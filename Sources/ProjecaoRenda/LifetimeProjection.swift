import Foundation

struct LifetimePlan: Codable, Equatable {
    struct Person: Codable, Equatable {
        var name: String
        var birth: LocalDate
        func age(on date: LocalDate) -> Int {
            date.year - birth.year - ((date.month, date.day) < (birth.month, birth.day) ? 1 : 0)
        }
    }
    struct Purchase: Codable, Equatable, Identifiable {
        var id: String
        var date: LocalDate
        var settlement: LocalDate
        var quantity: Double
        var amount: Double
        var rate: Double // Annual percentage above inflation.
        var conversionYear: Int? = nil
        var quoteBaseIndex: Double? = nil
    }
    var people: [Person] // The horizon is the first person's 100th birthday.
    var conversionYear: Int
    var purchases: [Purchase]
    var start: LocalDate
    var end: LocalDate
    var total: Double { purchases.reduce(0) { $0 + $1.amount } }
    var quantity: Double { purchases.reduce(0) { $0 + $1.quantity } }
}

enum LifetimeClock {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()
    static func local(_ y: Int, _ m: Int, _ d: Int) -> LocalDate {
        try! LocalDate(String(format: "%04d-%02d-%02d", y, m, d))
    }
    static func month(_ d: LocalDate) -> Int { d.year * 12 + d.month - 1 }
    static func first(_ month: Int) -> LocalDate { local(month / 12, month % 12 + 1, 1) }
    static func date(_ d: LocalDate) -> Date { calendar.date(from: .init(year: d.year, month: d.month, day: d.day))! }
    static func day(_ d: LocalDate) -> Int { Int(date(d).timeIntervalSince1970 / 86400) }
    static var today: LocalDate {
        var cal = calendar; cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return local(c.year!, c.month!, c.day!)
    }
}

// Brazilian financial-market calendar. Weekday counts are [settlement, payment).
private struct TreasuryDays {
    private let origin: Int
    private var counts: [Int]
    private var closed: Set<Int> = []

    init(from: LocalDate, through: LocalDate) {
        origin = LifetimeClock.day(from)
        counts = [0]
        for year in from.year...through.year {
            for (month, day) in [(1,1),(4,21),(5,1),(9,7),(10,12),(11,2),(11,15),(11,20),(12,25)] {
                closed.insert(LifetimeClock.day(LifetimeClock.local(year, month, day)))
            }
            // Gregorian computus; Carnival, Good Friday and Corpus Christi follow Easter.
            let a = year % 19, b = year / 100, c = year % 100, f = (b + 8) / 25
            let h = (19*a + b - b/4 - (b-f+1)/3 + 15) % 30
            let l = (32 + 2*(b%4) + 2*(c/4) - h - c%4) % 7
            let n = h + l - 7*((a + 11*h + 22*l)/451) + 114
            let easter = LifetimeClock.day(LifetimeClock.local(year, n/31, n%31+1))
            for offset in [-48,-47,-2,60] { closed.insert(easter + offset) }
        }
        var count = 0
        for day in origin...LifetimeClock.day(through) {
            if isOpen(day) { count += 1 }
            counts.append(count)
        }
    }
    func isOpen(_ day: Int) -> Bool { (day + 3) % 7 < 5 && !closed.contains(day) }
    func index(_ day: Int) -> Int { counts[day - origin] }
    func paymentDay(_ month: Int) -> Int {
        var day = LifetimeClock.day(LifetimeClock.first(month)) + 14
        while !isOpen(day) { day += 1 }
        return day
    }
}

struct LifetimeAssumptions: Codable, Equatable {
    var annual = 4.0
    var plannedYears: [Int: Double] = [:]
    var actualYears: [Int: Double] = [:]
    var plannedMonths: [Int: Double] = [:]
    var actualMonths: [Int: Double] = [:]
    // Statement amounts are always entered in nominal BRL at that date.
    var balances: [Int: Double] = [:]
    var withdrawals: [Int: Double] = [:]

