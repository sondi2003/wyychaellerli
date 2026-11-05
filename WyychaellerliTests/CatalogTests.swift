import Testing
@testable import Wyychaellerli

/// Der gemeinsame Katalog: Schlüssel, Suchwörter und Abgleich – alles ohne Netz.
///
/// Der Schlüssel verhindert Doppeleinträge im Katalog, die Suchwörter finden Kandidaten,
/// und den Treffer entscheidet dieselbe Regel wie bei doppelten Flaschen im Keller.
struct CatalogTests {

    private func entry(_ name: String, _ producer: String = "", _ vintage: Int = 2021) -> CatalogWine {
        CatalogWine(
            id: CatalogKey.make(producer: producer, name: name, vintage: vintage),
            name: name, producer: producer, vintage: vintage,
            grape: "", region: "", country: "", typeRaw: "red", alcoholPercent: 0, source: "nutzer"
        )
    }

    // MARK: Schlüssel

    @Test("Schreibweise ändert den Schlüssel nicht")
    func keyIgnoresSpelling() {
        let a = CatalogKey.make(producer: "Château Ollieux Romanis", name: "Cuvée Prestige", vintage: 2022)
        let b = CatalogKey.make(producer: "chateau ollieux-romanis", name: "CUVEE PRESTIGE", vintage: 2022)
        #expect(a == b)
        #expect(a.hasPrefix("wine_"))
    }

    @Test("Ein anderer Jahrgang ist ein anderer Eintrag")
    func keyDependsOnVintage() {
        let a = CatalogKey.make(producer: "Cicero", name: "Pinot Noir", vintage: 2023)
        let b = CatalogKey.make(producer: "Cicero", name: "Pinot Noir", vintage: 2022)
        #expect(a != b)
    }

    @Test("Mit Strichcode gilt der Strichcode")
    func keyPrefersGTIN() {
        let key = CatalogKey.make(gtin: "7 610000 123456", producer: "Egal", name: "Egal", vintage: 0)
        #expect(key == "ean_7610000123456")
    }

    @Test("Zu kurzer Strichcode zählt nicht")
    func keyIgnoresShortGTIN() {
        #expect(CatalogKey.make(gtin: "123", producer: "A", name: "B", vintage: 0).hasPrefix("wine_"))
    }

    // MARK: Suchwörter

    @Test("Füllwörter, Zahlen und Doppel fallen weg")
    func tokens() {
        let tokens = CatalogKey.tokens(name: "Primitivo di Manduria 2022", producer: "Cantine San Marzano Primitivo")
        #expect(tokens == ["san", "marzano", "primitivo", "manduria"])
    }

    @Test("Akzente werden entfernt")
    func tokensFoldAccents() {
        #expect(CatalogKey.tokens(name: "L'Épicurieux", producer: "") == ["epicurieux"])
    }

    @Test("Gesucht wird mit dem längsten Wort des Produzenten")
    func searchTokenPrefersProducer() {
        // „Château“ ist ein Füllwort; bei gleich langen Wörtern gilt das erste.
        #expect(CatalogKey.searchToken(name: "Cuvée Prestige", producer: "Château Ollieux Romanis") == "ollieux")
        #expect(CatalogKey.searchToken(name: "Malbec", producer: "Juan Benegas") == "benegas")
    }

    @Test("Ohne Produzent wird mit dem Namen gesucht")
    func searchTokenFallsBackToName() {
        #expect(CatalogKey.searchToken(name: "Sasso al Vento", producer: "") == "sasso")
    }

    // MARK: Abgleich

    @Test("Erkennungsfehler im Namen trifft trotzdem")
    func matchesDespiteTypo() {
        let catalog = [entry("La Pinède", "Domaine La Tour Vieille")]
        let candidate = DuplicateFinder.Candidate(name: "La Pinede", producer: "Domaine La Tour Vieille", vintage: 2021)
        #expect(CatalogMatcher.bestMatch(for: candidate, in: catalog)?.name == "La Pinède")
    }

    @Test("Riserva ist ein anderer Wein")
    func riservaDoesNotMatch() {
        let catalog = [entry("Chianti Classico Riserva")]
        let candidate = DuplicateFinder.Candidate(name: "Chianti Classico", producer: "", vintage: 2021)
        #expect(CatalogMatcher.bestMatch(for: candidate, in: catalog) == nil)
    }

    @Test("Anderer Jahrgang trifft nicht")
    func otherVintageDoesNotMatch() {
        let catalog = [entry("Barolo", "", 2018)]
        let candidate = DuplicateFinder.Candidate(name: "Barolo", producer: "", vintage: 2019)
        #expect(CatalogMatcher.bestMatch(for: candidate, in: catalog) == nil)
    }

