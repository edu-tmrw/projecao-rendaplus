import XCTest
@testable import ProjecaoRenda

final class SimulatorTests: XCTestCase {
    private let today = LifetimeClock.local(2026, 11, 25)

    func testEmptyDocumentAndIndependentScenariosRoundTrip() throws {
        var document = SimulatorDocument()
        XCTAssertTrue(document.scenarios[0].simulated.isEmpty)
        XCTAssertNil(document.projection(for: document.scenarios[0], today: today))

        let purchase = lot(year: 2040, amount: 10_000)
        let simulation = lot(year: 2050, amount: 20_000)
        document.scenarios[0].simulated = [purchase, simulation]
        document.scenarios.append(.init(name: "Cenário vazio"))
        document.scenarios.append(.init(name: "Outro cenário", simulated: [purchase]))
        let reopened = try JSONDecoder().decode(SimulatorDocument.self, from: JSONEncoder().encode(document))
        let first = try XCTUnwrap(reopened.projection(for: reopened.scenarios[0], today: today))
        XCTAssertNil(reopened.projection(for: reopened.scenarios[1], today: today))
        let second = try XCTUnwrap(reopened.projection(for: reopened.scenarios[2], today: today))

        XCTAssertEqual(first.plan.purchases.count, 2)
        XCTAssertEqual(first.distributionEnd, 2070 * 12 - 1)
        XCTAssertEqual(second.plan.purchases.count, 1)
        XCTAssertEqual(second.months.filter { $0.withdrawal > 0 }.count, 240)
        XCTAssertEqual(second.invested(initialPortfolioBalance: 0, nominal: true), 10_000, accuracy: 0.01)
    }

    func testPurchaseCostUsesInflationBetweenItsOwnDateAndToday() throws {
        var document = SimulatorDocument()
        document.scenarios[0].simulated = [
            .init(year: 2040, date: LifetimeClock.local(2025, 11, 25), amount: 10_000, quantity: 1, rate: 7),
            lot(year: 2040, amount: 20_000)
        ]
        let projection = try XCTUnwrap(document.projection(for: document.scenarios[0], today: today))
        XCTAssertEqual(projection.invested(initialPortfolioBalance: 0, nominal: false), 30_400, accuracy: 0.01)
    }

    func testIncomeExtendsPastAge100WhenLaterCohortsStillPay() throws {
        var document = SimulatorDocument()
        document.birth = LifetimeClock.local(1940, 1, 1)
        document.scenarios[0].simulated = [lot(year: 2060, amount: 1_000)]
        let projection = try XCTUnwrap(document.projection(for: document.scenarios[0], today: today))
        XCTAssertEqual(projection.months.filter { $0.withdrawal > 0 }.count, 240)
    }

    func testValidatesOrderAndSettlementCutoff() {
        XCTAssertNotNil(lot(year: 2040, amount: 500).settlement)
        XCTAssertNil(lot(year: 2026, amount: 500).settlement)
        XCTAssertNil(lot(year: 2040, amount: 0).settlement)
        XCTAssertNil(lot(year: 2040, amount: .infinity).settlement)
    }

    func testConstantIncomeCardUsesRendaAndPortfolioWithEveryDisplayFilter() throws {
        let document = SimulatorDocument()
        var scenario = document.scenarios[0]
        scenario.simulated = [lot(year: 2040, amount: 10_000)]
        scenario.assets.initial = 200_000
        scenario.levelsIncome = true
        let projection = try XCTUnwrap(document.projection(for: scenario, today: today))
        XCTAssertTrue(projection.levelNetIncomeAvailable)
        let row = try XCTUnwrap(projection.months.first(where: { $0.id == projection.conversion }))
        for nominal in [false, true] {
            for afterTax in [false, true] {
                scenario.nominal = nominal
                scenario.afterTax = afterTax
                let total = projection.income(row, nominal: nominal, afterTax: afterTax)
                let portfolio = projection.assetsIncome(row, nominal: nominal, afterTax: afterTax)
                XCTAssertGreaterThan(total, portfolio)
                let combinedCard = try XCTUnwrap(scenario.initialPortfolioIncome(in: projection, today: today))
                XCTAssertEqual(combinedCard, total, accuracy: 0.0001)
                scenario.levelsIncome = false
                let portfolioCard = try XCTUnwrap(scenario.initialPortfolioIncome(in: projection, today: today))
                XCTAssertEqual(portfolioCard, portfolio, accuracy: 0.0001)
                scenario.levelsIncome = true
            }
        }
    }

    func testUsesPurchaseSideOfTreasuryQuoteAndLatestDate() throws {
        let csv = """
        Tipo Titulo;Data Vencimento;Data Base;Taxa Compra Manha;Taxa Venda Manha;PU Compra Manha;PU Venda Manha;PU Base Manha
        Tesouro Renda+ Aposentadoria Extra;15/12/2064;24/11/2026;7,64;7,76;2.000,97;1974,09;1974,09
        Tesouro Renda+ Aposentadoria Extra;15/12/2064;25/11/2026;7,63;7,75;2.001,53;1975,25;1975,25
        """
        let quote = try XCTUnwrap(try LifetimeRendaQuotes.parse(Data(csv.utf8))[2045])
        XCTAssertEqual(quote.date, today)
        XCTAssertEqual(quote.price, 2_001.53)
        XCTAssertEqual(quote.rate, 7.63)
    }

    func testExampleOpensWithTwoEditableHypotheticalLots() throws {
        var example = SimulatorDocument.example(on: today)
        let scenario = example.scenarios[0]
        XCTAssertEqual(scenario.simulated.map(\.year), [2055, 2060])
        XCTAssertEqual(scenario.simulated.map(\.amount), [100_000, 100_000])
        XCTAssertEqual(scenario.simulated.map(\.rate), [7.5, 7.5])
        let original = try XCTUnwrap(example.projection(for: scenario, today: today))
        XCTAssertEqual(original.distributionEnd, 2080 * 12 - 1)
        XCTAssertEqual(original.invested(initialPortfolioBalance: 0, nominal: false), 200_000, accuracy: 0.01)
        example.scenarios[0].simulated[1].year = 2065
        example.scenarios[0].simulated[1].amount = 50_000
        example.scenarios[0].simulated[1].rate = 8
        let edited = try XCTUnwrap(example.projection(for: example.scenarios[0], today: today))
        XCTAssertEqual(edited.distributionEnd, 2085 * 12 - 1)
        XCTAssertEqual(edited.invested(initialPortfolioBalance: 0, nominal: false), 150_000, accuracy: 0.01)
    }

    private func lot(year: Int, amount: Double) -> SimulatorLot {
        .init(year: year, date: today, amount: amount, quantity: 1, rate: 7)
    }
}
