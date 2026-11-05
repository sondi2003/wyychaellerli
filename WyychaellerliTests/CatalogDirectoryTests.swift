import Foundation
import Testing
@testable import Wyychaellerli

/// Suche beim Tippen: Teilwörter, Tippfehler, Jahrgänge – alles auf dem Gerät.
struct CatalogDirectoryTests {

    private func wine(_ name: String, _ producer: String = "", _ vintage: Int = 2020, id: String? = nil) -> CatalogWine {
        CatalogWine(
            id: id ?? "wine_\(name)_\(producer)_\(vintage)", name: name, producer: producer, vintage: vintage,
            grape: "", region: "", country: "", typeRaw: "red", alcoholPercent: 0, source: "vivino"
        )
    }

    private var directory: CatalogDirectory {
        CatalogDirectory(entries: [
            wine("Con Brio", "Cantina Zeni", 2018), wine("Con Brio", "Cantina Zeni", 2019), wine("Con Brio", "Cantina Zeni", 2020),
            wine("Cicero", "Weingut Studach", 2021), wine("Barolo", "Giacomo Conterno", 2016),
            wine("Barolo Riserva", "Giacomo Conterno", 2015), wine("Trio", "Kellerei Test", 2020),
            wine("Weißburgunder", "Weingut Müller", 2022), wine("La Pinède", "Domaine Test", 2021)
        ])
    }

    private func names(_ query: String, vintage: Int = 0) -> [String] {
        directory.suggestions(for: query, vintage: vintage).map(\.name)
    }

    @Test("Ein Teilwort mitten im Namen trifft: „Brio“ findet „Con Brio“")
    func partialWord() {
        #expect(names("Brio") == ["Con Brio"])
        #expect(names("Con Brio") == ["Con Brio"])
        #expect(names("bri") == ["Con Brio"])
    }

    @Test("Mehrere Jahrgänge sind ein Vorschlag, neuester zuerst")
    func vintagesGrouped() throws {
        let hit = try #require(directory.suggestions(for: "Con Brio").first)
        #expect(hit.entries.map(\.vintage) == [2020, 2019, 2018])
    }

    @Test("Ein eingegebener Jahrgang steht in der Gruppe vorn")
    func typedVintageFirst() throws {
        let hit = try #require(directory.suggestions(for: "Con Brio", vintage: 2019).first)
        #expect(hit.entries.first?.vintage == 2019)
    }

    @Test("Tippfehler werden gefunden, aber erst ab vier Buchstaben")
    func typos() {
        #expect(names("Cicreo") == ["Cicero"])
        #expect(names("Con Brioo") == ["Con Brio"])
        #expect(names("Zx").isEmpty)
    }

    @Test("Treffer ohne Tippfehler verdrängen die unscharfen")
    func exactBeatsFuzzy() {
        // „Brio“ steht auch nahe bei „Trio“, aber „Con Brio“ trifft genau.
        #expect(names("Brio") == ["Con Brio"])
    }

    @Test("Akzente, Gross-/Kleinschreibung und ß stören nicht")
    func folding() {
        #expect(names("pinede") == ["La Pinède"])
        #expect(names("WEISSBURGUNDER") == ["Weißburgunder"])
        #expect(names("weißburg") == ["Weißburgunder"])
    }

    @Test("Der Produzent zählt mit")
    func producerCounts() {
        #expect(names("conterno").contains("Barolo"))
        #expect(names("zeni brio") == ["Con Brio"])
    }

    @Test("Jedes Wort muss treffen")
    func allWordsRequired() {
        #expect(names("Brio Cicero").isEmpty)
    }

    @Test("Zu kurz oder leer: nichts")
    func tooShort() {
        #expect(names("").isEmpty)
        #expect(names("c").isEmpty)
        #expect(names("   ").isEmpty)
    }

    @Test("Der Anfang des Namens geht vor einem Treffer mitten drin")
    func prefixRanksFirst() {
        #expect(names("Barolo").first == "Barolo")
    }

    @Test("Nicht mehr als fünf Vorschläge")
    func limit() {
        let many = (0..<20).map { wine("Rosso \($0)", "Kellerei \($0)") }
        #expect(CatalogDirectory(entries: many).suggestions(for: "Rosso").count == 5)
    }

    @Test("Editierabstand kennt Vertauschungen")
    func distance() {
        #expect(CatalogDirectory.distance("cicreo", "cicero") == 1)
        #expect(CatalogDirectory.distance("brio", "brio") == 0)
        #expect(CatalogDirectory.distance("brio", "trio") == 1)
    }

    @Test("Die Liste auf dem Gerät speichert Text und liest ihn unverändert zurück")
    func storage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dir-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [wine("Con Brio", "Cantina Zeni", 2019)]
        CatalogDirectoryStorage.save(entries, to: url)
        #expect(CatalogDirectoryStorage.load(from: url) == entries)
        // Eine kaputte Datei gilt als leer und löst ein Neuladen aus.
        try Data("kaputt".utf8).write(to: url)
        #expect(CatalogDirectoryStorage.load(from: url).isEmpty)
    }

    @MainActor
    @Test("Ein Vorschlag wählen übernimmt Name, Jahrgang und Lücken – Eigenes bleibt")
    func selectingSuggestion() {
        let model = WineFormViewModel(mode: .add)
        model.name = "Brio"
        model.producer = "Mein Weingut"
        let chosen = CatalogWine(
            id: "wine_x", name: "Con Brio", producer: "Cantina Zeni", vintage: 2019, grape: "Merlot",
            region: "Tessin", country: "Schweiz", typeRaw: "red", alcoholPercent: 13, source: "vivino"
        )
        model.selectSuggestion(chosen)
        #expect(model.name == "Con Brio")
        #expect(model.vintage == 2019)
        #expect(model.producer == "Mein Weingut")
        #expect(model.grape == "Merlot")
        #expect(model.catalogMatch?.id == "wine_x")
        #expect(model.suggestions.isEmpty)
    }

    @MainActor
    @Test("Name nach der Wahl geändert: Die Wahl gilt nicht mehr, ergänzte Felder bleiben")
    func editingNameReleasesChoice() {
        let model = WineFormViewModel(mode: .add)
        let chosen = CatalogWine(
            id: "wine_x", name: "Con Brio", producer: "Cantina Zeni", vintage: 2019, grape: "Merlot",
            region: "", country: "", typeRaw: "red", alcoholPercent: 0, source: "vivino"
        )
        model.selectSuggestion(chosen)
        model.releaseSuggestionIfNameChanged()
        #expect(model.catalogMatch != nil)
        model.name = "Con Brioso"
        model.releaseSuggestionIfNameChanged()
        #expect(model.catalogMatch == nil)
        #expect(model.grape == "Merlot")
    }

    @MainActor
    @Test("Vorschläge gezeigt, aber nicht gewählt: beim Sichern geht nichts an den Katalog")
    func unansweredSuggestionsAreIgnored() throws {
        let model = WineFormViewModel(mode: .add)
        model.updateSuggestions(directory.suggestions(for: "Brio"))
        guard case .ignored = model.catalogChoice else {
            Issue.record("erwartet: ignored")
            return
        }
        model.updateSuggestions([])
        guard case .none = model.catalogChoice else {
            Issue.record("erwartet: none")
            return
        }
    }
}
