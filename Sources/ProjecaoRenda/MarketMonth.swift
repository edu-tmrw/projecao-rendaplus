import Foundation

public enum MarketMonth {
    public static func start(_ date: LocalDate) -> LocalDate {
        try! LocalDate(String(format: "%04d-%02d-01", date.year, date.month))
    }
    public static func end(_ date: LocalDate) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = calendar.date(from: DateComponents(year: date.year, month: date.month, day: 1))!
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first)!
        let parts = calendar.dateComponents([.year, .month, .day], from: end)
        return try! LocalDate(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
    }
    /// A conservative boundary for legacy observations. Newly fetched monthly
    /// archives explicitly carry monthlyClose, including holiday/illiquid closes.
    public static func lastWeekday(_ date: LocalDate) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let last = end(date)
        var value = calendar.date(from: DateComponents(year: last.year, month: last.month, day: last.day))!
        while calendar.isDateInWeekend(value) { value = calendar.date(byAdding: .day, value: -1, to: value)! }
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return try! LocalDate(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
    }
}