    @Test("Der ähnlichste Eintrag gewinnt")
    func bestOfSeveral() {
        let catalog = [entry("Primitivo"), entry("Primitivo di Manduria")]
        let candidate = DuplicateFinder.Candidate(name: "Primitivo di Manduria", producer: "", vintage: 2021)
        #expect(CatalogMatcher.bestMatch(for: candidate, in: catalog)?.name == "Primitivo di Manduria")
    }

    // MARK: Vorschlag

    @Test("Vorschläge desselben Weins fallen zusammen")
    func submissionsGroupByKey() {
        func submission(_ id: String, _ name: String) -> CatalogSubmission {
            CatalogSubmission(
                id: id, name: name, producer: "Cicero", vintage: 2023, grape: "", region: "", country: "",
                typeRaw: "red", alcoholPercent: 0,
                catalogKey: CatalogKey.make(producer: "Cicero", name: name, vintage: 2023),
                wineUUID: "", status: .pending, createdAt: nil
            )
        }
        let groups = SubmissionGroup.grouping([
            submission("1", "Pinot Noir"), submission("2", "PINOT NOIR"), submission("3", "Chardonnay")
        ])
        #expect(groups.count == 2)
        #expect(groups.contains { $0.items.count == 2 })
    }

    // MARK: Suche und Filter im Admin-Bereich

    private func full(_ name: String, _ producer: String, _ vintage: Int, type: String = "red",
                      country: String = "Schweiz", source: String = "nutzer", grape: String = "Pinot Noir") -> CatalogWine {
        CatalogWine(id: name, name: name, producer: producer, vintage: vintage, grape: grape,
                    region: "Bündnerland", country: country, typeRaw: type, alcoholPercent: 13, source: source)
    }

    @Test("Teilwörter und fehlende Akzente finden den Wein")
    func searchFindsPartsAndAccents() {
        let entries = [full("Cicero", "Rutishauser", 2023), full("La Pinède", "Tour Vieille", 2021)]
        #expect(CatalogFilter(text: "cice").apply(to: entries).map(\.name) == ["Cicero"])
        #expect(CatalogFilter(text: "pinede").apply(to: entries).map(\.name) == ["La Pinède"])
    }

    @Test("Mehrere Wörter grenzen gemeinsam ein")
    func searchCombinesWords() {
        let entries = [full("Cicero", "Rutishauser", 2023), full("Cicero", "Rutishauser", 2022)]
        #expect(CatalogFilter(text: "cicero 2022").apply(to: entries).map(\.vintage) == [2022])
    }

    @Test("Weinart, Land und Herkunft filtern")
    func filters() {
        let entries = [
            full("A", "X", 2020, type: "red", country: "Schweiz", source: "nutzer"),
            full("B", "X", 2020, type: "white", country: "Italien", source: "admin"),
            full("C", "X", 2020, type: "white", country: "Schweiz", source: "nutzer")
        ]
        #expect(CatalogFilter(type: .white).apply(to: entries).map(\.name) == ["B", "C"])
        #expect(CatalogFilter(country: "Schweiz").apply(to: entries).map(\.name) == ["A", "C"])
        #expect(CatalogFilter(source: "admin").apply(to: entries).map(\.name) == ["B"])
        #expect(CatalogFilter(type: .white, country: "Schweiz").apply(to: entries).map(\.name) == ["C"])
    }

    @Test("Lückenhafte Einträge lassen sich herausfiltern")
    func incomplete() {
        let entries = [full("Komplett", "X", 2020), full("Ohne Jahrgang", "X", 0), full("Ohne Rebsorte", "X", 2020, grape: "")]
        #expect(CatalogFilter(onlyIncomplete: true).apply(to: entries).map(\.name) == ["Ohne Jahrgang", "Ohne Rebsorte"])
    }

    @Test("Länderliste ohne Leere und Doppel, alphabetisch")
    func countryList() {
        let entries = [full("A", "", 0, country: "Schweiz"), full("B", "", 0, country: "Italien"),
                       full("C", "", 0, country: ""), full("D", "", 0, country: "Schweiz")]
        #expect(CatalogFilter.countries(in: entries) == ["Italien", "Schweiz"])
        let counts = CatalogFilter.countryCounts(in: entries)
        #expect(counts.map(\.country) == ["Italien", "Schweiz"])
        #expect(counts.map(\.count).reduce(0, +) == entries.filter { !$0.country.isEmpty }.count)
    }
}
