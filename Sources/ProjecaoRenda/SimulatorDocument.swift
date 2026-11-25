import Foundation

struct SimulatorLot: Codable, Equatable, Identifiable {
    var id = UUID()
    var year: Int
    var date: LocalDate
    var amount: Double
    var quantity: Double
    var rate: Double

    var settlement: LocalDate? {
        guard (2023...2150).contains(date.year), (2025...2150).contains(year),
              (0.01...1_000_000_000).contains(amount), (0.000_001...10_000_000).contains(quantity),
              (-20...30).contains(rate) else { return nil }
        return LifetimeProjection.simulatedSettlement(on: date, conversionYear: year)
    }
}

struct SimulatorScenario: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var annualInflation = 4.0
    var nominal = false
    var afterTax = true
    var simulated: [SimulatorLot] = []
    var assets = LifetimeGenericAssets()
    var levelsIncome = false
    var portfolioYear: Int?

    var hasPortfolio: Bool { assets.initial > 0 || assets.contribution > 0 }

    func initialPortfolioIncome(in projection: LifetimeProjection, today: LocalDate) -> Double? {
        if levelsIncome {
            let start = max(projection.conversion, LifetimeClock.month(today) + 1)
            return projection.months.first { $0.id == start }.map {
                projection.income($0, nominal: nominal, afterTax: afterTax)
            }
        }
        return projection.months.first { $0.assetsWithdrawal > 0 }.map {
            projection.assetsIncome($0, nominal: nominal, afterTax: afterTax)
        }
    }
}

struct SimulatorDocument: Codable, Equatable {
    var birth: LocalDate?
    var scenarios = [SimulatorScenario(name: "Cenário principal")]

    static func example(on today: LocalDate) -> Self {
        // Reference buy prices from the Tesouro Transparente archive (2026-11-19).
        // The example overrides the published rates by design.
        let samples = [(2055, 331.70), (2060, 231.10)]
        let amount = 100_000.0
        let lots = samples.compactMap { year, price -> SimulatorLot? in
            let lot = SimulatorLot(year: year, date: today, amount: amount,
                                   quantity: amount / price, rate: 7.5)
            return lot.settlement == nil ? nil : lot
        }
        return Self(scenarios: [SimulatorScenario(name: "Exemplo RendA+", simulated: lots)])
    }

    func projection(for scenario: SimulatorScenario, today: LocalDate) -> LifetimeProjection? {
        let positions = scenario.simulated.compactMap { lot in
            lot.settlement.map { (lot: lot, settlement: $0) }
        }
        guard !positions.isEmpty || scenario.hasPortfolio else { return nil }

        let firstBondYear = positions.map(\.lot.year).min()
        let portfolioYear = scenario.portfolioYear ?? firstBondYear ?? max(2050, today.year + 1)
        let conversion = scenario.hasPortfolio ? portfolioYear : firstBondYear ?? portfolioYear
        let lastBondYear = positions.map(\.lot.year).max() ?? conversion
        let latestYear = scenario.hasPortfolio ? max(lastBondYear, conversion) : lastBondYear
        let opening = min(positions.map(\.lot.date).min() ?? today, today)
        let todayEnd = MarketMonth.end(today)
        let paymentEnd = LifetimeClock.local(latestYear + 19, 12, 31)
        let people = birth.map { [LifetimePlan.Person(name: "Idade", birth: $0)] } ?? []
        let lifetimeEnd = birth.flatMap { birth in
            LifetimeClock.calendar.date(byAdding: .year, value: 100, to: LifetimeClock.date(birth))
        }.map(LifetimeClock.localDate)
        let end = max(todayEnd, paymentEnd, lifetimeEnd ?? paymentEnd)
        let annual = (-10...30).contains(scenario.annualInflation) ? scenario.annualInflation : 4
        let lots = positions.map { lot, settlement in
            LifetimePlan.Purchase(id: lot.id.uuidString, date: lot.date, settlement: settlement,
                                  quantity: lot.quantity, amount: lot.amount, rate: lot.rate,
                                  conversionYear: lot.year,
                                  quoteBaseIndex: inflationIndex(from: opening, to: lot.date, annual: annual))
        }
        let plan = LifetimePlan(people: people, conversionYear: conversion, purchases: lots, start: opening, end: end)
        return LifetimeProjection(plan: plan, assumptions: .init(annual: annual), today: today,
                                  genericAssets: scenario.assets, scope: scenario.hasPortfolio ? .combined : .renda,
                                  levelNetIncome: scenario.hasPortfolio && scenario.levelsIncome)
    }

    private func inflationIndex(from opening: LocalDate, to date: LocalDate, annual: Double) -> Double {
        let firstMonth = LifetimeClock.month(opening)
        let lastMonth = LifetimeClock.month(date)
        let openingFraction = Double(opening.day) / Double(MarketMonth.end(opening).day)
        let closingFraction = Double(date.day) / Double(MarketMonth.end(date).day)
        let elapsedMonths = Double(lastMonth - firstMonth) + closingFraction - openingFraction
        return exp(log1p(annual / 100) * elapsedMonths / 12)
    }
}

extension LifetimeClock {
    static func localDate(_ date: Date) -> LocalDate {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return local(components.year!, components.month!, components.day!)
    }
}
