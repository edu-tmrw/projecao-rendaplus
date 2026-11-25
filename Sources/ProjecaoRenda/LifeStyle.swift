import SwiftUI

enum LifeStyle {
    static let pt = Locale(identifier: "pt_BR")
    static let mint = Color(red: 0.39, green: 0.91, blue: 0.73)
    static let amber = Color(red: 1, green: 0.75, blue: 0.41)
    static let blue = Color(red: 0.57, green: 0.76, blue: 1)
    static let teal = Color(red: 0.10, green: 0.54, blue: 0.46)
    static let names = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
    static func money(_ v: Double, cents: Bool = false) -> String {
        v.formatted(.currency(code: "BRL").locale(pt).precision(.fractionLength(cents ? 2 : 0)))
    }
    static func number(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.locale(pt).precision(.fractionLength(digits)))
    }
    static func month(_ id: Int) -> String { "\(names[id % 12])/\(id / 12)" }
    static func date(_ d: LocalDate) -> String { String(format: "%02d/%02d/%04d", d.day, d.month, d.year) }
}
