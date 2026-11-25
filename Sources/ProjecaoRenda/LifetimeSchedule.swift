import SwiftUI

struct LifetimeSchedule: View {
    let projection: LifetimeProjection
    let nominal: Bool
    let afterTax: Bool
    @State private var expanded: Set<Int> = []
    @State private var onlyPayments = false

    var body: some View {
        let years = projection.years.filter { !onlyPayments || ($0 >= projection.firstDistribution / 12 && $0 <= projection.distributionEnd / 12) }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fluxo por período").font(.title2.bold())
                Spacer()
                Toggle("Só distribuição", isOn: $onlyPayments).toggleStyle(.checkbox)
                Button(expanded.isSuperset(of: years) ? "Recolher todos" : "Expandir todos") {
                    if expanded.isSuperset(of: years) { expanded.subtract(years) } else { expanded.formUnion(years) }
                }
            }.padding(.bottom, 14)
            HStack(spacing: 10) {
                Text("Período").frame(maxWidth: .infinity, alignment: .leading)
                if !projection.plan.people.isEmpty { Text("Idade").frame(width: 54) }
                Text("IPCA prev. / real").frame(width: 120, alignment: .trailing)
                if projection.hasGenericAssets {
                    Text("Aportes").frame(width: 95, alignment: .trailing)
                }
                Text("Saldo bruto final").frame(width: 127, alignment: .trailing)
                Text(afterTax ? "Retiradas após IR" : "Retiradas brutas").frame(width: 135, alignment: .trailing)
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            LazyVStack(spacing: 0) {
                let firstPurchaseYear = projection.includesRenda ? projection.plan.purchases.map(\.date.year).min() : nil
                let hasDistribution = projection.months.contains { $0.withdrawal > 0 || $0.assetsWithdrawal > 0 }
                ForEach(years, id: \.self) { year in
                    let rows = projection.groups[year]!
                    VStack(spacing: 0) {
                        Button {
                            if expanded.contains(year) { expanded.remove(year) } else { expanded.insert(year) }
                        } label: {
                            HStack(spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: expanded.contains(year) ? "chevron.down" : "chevron.right").font(.caption).frame(width: 12)
                                    Text(String(year)).font(.headline)
                                    if year == firstPurchaseYear { phase("Compra", .blue) }
                                    if hasDistribution, year == projection.firstDistribution / 12 { phase("Início da renda", LifeStyle.teal) }
                                    if projection.hasGenericAssets, year == projection.conversion / 12, year != projection.firstDistribution / 12 {
                                        phase("Fim dos aportes", LifeStyle.teal)
                                    }
                                    if firstPurchaseYear != nil, year == projection.lastPayment / 12 { phase(projection.isSimulation ? "Fim do RendA+" : "Última parcela", .orange) }
                                    if year == projection.end / 12, projection.plan.people.first?.age(on: projection.plan.end) == 100 {
                                        phase("100 anos", .purple)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                amounts(rows)
                            }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Detalhar \(String(year))")
                        if expanded.contains(year) {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 10) {
                                        HStack(spacing: 8) {
                                            Text(LifeStyle.names[row.id % 12].capitalized)
                                            if !projection.isSimulation, let i = row.installment, let date = row.paymentDate {
                                                Text("#\(i) · dia \(date.day)").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }.padding(.leading, 21).frame(maxWidth: .infinity, alignment: .leading)
                                        amounts([row])
                                    }
                                    if row.observedBalance != nil || row.observedWithdrawal != nil {
                                        HStack {
                                            Text("Extrato informado").padding(.leading, 21); Spacer()
                                            Text(row.observedBalance.map { LifeStyle.money(projection.observed($0, index: row.index, nominal: nominal)) } ?? "—")
                                                .frame(width: 127, alignment: .trailing)
                                            Text(row.observedWithdrawal.map { LifeStyle.money(projection.observed($0, index: row.paymentIndex, nominal: nominal)) } ?? "—")
                                                .frame(width: 135, alignment: .trailing)
                                        }.foregroundStyle(LifeStyle.teal).font(.caption)
                                    }
                                }.font(.callout).padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.quaternary.opacity(0.22))
                            }
                        }
                        Divider()
                    }
                }
            }
            Text("O saldo já desconta as retiradas. Nos anos parciais, os totais abrangem apenas os meses exibidos.").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
        }
    }

    @ViewBuilder private func amounts(_ rows: [LifetimeMonth]) -> some View {
        let last = rows[rows.count-1]
        let rates = rows.compactMap(\.plannedIPCA)
        let actual = rows.compactMap(\.actualIPCA)
        if let person = projection.plan.people.first { Text(String(person.age(on: last.close))).frame(width: 54) }
        Text("\(percent(rates)) / \(actual.count == rows.count ? percent(actual) : "—")")
            .font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
            .help("IPCA dos meses exibidos. Abra o ano para ver os índices realizados disponíveis.")
        if projection.hasGenericAssets {
            let contribution = rows.reduce(0) { $0 + projection.contribution($1, nominal: nominal) }
            Text(contribution > 0 ? LifeStyle.money(contribution) : "—")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 95, alignment: .trailing)
        }
        Text(LifeStyle.money(projection.balance(last, nominal: nominal))).monospacedDigit().frame(width: 127, alignment: .trailing)
        let income = rows.reduce(0) { $0 + projection.income($1, nominal: nominal, afterTax: afterTax) }
        Text(income > 0 ? LifeStyle.money(income) : "—").monospacedDigit()
            .foregroundStyle(income > 0 ? AnyShapeStyle(LifeStyle.teal) : AnyShapeStyle(.secondary)).frame(width: 135, alignment: .trailing)
    }
    private func percent(_ rates: [Double]) -> String {
        LifeStyle.number((rates.reduce(1.0) { $0 * (1 + $1/100) } - 1) * 100) + "%"
    }
    private func phase(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(color)
    }
}
