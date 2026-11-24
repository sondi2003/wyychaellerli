import Foundation
import Testing
@testable import Wyychaellerli

/// Katalog in Zahlen: Zählung nach Land.
@Suite("Katalog-Übersicht")
struct CatalogOverviewTests {

    private let de = Locale(identifier: "de")

    private func wines(_ counts: [(String, Int)]) -> [CatalogWine] {
        counts.flatMap { country, count in
            (0..<count).map { index in
                CatalogWine(id: "\(country)-\(index)", name: "Wein \(index)", producer: "", vintage: 2020, grape: "",
                            region: "", country: country, typeRaw: "red", alcoholPercent: 0, source: "")
            }
        }
    }

    /// Die Länder aus dem Katalog vom 5.11.2026.
    private var richards: [(String, Int)] {
        [("Chile", 193), ("Italien", 110), ("Argentinien", 97), ("USA", 96), ("Neuseeland", 96),
         ("Frankreich", 8), ("Schweiz", 8), ("Deutschland", 4), ("Portugal", 3), ("Spanien", 3),
         ("Südafrika", 2), ("Nordmazedonien", 1)]
    }

    @Test("Zählt Weine und Länder, grösstes zuerst")
    func counts() {
        let overview = CatalogOverview(entries: wines(richards), locale: de)
        #expect(overview.total == 621)
        #expect(overview.countries.count == 12)
        #expect(overview.countries.first?.name == "Chile")
        #expect(overview.countries.map(\.count) == overview.countries.map(\.count).sorted(by: >))
    }

    @Test("Länderliste: nur die Weine des Landes, alle Schreibweisen, alphabetisch")
    func winesOfCountry() {
        var entries = wines([("Schweiz", 2), ("Suisse", 1), ("Chile", 4)])
        entries[0].name = "Zeta"
        entries[1].name = "alpha"
        entries[2].name = "Mitte"
        let overview = CatalogOverview(entries: entries, locale: de)
        let swiss = overview.countries.first { $0.name == "Schweiz" }
        #expect(swiss?.count == 3)
        let list = CatalogOverview.wines(inCountry: swiss?.id ?? "", from: entries)
        #expect(list.map(\.name) == ["alpha", "Mitte", "Zeta"])
        #expect(CatalogOverview.wines(inCountry: "gibtsnicht", from: entries).isEmpty)
    }

    @Test("Schweiz, Suisse und Switzerland sind ein Land")
    func mergesSpellings() {
        let overview = CatalogOverview(entries: wines([("Schweiz", 2), ("Suisse", 3), ("Switzerland", 1)]), locale: de)
        #expect(overview.countries.count == 1)
        #expect(overview.countries[0].count == 6)
    }

    @Test("Weine ohne Land zählen zur Gesamtzahl, erscheinen aber in keiner Kachel")
    func missingCountry() {
        let overview = CatalogOverview(entries: wines([("", 5), ("Italien", 3)]), locale: de)
        #expect(overview.total == 8)
        #expect(overview.countries.count == 1)
    }

    @Test("USA heissen USA, nicht „Vereinigte Staaten“")
    func usName() {
        #expect(CountryFlag.displayName(for: "United States", locale: de) == "USA")
        #expect(CountryFlag.displayName(for: "USA", locale: Locale(identifier: "en")) == "USA")
        #expect(CountryFlag.displayName(for: "USA", locale: Locale(identifier: "sr-Latn")) == "SAD")
    }

    @Test("Unter 200 Weinen bleibt die Karte weg")
    func threshold() {
        #expect(!CatalogOverview(entries: wines([("Italien", 199)]), locale: de).isWorthShowing)
        #expect(CatalogOverview(entries: wines([("Italien", 200)]), locale: de).isWorthShowing)
    }
}
