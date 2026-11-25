import SwiftUI

struct SimulatorView: View {
    private struct LotSheet: Identifiable {
        var id = UUID()
        let scenario: UUID
        let lot: SimulatorLot?
    }

    private enum ScenarioAction {
        case create, duplicate, rename

        var title: String {
            switch self {
            case .create: "Novo cenário"
            case .duplicate: "Duplicar cenário"
            case .rename: "Renomear cenário"
            }
        }
    }

    @AppStorage("projection.document.v1") private var storedDocument: Data?
    @AppStorage("projection.selectedScenario") private var selection = ""
    @AppStorage("projection.quotes.v1") private var storedQuotes: Data?
    @State private var document = SimulatorDocument.example(on: LifetimeClock.today)
    @State private var quotes: [Int: LifetimeRendaQuote] = [:]
    @State private var today = LifetimeClock.today
    @State private var lotSheet: LotSheet?
    @State private var pendingRemoval: SimulatorLot?
    @State private var editingName = false
    @State private var confirmingScenarioDeletion = false
    @State private var scenarioAction = ScenarioAction.create
    @State private var scenarioName = ""
    @State private var quoteStatus: String?
    @State private var refreshing = false
    @State private var readFailed = false

    private var scenario: SimulatorScenario {
        document.scenarios.first { $0.id.uuidString == selection } ?? document.scenarios[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let projection = document.projection(for: scenario, today: today)
                    if let projection {
                        metrics(projection)
                        LifetimeChartPanel(projection: projection, nominal: scenario.nominal, afterTax: setting(\.afterTax))
                            .id(scenario.id)
                        lotList
                        portfolioCard(projection)
                        LifetimeSchedule(projection: projection, nominal: scenario.nominal, afterTax: scenario.afterTax)
                            .id(scenario.id)
                    } else {
                        ContentUnavailableView {
                            Label("R$ 0 investido", systemImage: "chart.line.uptrend.xyaxis")
                        } description: {
                            Text("Adicione um aporte simulado para ver quando começa a renda e quanto os títulos podem pagar por mês.")
                        } actions: {
                            addLotButton.buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 230)
                        portfolioCard(nil)
                    }
                    HStack {
                        Text("Estimativas com o IPCA informado e IR sobre os rendimentos. Custódia e taxas da corretora ficam fora do cálculo.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Link("Metodologia do Tesouro Direto", destination: URL(string: "https://www.tesourodireto.com.br/documents/d/guest/tesouro_renda_mais")!)
                            .font(.caption)
                    }
                }
                .padding(24)
            }
        }
        .task { restore() }
        .onChange(of: document) { _, updated in
            guard !readFailed else { return }
            storedDocument = try? JSONEncoder().encode(updated)
        }
        .sheet(item: $lotSheet) { sheet in
            LotEditor(quotes: availableQuotes, lot: sheet.lot) { updated in
                guard let index = document.scenarios.firstIndex(where: { $0.id == sheet.scenario }) else { return }
                if let existing = document.scenarios[index].simulated.firstIndex(where: { $0.id == updated.id }) {
                    document.scenarios[index].simulated[existing] = updated
                } else {
                    document.scenarios[index].simulated.append(updated)
                }
            }
        }
        .alert(scenarioAction.title, isPresented: $editingName) {
            TextField("Nome do cenário", text: $scenarioName)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") { saveScenarioName() }
                .disabled(scenarioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Excluir \(scenario.name)?", isPresented: $confirmingScenarioDeletion) {
            Button("Cancelar", role: .cancel) {}
            Button("Excluir cenário", role: .destructive) {
                let id = scenario.id
                guard document.scenarios.count > 1 else { return }
                document.scenarios.removeAll { $0.id == id }
                selection = document.scenarios[0].id.uuidString
            }
        } message: {
            Text("Os aportes simulados deste cenário serão apagados.")
        }
        .alert("Remover aporte?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { lot in
            Button("Cancelar", role: .cancel) {}
            Button("Remover", role: .destructive) {
                change { $0.simulated.removeAll { $0.id == lot.id } }
            }
        } message: { lot in
            Text("RendA+ \(String(lot.year)) · \(LifeStyle.money(lot.amount, cents: true))")
        }
        .disabled(readFailed)
        .overlay(alignment: .bottom) {
            if readFailed {
                Text("Não foi possível abrir as simulações salvas. Os dados locais foram preservados.")
                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Tesouro RendA+", systemImage: "building.columns")
                        .font(.callout.weight(.semibold)).foregroundStyle(LifeStyle.teal)
                    Text("Projeção Vitalícia")
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Button {
                        Task { await refreshQuotes() }
                    } label: {
                        Label(refreshing ? "Buscando cotações…" : "Atualizar cotações", systemImage: "arrow.clockwise")
                    }
                    .disabled(refreshing)
                    .help("Busca preços e taxas do Tesouro Transparente. Os aportes salvos mantêm suas premissas.")
                    if let quoteStatus {
                        Text(quoteStatus).font(.caption).foregroundStyle(.secondary)
                    } else if let date = availableQuotes.values.map(\.date).max() {
                        Text("Última cotação: \(LifeStyle.date(date))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 14) {
                Picker("Cenário", selection: Binding(
                    get: { scenario.id.uuidString },
                    set: { selection = $0 }
                )) {
                    ForEach(document.scenarios) { item in
                        Text(item.name).tag(item.id.uuidString)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
                .accessibilityLabel("Cenário")

                Menu {
                    Button("Novo cenário") { editName(.create) }
                    Button("Duplicar cenário") { editName(.duplicate) }
                    Button("Renomear cenário") { editName(.rename) }
                    Divider()
                    Button("Excluir cenário", role: .destructive) { confirmingScenarioDeletion = true }
                        .disabled(document.scenarios.count == 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .fixedSize()
                .accessibilityLabel("Gerenciar cenários")

                Divider().frame(height: 18)

                HStack(spacing: 6) {
                    Text("IPCA anual").foregroundStyle(.secondary)
                    LifetimeEditableNumber(title: "IPCA anual", value: scenario.annualInflation, format: .percent, range: -10...30) { value in
                        change { $0.annualInflation = value }
                    }
                    .monospacedDigit()
                    Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                }

                Spacer()
                Picker("Valores", selection: setting(\.nominal)) {
                    Text("Dinheiro de hoje").tag(false)
                    Text("Dinheiro de amanhã").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.background)
    }

    private var availableQuotes: [Int: LifetimeRendaQuote] {
        quotes.filter { $0.key > today.year }
    }

    private var addLotButton: some View {
        Button {
            lotSheet = LotSheet(scenario: scenario.id, lot: nil)
        } label: {
            Label("Simular aporte", systemImage: "plus")
        }
    }

    private func portfolioCard(_ projection: LifetimeProjection?) -> some View {
        GenericPortfolioCard(scenario: scenario, projection: projection, today: today,
                             birth: $document.birth, update: change)
            .id(scenario.id)
    }

    private var lotList: some View {
        let lots = scenario.simulated.sorted { ($0.date, $0.year) < ($1.date, $1.year) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Aportes simulados").font(.title2.bold())
                Spacer()
                addLotButton.buttonStyle(.borderedProminent)
            }
            VStack(spacing: 0) {
                ForEach(lots) { lot in
                    HStack(spacing: 14) {
                        Image(systemName: "building.columns").foregroundStyle(LifeStyle.teal).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RendA+ \(String(lot.year))").font(.headline)
                            Text("\(LifeStyle.date(lot.date)) · IPCA + \(LifeStyle.number(lot.rate))% a.a.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(LifeStyle.number(lot.quantity, digits: 4)) títulos")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        Text(LifeStyle.money(lot.amount, cents: true)).font(.callout.bold()).monospacedDigit()
                            .frame(minWidth: 100, alignment: .trailing)
                        Button {
                            lotSheet = LotSheet(scenario: scenario.id, lot: lot)
                        } label: { Image(systemName: "pencil") }.accessibilityLabel("Editar aporte")
                        Button {
                            pendingRemoval = lot
                        } label: { Image(systemName: "trash") }.accessibilityLabel("Remover aporte")
                    }
                    .padding(12)
                    if lot.id != lots.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func metrics(_ projection: LifetimeProjection) -> some View {
        let firstMonth = scenario.levelsIncome && projection.levelNetIncomeAvailable
            ? max(projection.conversion, LifetimeClock.month(today) + 1)
            : projection.firstDistribution
        let first = projection.months.first { $0.id == firstMonth }
        let last = projection.distributionEnd
        let nominal = scenario.nominal
        let invested = projection.invested(initialPortfolioBalance: scenario.assets.initial, nominal: nominal)
        return LifetimeMetricCards(count: 4) {
            LifetimeMetricCard(title: "Valor investido", value: LifeStyle.money(invested, cents: true),
                               detail: nominal ? "Total em dinheiro de amanhã" : "Total em dinheiro de hoje",
                               icon: "banknote", tint: .purple)
            LifetimeMetricCard(title: "Títulos RendA+", value: LifeStyle.number(projection.plan.quantity, digits: 4),
                               detail: "Quantidade simulada", icon: "building.columns", tint: LifeStyle.teal)
            LifetimeMetricCard(title: projection.levelNetIncomeAvailable && scenario.afterTax && !nominal
                               ? "Renda líquida constante"
                               : scenario.afterTax ? "Renda inicial após IR" : "Renda inicial bruta",
                               value: LifeStyle.money(first.map { projection.income($0, nominal: nominal, afterTax: scenario.afterTax) } ?? 0, cents: true),
                               detail: LifeStyle.month(firstMonth), icon: "arrow.down.left.circle", tint: .orange)
            LifetimeMetricCard(title: "Último pagamento", value: LifeStyle.month(last),
                               detail: "Fim da distribuição", icon: "calendar", tint: .blue)
        }
    }

    private func restore() {
        if let storedDocument {
            guard let restored = try? JSONDecoder().decode(SimulatorDocument.self, from: storedDocument),
                  !restored.scenarios.isEmpty else {
                readFailed = true
                return
            }
            document = restored
        } else {
            storedDocument = try? JSONEncoder().encode(document)
        }
        if let storedQuotes, let restored = try? JSONDecoder().decode([Int: LifetimeRendaQuote].self, from: storedQuotes) {
            quotes = restored
        }
    }

    private func refreshQuotes() async {
        refreshing = true
        quoteStatus = nil
        defer { refreshing = false }
        do {
            let updated = try await LifetimeRendaQuotes.fetch()
            storedQuotes = try JSONEncoder().encode(updated)
            quotes = updated
        } catch {
            quoteStatus = "Cotações indisponíveis. Você pode informar os valores."
        }
    }

    private func change(_ update: (inout SimulatorScenario) -> Void) {
        let id = scenario.id
        guard let index = document.scenarios.firstIndex(where: { $0.id == id }) else { return }
        update(&document.scenarios[index])
    }

    private func setting<Value>(_ key: WritableKeyPath<SimulatorScenario, Value>) -> Binding<Value> {
        Binding(get: { scenario[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
    }

    private func editName(_ action: ScenarioAction) {
        scenarioAction = action
        switch action {
        case .create: scenarioName = ""
        case .duplicate: scenarioName = "\(scenario.name) (cópia)"
        case .rename: scenarioName = scenario.name
        }
        editingName = true
    }

    private func saveScenarioName() {
        let name = scenarioName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch scenarioAction {
        case .rename:
            change { $0.name = name }
        case .create, .duplicate:
            var item = scenarioAction == .duplicate ? scenario : SimulatorScenario(name: name)
            item.name = name
            item.id = UUID()
            document.scenarios.append(item)
            selection = item.id.uuidString
        }
    }
}
