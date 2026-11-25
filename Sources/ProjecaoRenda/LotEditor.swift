import SwiftUI

struct LotEditor: View {
    private enum Order: String, CaseIterable {
        case amount = "Valor a investir"
        case quantity = "Quantidade de títulos"
    }

    let quotes: [Int: LifetimeRendaQuote]
    let lot: SimulatorLot?
    let save: (SimulatorLot) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year: String
    @State private var date: Date
    @State private var price: String
    @State private var rate: String
    @State private var amount: String
    @State private var quantity: String
    @State private var order = Order.amount

    init(quotes: [Int: LifetimeRendaQuote], lot: SimulatorLot?, save: @escaping (SimulatorLot) -> Void) {
        self.quotes = quotes
        self.lot = lot
        self.save = save
        let today = LifetimeClock.today
        let next = quotes.keys.sorted().first { $0 > today.year }
        _year = State(initialValue: String(lot?.year ?? next ?? max(2030, today.year + 1)))
        _date = State(initialValue: LifetimeClock.date(lot?.date ?? today))
        _price = State(initialValue: lot.map { Self.number($0.amount / $0.quantity) } ?? "")
        _rate = State(initialValue: lot.map { Self.number($0.rate) } ?? "")
        _amount = State(initialValue: lot.map { Self.number($0.amount) } ?? "")
        _quantity = State(initialValue: lot.map { Self.number($0.quantity) } ?? "")
    }

    var body: some View {
        LifetimeSheet(title: lot == nil ? "Simular aporte" : "Editar aporte", width: 480) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Ano de início da renda")
                    HStack {
                        TextField("2045", text: $year)
                            .accessibilityLabel("Ano de início da renda")
                            .frame(width: 58)
                        Menu {
                            ForEach([2055, 2060, 2065], id: \.self) { target in
                                Button(String(target)) { year = String(target) }
                            }
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .fixedSize()
                        .accessibilityLabel("Escolher ano de início da renda")
                        if !quotes.isEmpty {
                            Menu("Usar cotação") {
                                ForEach(quotes.keys.sorted(), id: \.self) { year in
                                    if let quote = quotes[year] {
                                        Button(String(year)) {
                                            self.year = String(year)
                                            self.price = Self.number(quote.price)
                                            self.rate = Self.number(quote.rate)
                                        }
                                    }
                                }
                            }
                            .help("Preenche o preço e a taxa de compra divulgados pelo Tesouro")
                        }
                    }
                }
                GridRow {
                    Text("Data do aporte")
                    DatePicker("Data do aporte", selection: $date, in: allowedDates, displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow {
                    Text("Preço por título (R$)")
                    TextField("0,00", text: $price).accessibilityLabel("Preço por título")
                }
                GridRow {
                    Text("Taxa real anual (%)")
                    TextField("0,00", text: $rate).accessibilityLabel("Taxa real anual")
                }
                GridRow {
                    Picker("Modo do aporte", selection: $order) {
                        ForEach(Order.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    if order == .amount {
                        TextField("R$ 0,00", text: $amount).accessibilityLabel("Valor a investir")
                    } else {
                        TextField("0,000", text: $quantity).accessibilityLabel("Quantidade de títulos")
                    }
                }
            }
            if let year = Int(year), let quote = quotes[year], Self.parse(price) == quote.price, Self.parse(rate) == quote.rate {
                Text("Cotação publicada em \(LifeStyle.date(quote.date)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let position, let settlement = position.settlement {
                Text("\(LifeStyle.money(position.amount, cents: true)) · \(LifeStyle.number(position.quantity, digits: 4)) títulos · liquidação estimada em \(LifeStyle.date(settlement))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Informe o preço, a taxa e o aporte. A liquidação precisa ocorrer antes do ano de início da renda.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } actions: {
            Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Salvar aporte") {
                guard let position, position.settlement != nil else { return }
                save(position)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(position?.settlement == nil)
        }
    }

    private var allowedDates: ClosedRange<Date> {
        LifetimeClock.date(min(lot?.date ?? LifetimeClock.today, LifetimeClock.today))...LifetimeClock.date(LifetimeClock.local(2150, 12, 31))
    }

    private var position: SimulatorLot? {
        guard let year = Int(year), let price = Self.parse(price), price > 0,
              let rate = Self.parse(rate) else { return nil }
        let orderValue = Self.parse(order == .amount ? amount : quantity)
        guard let orderValue, orderValue > 0 else { return nil }
        let cost = order == .amount ? orderValue : orderValue * price
        let units = order == .quantity ? orderValue : orderValue / price
        return SimulatorLot(id: lot?.id ?? UUID(), year: year, date: LifetimeClock.localDate(date),
                            amount: cost, quantity: units, rate: rate)
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.locale(LifeStyle.pt).grouping(.never).precision(.fractionLength(0...10)))
    }

    private static func parse(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimal = value.replacingOccurrences(of: ",", with: ".")
        if decimal.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            return Double(decimal)
        }
        return nil
    }
}