    func planned(_ month: Int) -> Double {
        plannedMonths[month] ?? Self.monthly(plannedYears[month / 12] ?? annual)
    }
    func actual(_ month: Int) -> Double? {
        actualMonths[month] ?? actualYears[month / 12].map(Self.monthly)
    }
    static func monthly(_ year: Double) -> Double { expm1(log1p(year / 100) / 12) * 100 }
}

struct LifetimeMonth: Identifiable {
    let id: Int
    let close: LocalDate
    let paymentDate: LocalDate?
    let installment: Int?
    let balance, withdrawal: Double // Contractual purchasing power at the base date.
    let nominalIncomeTax: Double // Estimated withholding in BRL on the payment date.
    let forecastIndex, index, paymentIndex: Double
    let plannedIPCA, actualIPCA, appliedIPCA: Double?
    let observedBalance, observedWithdrawal: Double?
    var contribution = 0.0
    var assetsBalance = 0.0
    var assetsWithdrawal = 0.0
    var assetsNominalWithdrawal = 0.0
    var assetsTax = 0.0

    var realRendaIncomeAfterTax: Double { withdrawal - nominalIncomeTax / paymentIndex }
}

struct LifetimeProjection {
    static let installmentCount = 240
    static let estimatedIncomeTaxRate = 0.15
    let plan: LifetimePlan
    let months: [LifetimeMonth]
    let todayIndex: Double
    let conversion: Int
    let lastPayment: Int
    let isSimulation: Bool
    let includesRenda: Bool
    let hasGenericAssets: Bool
    let levelNetIncomeAvailable: Bool
    let firstDistribution: Int
    let distributionEnd: Int
    let years: [Int]
    let groups: [Int: [LifetimeMonth]]
    var start: Int { months[0].id }
    var end: Int { months[months.count - 1].id }

