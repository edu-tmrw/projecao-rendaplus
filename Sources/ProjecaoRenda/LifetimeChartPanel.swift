import Charts
import SwiftUI

private enum LifeRange: String, CaseIterable {
    case all = "Vida toda", accumulation = "Acumulação", income = "Distribuição", after = "Após o título"
}

struct LifetimeChartPanel: View {
    let projection: LifetimeProjection
    let nominal: Bool
    @Binding var afterTax: Bool
    @State private var range = LifeRange.all
    @State private var selected: Int?

    private var ranges: [LifeRange] {
        LifeRange.allCases.filter { $0 != .after || projection.distributionEnd < projection.end }
    }

    private var currentRange: LifeRange { ranges.contains(range) ? range : .all }

    private var domain: ClosedRange<Int> {
        let start = projection.start, end = projection.end
        switch currentRange {
        case .all: return start...end
        case .accumulation: return start...max(start, min(end, projection.firstDistribution - 1))
        case .income: return max(start, min(end, projection.firstDistribution))...max(start, min(end, projection.distributionEnd))
        case .after: return min(end, max(start, projection.distributionEnd + 1))...end
        }
    }
    var body: some View {
        let bounds = domain
        let focus = selected.map { min(bounds.upperBound, max(bounds.lowerBound, $0)) } ?? (currentRange == .all ? min(bounds.upperBound, max(bounds.lowerBound, projection.conversion - 1)) : bounds.lowerBound)
        let row = projection.months[focus - projection.start]
        let inRange = projection.months[(bounds.lowerBound - projection.start)...(bounds.upperBound - projection.start)]
        // Use the same withdrawal axis so switching tax basis shows the size of the deduction.
        let incomeCeiling = inRange.reduce(1.0) { maximum, month in
            let statement = month.observedWithdrawal.map { projection.observed($0, index: month.paymentIndex, nominal: nominal) } ?? 0
            return max(maximum, projection.income(month, nominal: nominal), projection.contribution(month, nominal: nominal), statement)
        }
        // Keep exact data for the cursor. Decimate only continuous drawing on the longest range.
        let stride = max(1, inRange.count / 170)
        let starts: Set<Int> = projection.includesRenda
            ? Set(projection.plan.purchases.compactMap(\.conversionYear).map { $0 * 12 }).union([projection.conversion])
            : []
        let firstContribution = projection.months.first { $0.contribution > 0 }.map { [$0.id] } ?? []
        let transitions = starts.union(starts.map { $0 + LifetimeProjection.installmentCount })
            .union([projection.firstDistribution, projection.distributionEnd + 1]).union(firstContribution)
        let points = inRange.filter {
            ($0.id - bounds.lowerBound) % stride == 0 || $0.id == bounds.upperBound ||
            transitions.contains($0.id) || transitions.contains($0.id + 1)
        }
        let hasRevision = nominal && inRange.contains { abs($0.forecastIndex - $0.index) > 0.000001 }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Evolução patrimonial", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                ForEach(ranges, id: \.self) { item in
                    Button(item == .after && projection.isSimulation ? "Após a renda" : item.rawValue) { range = item; selected = nil }
                        .buttonStyle(.plain).font(.caption.weight(.semibold))
                        .foregroundStyle(currentRange == item ? Color.black : Color.white.opacity(0.82))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(currentRange == item ? LifeStyle.mint : .white.opacity(0.09), in: Capsule())
                        .accessibilityAddTraits(currentRange == item ? .isSelected : [])
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 13) {
                Text(LifeStyle.money(projection.balance(row, nominal: nominal))).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                VStack(alignment: .leading, spacing: 3) {
                    Text("saldo bruto em \(LifeStyle.month(row.id))").foregroundStyle(.white.opacity(0.74))
                    ages(in: row, showNames: true).font(.caption)
                }
                Spacer()
                Text(row.id < projection.firstDistribution ? "Acumulação" : row.id <= projection.distributionEnd ? "Distribuição" : projection.isSimulation ? "Renda encerrada" : "Título encerrado")
                    .font(.caption.weight(.medium))
                if !projection.isSimulation, let n = row.installment { Text("\(n)/240").font(.caption.monospacedDigit()) }
            }
            Chart {
                if bounds.overlaps(projection.firstDistribution...projection.distributionEnd) {
                    RectangleMark(xStart: .value("Início da distribuição", max(bounds.lowerBound, projection.firstDistribution)),
                                  xEnd: .value("Fim da distribuição", min(bounds.upperBound, projection.distributionEnd)))
                        .foregroundStyle(LifeStyle.amber.opacity(0.045)).accessibilityHidden(true)
                }
                ForEach(points) { p in
                    AreaMark(x: .value("Mês", p.id), y: .value("Saldo", projection.balance(p, nominal: nominal)))
                        .foregroundStyle(LinearGradient(colors: [LifeStyle.mint.opacity(0.25), LifeStyle.mint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Mês", p.id), y: .value("Saldo", projection.balance(p, nominal: nominal)), series: .value("Curva", "Atualizada"))
                        .lineStyle(.init(lineWidth: 2.6)).foregroundStyle(LifeStyle.mint)
                    if hasRevision {
                        LineMark(x: .value("Mês", p.id), y: .value("Previsto", (p.balance + p.assetsBalance) * p.forecastIndex), series: .value("Curva", "Prevista"))
                            .lineStyle(.init(lineWidth: 1.4, dash: [4,4])).foregroundStyle(LifeStyle.blue)
                    }
                }
                ForEach(inRange.filter { $0.observedBalance != nil }) { p in
                    PointMark(x: .value("Mês", p.id), y: .value("Saldo realizado", projection.observed(p.observedBalance!, index: p.index, nominal: nominal)))
                        .symbol(.diamond).foregroundStyle(LifeStyle.amber)
                }
                if bounds.contains(projection.firstDistribution) {
                    RuleMark(x: .value("Início da renda", projection.firstDistribution)).foregroundStyle(.white.opacity(0.4)).lineStyle(.init(dash: [3, 4]))
                        .annotation(position: .top, spacing: 2) { Text("Início da renda").font(.caption2).foregroundStyle(.white.opacity(0.8)) }
                }
                if currentRange == .all, bounds.contains(projection.distributionEnd) {
                    RuleMark(x: .value("Última retirada", projection.distributionEnd)).foregroundStyle(.white.opacity(0.4)).lineStyle(.init(dash: [3, 4]))
                        .annotation(position: .top, spacing: 2) { Text("Fim da renda").font(.caption2).foregroundStyle(.white.opacity(0.8)) }
                }
                RuleMark(x: .value("Mês selecionado", focus)).foregroundStyle(.white.opacity(0.3))
                PointMark(x: .value("Mês selecionado", focus), y: .value("Saldo", projection.balance(row, nominal: nominal))).symbolSize(44).foregroundStyle(LifeStyle.mint)
            }
            .chartXScale(domain: bounds).chartXSelection(value: $selected).chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.12)); AxisValueLabel { axis(value) }
            } }.frame(height: 174)
            HStack {
                Label(afterTax ? "Retirada após IR" : "Retirada bruta", systemImage: "arrow.down.left").font(.caption.weight(.semibold))
                Text(LifeStyle.money(projection.income(row, nominal: nominal, afterTax: afterTax), cents: true)).monospacedDigit().font(.callout.bold()).foregroundStyle(LifeStyle.amber)
                if afterTax, projection.incomeTax(row, nominal: nominal) > 0 {
                    Text("IR estimado · \(LifeStyle.money(projection.incomeTax(row, nominal: nominal), cents: true))")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Picker("Retiradas", selection: $afterTax) {
                    Text("Brutas").tag(false)
                    Text(projection.isSimulation ? "Após IR" : "Após IR de 15%").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().environment(\.colorScheme, .dark)
                .help("Alterna o gráfico, os indicadores e a lista entre retiradas brutas e líquidas estimadas de IR.")
                if hasRevision { Text("– – Com o IPCA previsto").foregroundStyle(LifeStyle.blue).font(.caption) }
                if inRange.contains(where: { $0.observedBalance != nil || $0.observedWithdrawal != nil }) {
                    Text("◆ Extrato").font(.caption).foregroundStyle(LifeStyle.amber)
                }
            }
            if projection.hasGenericAssets {
                let total = projection.income(row, nominal: nominal, afterTax: afterTax)
                let generic = projection.assetsIncome(row, nominal: nominal, afterTax: afterTax)
                HStack(spacing: 16) {
                    if projection.includesRenda {
                        Text("RendA+ \(LifeStyle.money(total - generic, cents: true))")
                    }
                    Text("Carteira genérica \(LifeStyle.money(generic, cents: true))")
                    Label("Aportes \(LifeStyle.money(projection.contribution(row, nominal: nominal)))", systemImage: "arrow.up.right")
                        .foregroundStyle(LifeStyle.blue)
                }.font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Mês", p.id), y: .value(afterTax ? "Retirada líquida estimada" : "Retirada bruta", projection.income(p, nominal: nominal, afterTax: afterTax)))
                        .interpolationMethod(.stepEnd).foregroundStyle(LifeStyle.amber.opacity(0.3))
                    LineMark(x: .value("Mês", p.id), y: .value("Retiradas", projection.income(p, nominal: nominal, afterTax: afterTax)), series: .value("Fluxo", "Retiradas"))
                        .interpolationMethod(.stepEnd).foregroundStyle(LifeStyle.amber)
                }
                if projection.hasGenericAssets {
                    ForEach(points) { p in
                        LineMark(x: .value("Mês", p.id), y: .value("Aportes", projection.contribution(p, nominal: nominal)), series: .value("Fluxo", "Aportes"))
                            .interpolationMethod(.stepEnd).lineStyle(.init(lineWidth: 1.6, dash: [4, 3]))
                            .foregroundStyle(LifeStyle.blue)
                    }
                }
                ForEach(inRange.filter { $0.observedWithdrawal != nil }) { p in
                    PointMark(x: .value("Mês", p.id), y: .value("Retirada realizada", projection.observed(p.observedWithdrawal!, index: p.paymentIndex, nominal: nominal))).symbol(.diamond).foregroundStyle(.white)
                }
                RuleMark(x: .value("Mês selecionado", focus)).foregroundStyle(.white.opacity(0.3))
            }
            .chartXScale(domain: bounds).chartXSelection(value: $selected)
            .chartYScale(domain: 0...incomeCeiling)
            .chartXAxis { AxisMarks(values: ticks(bounds)) { value in
                AxisTick().foregroundStyle(.white.opacity(0.45))
                AxisValueLabel {
                    if let month = value.as(Int.self), projection.start...projection.end ~= month {
                        VStack(spacing: 2) {
                            Text(String(month / 12)).font(.caption2).foregroundStyle(.white.opacity(0.8))
                            ages(in: projection.months[month - projection.start], showNames: false)
                                .font(.system(size: 9))
                        }
                    }
                }
            } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.1)); AxisValueLabel { axis(value) }
            } }.frame(height: 82)
        }
        .foregroundStyle(.white).padding(20)
        .background(LinearGradient(colors: [Color(red: 0.065, green: 0.14, blue: 0.18), Color(red: 0.07, green: 0.19, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
    }
    private func ages(in row: LifetimeMonth, showNames: Bool) -> some View {
        HStack(spacing: showNames ? 10 : 5) {
            ForEach(Array(projection.plan.people.prefix(2).enumerated()), id: \.offset) { index, person in
                let age = person.age(on: row.close)
                Text(showNames ? "\(person.name) \(age)" : String(age))
                    .monospacedDigit().foregroundStyle(index == 0 ? LifeStyle.blue : Color(red: 0.98, green: 0.67, blue: 0.81))
                    .accessibilityLabel("\(person.name), \(age) anos")
            }
        }
    }

    private func axis(_ value: AxisValue) -> some View {
        let v = value.as(Double.self) ?? 0
        let label = v >= 1_000_000 ? LifeStyle.number(v/1_000_000, digits: 1) + " mi" : v >= 1000 ? LifeStyle.number(v/1000, digits: 0) + " mil" : LifeStyle.number(v, digits: 0)
        return Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.76)).frame(width: 46, alignment: .trailing)
    }
    private func ticks(_ bounds: ClosedRange<Int>) -> [Int] {
        guard bounds.lowerBound != bounds.upperBound else { return [bounds.lowerBound] }
        let step = bounds.count > 500 ? 10 : 5
        let years = projection.years.filter { $0 % step == 0 }.map { $0 * 12 }.filter { bounds.contains($0) && $0 - bounds.lowerBound >= 17 && bounds.upperBound - $0 >= 17 }
        return [bounds.lowerBound] + years + [bounds.upperBound]
    }
}
