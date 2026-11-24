import Foundation
import Testing
@testable import Wyychaellerli

/// Die Kellerstatistik zählt **Flaschen im Bestand** – nicht Weine, nicht das Archiv.
@MainActor
struct CellarStatisticsTests {

    private let german = Locale(identifier: "de_CH")

    @Test("Flaschen und Weine: Archiv und leerer Bestand zählen nicht")
    func countsOnlyStock() {
        let context = TestStack.makeContext()
        let wines = [
            TestStack.makeWine(in: context, name: "A", quantity: 3),
            TestStack.makeWine(in: context, name: "B", quantity: 2),
            TestStack.makeWine(in: context, name: "Leer", quantity: 0),
            TestStack.makeWine(in: context, name: "Archiv", quantity: 6, isArchived: true)
        ]
        let statistics = CellarStatistics(wines: wines, locale: german)
        #expect(statistics.bottles == 5)
        #expect(statistics.wineCount == 2)
        #expect(!statistics.isEmpty)
    }

    @Test("Leerer Keller ist leer")
    func emptyCellar() {
        let statistics = CellarStatistics(wines: [], locale: german)
        #expect(statistics.isEmpty)
        #expect(statistics.averageRating == nil)
        #expect(!statistics.hasMaturity)
    }

    @Test("Weinarten in fester Reihenfolge, Arten ohne Flasche fehlen")
    func typeShares() {
        let context = TestStack.makeContext()
        let wines = [
            TestStack.makeWine(in: context, name: "W", type: .white, quantity: 4),
            TestStack.makeWine(in: context, name: "R1", type: .red, quantity: 1),
            TestStack.makeWine(in: context, name: "R2", type: .red, quantity: 2)
        ]
        let types = CellarStatistics(wines: wines, locale: german).types
        #expect(types.map(\.type) == [.red, .white])
        #expect(types.map(\.bottles) == [3, 4])
    }

    @Test("Schweiz, Suisse und Switzerland sind ein Land; meiste Flaschen zuerst")
    func countriesMergeAndSort() {
        let context = TestStack.makeContext()
        let wines = [
            TestStack.makeWine(in: context, name: "A", country: "Schweiz", quantity: 1),
            TestStack.makeWine(in: context, name: "B", country: "Suisse", quantity: 2),
            TestStack.makeWine(in: context, name: "C", country: "Italien", quantity: 2),
            TestStack.makeWine(in: context, name: "D", country: "", quantity: 9)
        ]
        let countries = CellarStatistics(wines: wines, locale: german).countries
        #expect(countries.count == 2)
        #expect(countries.first?.bottles == 3)
        #expect(countries.last?.bottles == 2)
    }

    @Test("Jahrgänge aufsteigend, ohne Jahrgang wird nichts erfunden")
    func vintages() {
        let context = TestStack.makeContext()
        let wines = [
            TestStack.makeWine(in: context, name: "A", vintage: 2021, quantity: 2),
            TestStack.makeWine(in: context, name: "B", vintage: 2018, quantity: 1),
            TestStack.makeWine(in: context, name: "C", vintage: 2021, quantity: 1),
            TestStack.makeWine(in: context, name: "D", vintage: 0, quantity: 5)
        ]
        let vintages = CellarStatistics(wines: wines, locale: german).vintages
        #expect(vintages.map(\.year) == [2018, 2021])
        #expect(vintages.map(\.bottles) == [1, 3])
    }

    @Test("Trinkreife in Flaschen: bald, trinkreif, lagern, ohne Angabe")
    func maturity() {
        let context = TestStack.makeContext()
        let year = Calendar.current.component(.year, from: .now)
        let wines = [
            TestStack.makeWine(in: context, name: "Bald", quantity: 2, drinkFrom: year - 3, drinkTo: year),
            TestStack.makeWine(in: context, name: "Vorbei", quantity: 1, drinkFrom: year - 5, drinkTo: year - 1),
            TestStack.makeWine(in: context, name: "Reif", quantity: 4, drinkFrom: year - 1, drinkTo: year + 3),
            TestStack.makeWine(in: context, name: "Jung", quantity: 3, drinkFrom: year + 2, drinkTo: year + 8),
            TestStack.makeWine(in: context, name: "Ohne", quantity: 5)
        ]
        let statistics = CellarStatistics(wines: wines, locale: german)
        #expect(statistics.drinkSoon == 3)
        #expect(statistics.ready == 4)
        #expect(statistics.tooYoung == 3)
        #expect(statistics.withoutWindow == 5)
        #expect(statistics.hasMaturity)
    }
}
