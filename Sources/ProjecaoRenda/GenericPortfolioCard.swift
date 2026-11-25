import SwiftUI

struct GenericPortfolioCard: View {
    let scenario: SimulatorScenario
    let projection: LifetimeProjection?
    let today: LocalDate
    @Binding var birth: LocalDate?
    let update: ((inout SimulatorScenario) -> Void) -> Void

    @State private var editingBirth = false
    @State private var birthDraft = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Carteira genérica", systemImage: "chart.pie")
                .font(.title2.bold()).foregroundStyle(LifeStyle.teal)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Saldo inicial simulado")
                    number("Saldo inicial", value: scenario.assets.initial, format: .money) { $0.assets.initial = $1 }
                    Text("Aporte mensal nominal")
                    number("Aporte mensal", value: scenario.assets.contribution, format: .money) { $0.assets.contribution = $1 }
                }
                GridRow {
                    Text("Rentabilidade real anual")
                    number("Rentabilidade real anual", value: scenario.assets.realRate, format: .percent, range: -20...30) { $0.assets.realRate = $1 }
                    Text("Início das retiradas")
                    HStack(spacing: 5) {
                        Stepper(String(startYear), value: startYearBinding, in: (today.year + 1)...2150)
                            .fixedSize()
                        if scenario.portfolioYear != nil {
                            Button {
                                update { $0.portfolioYear = nil }
                            } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.borderless)
                                .help("Voltar ao ano automático")
                                .accessibilityLabel("Voltar ao ano automático")
                        }
                    }
                }
                GridRow {
                    Text("Horizonte")
                    Button {
                        birthDraft = birth.map(LifetimeClock.date) ?? LifetimeClock.date(LifetimeClock.local(today.year - 40, 1, 1))
                        editingBirth = true
                    } label: {
                        Text(birth == nil ? "Informar nascimento" : "Até os 100 anos")
                    }
                    .popover(isPresented: $editingBirth) { birthEditor }
                    Text(horizonSummary).font(.caption).foregroundStyle(.secondary)
                        .gridCellColumns(2)
                }
            }
            .monospacedDigit()

            Divider()
            Toggle("Renda líquida constante", isOn: Binding(
                get: { scenario.levelsIncome },
                set: { enabled in update { $0.levelsIncome = enabled } }
            ))
            .toggleStyle(.checkbox)
            if scenario.levelsIncome {
                Text(levelsMessage).font(.caption).foregroundStyle(.secondary)
            }

            if let projection, let income = scenario.initialPortfolioIncome(in: projection, today: today) {
                LabeledContent(incomeLabel, value: LifeStyle.money(income, cents: true))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("portfolio-initial-income")
            }
            Text("Aporte mensal fixo em reais. IR da carteira estimado em 15% sobre os ganhos.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var startYear: Int {
        scenario.portfolioYear ?? scenario.simulated.map(\.year).min() ?? max(today.year + 1, 2050)
    }

    private var startYearBinding: Binding<Int> {
        Binding(get: { max(today.year + 1, startYear) }, set: { year in update { $0.portfolioYear = year } })
    }

    private var horizonSummary: String {
        if let projection {
            return "Projeção até \(LifeStyle.month(projection.end))."
        }
        return "Até o fim dos pagamentos, com pelo menos 20 anos de retiradas da carteira."
    }

    private var birthEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Data de nascimento", selection: $birthDraft,
                       in: LifetimeClock.date(LifetimeClock.local(today.year - 120, 1, 1))...LifetimeClock.date(today),
                       displayedComponents: .date)
            HStack {
                if birth != nil {
                    Button("Remover data") {
                        birth = nil
                        editingBirth = false
                    }
                }
                Spacer()
                Button("Aplicar") {
                    birth = LifetimeClock.localDate(birthDraft)
                    editingBirth = false
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(16)
    }

    private var levelsMessage: String {
        guard let projection, scenario.hasPortfolio else {
            return "Simule um saldo ou aportes na carteira para calcular o complemento mensal ao RendA+."
        }
        if projection.levelNetIncomeAvailable {
            let start = max(projection.conversion, LifetimeClock.month(today) + 1)
            return "A partir de \(LifeStyle.month(start)), a carteira complementa o RendA+ para manter a renda líquida em dinheiro de hoje."
        }
        return "As premissas atuais não permitem renda líquida constante. A projeção exibe as retiradas padrão."
    }

    private var incomeLabel: String {
        if scenario.levelsIncome {
            return scenario.afterTax ? "Renda inicial total após IR" : "Retirada inicial total bruta"
        }
        return scenario.afterTax ? "Renda mensal inicial após IR" : "Retirada mensal bruta inicial"
    }

    private func number(_ title: String, value: Double, format: LifetimeEditableNumber.Format,
                        range: ClosedRange<Double> = 0...1_000_000_000,
                        set: @escaping (inout SimulatorScenario, Double) -> Void) -> some View {
        HStack(spacing: 5) {
            LifetimeEditableNumber(title: title, value: value, format: format, range: range) { value in
                update { set(&$0, value) }
            }
            Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}