    static func simulatedSettlement(on date: LocalDate, conversionYear: Int) -> LocalDate? {
        let limit = LifetimeClock.local(conversionYear, 1, 1)
        guard date < limit else { return nil }
        let maxDay = min(LifetimeClock.day(limit), LifetimeClock.day(date) + 15)
        let end = LifetimeClock.calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(maxDay) * 86400))
        let calendar = TreasuryDays(from: date, through: LifetimeClock.local(end.year!, end.month!, end.day!))
        var day = LifetimeClock.day(date) + 1
        while day < maxDay {
            if calendar.isOpen(day) {
                let parts = LifetimeClock.calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) * 86400))
                return LifetimeClock.local(parts.year!, parts.month!, parts.day!)
            }
            day += 1
        }
        return nil
    }

    private static func taxRate(holdingDays: Int) -> Double {
        switch holdingDays {
        case ...180: 0.225
        case ...360: 0.20
        case ...720: 0.175
        default: estimatedIncomeTaxRate
        }
    }

    init(plan: LifetimePlan, assumptions: LifetimeAssumptions, today: LocalDate,
         genericAssets: LifetimeGenericAssets? = nil, scope: LifetimeInvestmentScope = .combined,
         levelNetIncome: Bool = false) {
        self.plan = plan
        let opening = plan.start
        let first = LifetimeClock.month(opening), final = LifetimeClock.month(plan.end)
        let conversion = plan.conversionYear * 12
        self.conversion = conversion
        let count = Self.installmentCount
        isSimulation = genericAssets != nil
        includesRenda = scope.includesRenda
        hasGenericAssets = isSimulation && scope.includesPortfolio
        let purchases = scope.includesRenda ? plan.purchases.filter { $0.amount > 0 } : []
        let activeYears = Set(purchases.map { $0.conversionYear ?? plan.conversionYear })
        let lastYear = activeYears.max() ?? plan.conversionYear
        lastPayment = lastYear * 12 + count - 1
        let calendarEnd = max(plan.end, LifetimeClock.local(lastYear + 20, 1, 1))
        let calendar = TreasuryDays(from: opening, through: calendarEnd)
        let conversions = activeYears.map { $0 * 12 }
        let calendars = Dictionary(uniqueKeysWithValues: conversions.map { start in
            (start, (start..<(start + count)).map { calendar.paymentDay($0) })
        })

        // Each lot keeps the contracted rate, cost basis and its own 240 settlement dates.
        let lots = purchases.map { buy in
            let start = (buy.conversionYear ?? plan.conversionYear) * 12
            let days = calendars[start]!
            let origin = calendar.index(LifetimeClock.day(buy.settlement))
            let growth = log1p(buy.rate / 100) / 252
            var remaining = [Double](repeating: 0, count: count + 1)
            for i in (0..<count).reversed() {
                remaining[i] = remaining[i + 1] + exp(-growth * Double(calendar.index(days[i]) - origin))
            }
            return (buy: buy, start: start, days: days, origin: origin, growth: growth,
                    remaining: remaining, payment: buy.amount / (buy.quoteBaseIndex ?? 1) / remaining[0])
        }
        var forecast = 1.0, index = 1.0, todayIndex = 1.0
        var rows: [LifetimeMonth] = []
        for month in first...final {
            let monthStart = LifetimeClock.first(month)
            let monthEnd = MarketMonth.end(monthStart)
            let close = min(monthEnd, plan.end), closeDay = LifetimeClock.day(close)
            let startDay = month == first ? opening.day : 0
            let portion = Double(close.day - startDay) / Double(monthEnd.day)
            let expected = assumptions.planned(month)
            let actual = month < LifetimeClock.month(today) ? assumptions.actual(month) : nil
            let applied = actual ?? expected
            let openingIndex = index
            forecast *= pow(1 + expected / 100, portion)
            index *= pow(1 + applied / 100, portion)
            if today >= close { todayIndex = index }
            else if LifetimeClock.month(today) == month, today >= opening {
                todayIndex = openingIndex * pow(1 + applied / 100, Double(today.day - startDay) / Double(monthEnd.day))
            }
            // All RendA+ cohorts that pay in a given month share the same business day.
            let paymentMonth = conversions.contains { (0..<count).contains(month - $0) }
            let commonDay = paymentMonth ? calendar.paymentDay(month) : nil
            let payDay = commonDay.flatMap { $0 <= closeDay ? $0 - LifetimeClock.day(monthStart) + 1 : nil }
            let payDate = payDay.map { LifetimeClock.local(monthStart.year, monthStart.month, $0) }
            let payIndex = payDay.map { openingIndex * pow(1 + applied/100, Double($0 - startDay) / Double(monthEnd.day)) } ?? index
            let installment = payDay.flatMap { _ in
                let active = conversions.filter { (0..<count).contains(month - $0) }
                let start = active.contains(conversion) ? conversion : active.max()
                return start.map { month - $0 + 1 }
            }
            var balance = 0.0, withdrawal = 0.0
            var nominalIncomeTax = 0.0
            for lot in lots where lot.buy.date <= close {
                let i = month - lot.start
                let pays = (0..<count).contains(i) && payDay != nil
                let paid = min(count, max(0, i + (pays ? 1 : 0)))
                let elapsed = max(0, calendar.index(closeDay) - lot.origin)
                balance += lot.payment * lot.remaining[paid] * exp(lot.growth * Double(elapsed))
                if pays {
                    withdrawal += lot.payment
                    let gain = max(0, lot.payment * payIndex - lot.buy.amount / Double(count))
                    let rate = lot.buy.quoteBaseIndex == nil
                        ? Self.estimatedIncomeTaxRate
                        : Self.taxRate(holdingDays: lot.days[i] - LifetimeClock.day(lot.buy.settlement))
                    nominalIncomeTax += gain * rate
                }
            }
            rows.append(.init(id: month, close: close, paymentDate: payDate, installment: installment,
                              balance: balance, withdrawal: withdrawal, nominalIncomeTax: nominalIncomeTax, forecastIndex: forecast, index: index,
                              paymentIndex: payIndex, plannedIPCA: expected, actualIPCA: actual, appliedIPCA: applied,
                              observedBalance: close <= today ? assumptions.balances[month] : nil,
                              observedWithdrawal: payDate.map { $0 <= today } == true ? assumptions.withdrawals[month] : nil))
        }
        if hasGenericAssets, let genericAssets {
            levelNetIncomeAvailable = genericAssets.apply(to: &rows, today: today, todayIndex: todayIndex,
                                                          conversion: conversion, levelNetIncome: levelNetIncome)
        } else {
            levelNetIncomeAvailable = false
        }
        if isSimulation {
            firstDistribution = rows.first { $0.withdrawal > 0 || $0.assetsWithdrawal > 0 }?.id ?? conversion
            distributionEnd = rows.last { $0.withdrawal > 0 || $0.assetsWithdrawal > 0 }?.id ?? firstDistribution
        } else {
            firstDistribution = conversion
            distributionEnd = lastPayment
        }
        months = rows
        self.todayIndex = todayIndex
        groups = Dictionary(grouping: rows) { $0.id / 12 }
        years = groups.keys.sorted()
    }
    func balance(_ row: LifetimeMonth, nominal: Bool) -> Double {
        (row.balance + row.assetsBalance) * (nominal ? row.index : todayIndex)
    }

    func contribution(_ row: LifetimeMonth, nominal: Bool) -> Double {
        row.contribution * (nominal ? row.index : todayIndex)
    }

    func invested(initialPortfolioBalance: Double, nominal: Bool) -> Double {
        let portfolio = hasGenericAssets
            ? months.reduce(initialPortfolioBalance) { $0 + contribution($1, nominal: nominal) }
            : 0
        guard includesRenda else { return portfolio }
        return plan.purchases.reduce(portfolio) { total, purchase in
            if nominal { return total + purchase.amount }
            let index = purchase.quoteBaseIndex ?? priceIndex(on: purchase.date)
            return total + observed(purchase.amount, index: index, nominal: false)
        }
    }

    private func priceIndex(on date: LocalDate) -> Double {
        let month = LifetimeClock.month(date)
        guard month >= start, month <= end else { return todayIndex }
        let row = months[month - start]
        let monthEnd = MarketMonth.end(LifetimeClock.first(month))
        let remaining = Double(row.close.day - date.day) / Double(monthEnd.day)
        return row.index / pow(1 + (row.appliedIPCA ?? 0) / 100, remaining)
    }

    func assetsIncome(_ row: LifetimeMonth, nominal: Bool, afterTax: Bool) -> Double {
        let gross = nominal ? row.assetsNominalWithdrawal : row.assetsWithdrawal * todayIndex
        return afterTax ? gross - observed(row.assetsTax, index: row.index, nominal: nominal) : gross
    }

    func income(_ row: LifetimeMonth, nominal: Bool, afterTax: Bool = false) -> Double {
        let gross = row.withdrawal * (nominal ? row.paymentIndex : todayIndex)
        let bondIncome = afterTax ? gross - observed(row.nominalIncomeTax, index: row.paymentIndex, nominal: nominal) : gross
        return bondIncome + assetsIncome(row, nominal: nominal, afterTax: afterTax)
    }

    func incomeTax(_ row: LifetimeMonth, nominal: Bool) -> Double {
        observed(row.nominalIncomeTax, index: row.paymentIndex, nominal: nominal)
            + observed(row.assetsTax, index: row.index, nominal: nominal)
    }

    func observed(_ amount: Double, index: Double, nominal: Bool) -> Double { nominal ? amount : amount / index * todayIndex }
}
