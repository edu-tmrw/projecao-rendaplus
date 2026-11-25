import Foundation

public enum LocalDateError: Error, Equatable, Sendable {
    case invalid(String)
}

public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public init(_ value: String) throws {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
            throw LocalDateError.invalid(value)
        }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw LocalDateError.invalid(value)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(
                  year: year,
                  month: month,
                  day: day
              ) else {
            throw LocalDateError.invalid(value)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
