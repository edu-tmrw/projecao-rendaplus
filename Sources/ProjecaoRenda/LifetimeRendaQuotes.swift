import Foundation

struct LifetimeRendaQuote: Codable, Equatable, Sendable {
    let year: Int
    let date: LocalDate
    let price: Double
    let rate: Double
    var time: String? = nil
}

enum LifetimeRendaQuotes {
    static let source = URL(string: "https://www.tesourotransparente.gov.br/ckan/dataset/df56aa42-484a-4a59-8184-7676580c81e3/resource/796d2059-14e9-44e3-80c9-2d9e30b405c1/download/precotaxatesourodireto.csv")!

    static func fetch() async throws -> [Int: LifetimeRendaQuote] {
        let request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try await Task.detached(priority: .userInitiated) { try parse(data) }.value
    }

    static func parse(_ data: Data) throws -> [Int: LifetimeRendaQuote] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }
        var quotes: [Int: LifetimeRendaQuote] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("Tesouro Renda+ Aposentadoria Extra;") {
            let columns = line.split(separator: ";", omittingEmptySubsequences: false)
            guard columns.count >= 6,
                  let maturity = date(columns[1]), maturity.month == 12,
                  let observed = date(columns[2]),
                  let price = number(columns[5]), price.isFinite, price > 0,
                  let rate = number(columns[3]), rate.isFinite, rate > -100 else { continue }
            let year = maturity.year - 19
            guard observed.year < year, quotes[year].map({ $0.date < observed }) ?? true else { continue }
            quotes[year] = LifetimeRendaQuote(year: year, date: observed, price: price, rate: rate)
        }
        guard !quotes.isEmpty else { throw URLError(.cannotParseResponse) }
        return quotes
    }

    private static func date(_ raw: Substring) -> LocalDate? {
        let parts = raw.split(separator: "/")
        guard parts.count == 3 else { return nil }
        return try? LocalDate("\(parts[2])-\(parts[1])-\(parts[0])")
    }

    private static func number(_ raw: Substring) -> Double? {
        Double(raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
    }
}
