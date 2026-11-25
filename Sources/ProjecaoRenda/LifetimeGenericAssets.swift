import Foundation

enum LifetimeInvestmentScope: String, CaseIterable, Codable {
    case combined, portfolio, renda

    var title: String {
        switch self {
        case .combined: "Os dois"
        case .portfolio: "Carteira genérica"
        case .renda: "RendA+"
        }
    }

    var includesPortfolio: Bool { self != .renda }
    var includesRenda: Bool { self != .portfolio }
}

struct LifetimeGenericAssets: Codable, Equatable {
    var initial: Double = 0
    var contribution: Double = 0
    var realRate: Double = 6
    static let estimatedTaxRate = 0.15

    func apply(to rows: inout [LifetimeMonth], today: LocalDate, todayIndex: Double,
               conversion: Int, levelNetIncome: Bool) -> Bool {
        let todayMonth = LifetimeClock.month(today)
        let firstWithdrawal = max(todayMonth + 1, conversion)
        let monthlyRate = expm1(log1p(realRate / 100) / 12)
        var assets = initial / todayIndex
        var cost = initial
        var payment: Double?
        var netTarget: Double?

        for index in rows.indices where rows[index].id >= todayMonth {
            var row = rows[index]
            if row.id > todayMonth { assets *= 1 + monthlyRate }
            if row.id > todayMonth && row.id < conversion {
                row.contribution = contribution / row.index
                assets += row.contribution
                cost += contribution
            }

            if row.id >= firstWithdrawal {
                if levelNetIncome && row.id == firstWithdrawal {
                    netTarget = constantIncome(for: rows[index...], assets: assets, cost: cost, monthlyRate: monthlyRate)
                }
                if payment == nil {
                    let count = Double(rows.count - index)
                    let presentValue = abs(monthlyRate) < 1e-12
                        ? count
                        : (1 + monthlyRate) * -expm1(-count * log1p(monthlyRate)) / monthlyRate
                    payment = assets / presentValue
                }
                let requested: Double
                if let netTarget {
                    let netNeeded = max(0, netTarget - row.realRendaIncomeAfterTax)
                    let costFraction = assets > 0 ? cost / (assets * row.index) : 0
                    requested = netNeeded / netFraction(costFraction: costFraction)
                } else {
                    requested = payment ?? 0
                }
                let gross = min(assets, requested)
                let fraction = assets > 0 ? gross / assets : 0
                let costReturned = cost * fraction
                let nominalGeneric = gross * row.index
                let tax = max(0, nominalGeneric - costReturned) * Self.estimatedTaxRate
                assets = max(0, assets - gross)
                cost = max(0, cost - costReturned)
                row.assetsWithdrawal = gross
                row.assetsTax = tax
                row.assetsNominalWithdrawal = nominalGeneric
            }
            row.assetsBalance = assets
            rows[index] = row
        }
        return netTarget != nil
    }

    private func netFraction(costFraction: Double) -> Double {
        1 - Self.estimatedTaxRate * max(0, 1 - costFraction)
    }

    private func constantIncome(for rows: ArraySlice<LifetimeMonth>, assets: Double,
                                cost: Double, monthlyRate: Double) -> Double? {
        guard assets > 0 else { return nil }
        let logGrowth = log1p(monthlyRate)
        var incomeWeight = 0.0
        var bondPresentValue = 0.0
        var largestBondPayment = 0.0
        for (offset, row) in rows.enumerated() {
            let discount = exp(-Double(offset) * logGrowth)
            // Withdrawals remove capital and cost basis in the same proportion.
            // Their ratio evolves with investment growth and inflation alone.
            let costFraction = (cost / assets) * (discount / row.index)
            let weight = discount / netFraction(costFraction: costFraction)
            let bond = row.realRendaIncomeAfterTax
            incomeWeight += weight
            bondPresentValue += bond * weight
            largestBondPayment = max(largestBondPayment, bond)
        }
        let target = (assets + bondPresentValue) / incomeWeight
        guard target.isFinite, target >= largestBondPayment else { return nil }
        return target
    }
}
