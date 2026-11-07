import Foundation
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

    @Test("Jahrgang filtern, 0 heisst ohne Jahrgang, neueste zuerst gezählt")
    func vintageFilter() {
        let entries = [full("A", "X", 2023), full("B", "X", 2021), full("C", "X", 2023), full("D", "X", 0)]
        #expect(CatalogFilter(vintage: 2023).apply(to: entries).map(\.name) == ["A", "C"])
        #expect(CatalogFilter(vintage: 0).apply(to: entries).map(\.name) == ["D"])
        #expect(CatalogFilter(vintage: 2021).isActive)
        let counts = CatalogFilter.vintageCounts(in: entries)
        #expect(counts.map(\.vintage) == [2023, 2021, 0])
        #expect(counts.map(\.count) == [2, 1, 1])
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

@Suite("Passt zu: Speisegruppen")
struct PairingCategoryTests {

    @Test("Freitext der Etiketten fällt in die richtigen Gruppen")
    func groups() {
        #expect(PairingCategory.categories(in: ["Gegrilltes Fleisch", "Lamm", "Hartkäse"]) == [.meat, .cheese])
        #expect(PairingCategory.categories(in: ["Fisch und Meeresfrüchte"]) == [.fish])
        #expect(PairingCategory.categories(in: ["Lasagne", "Gemüsegratin"]) == [.pasta, .vegetables])
        #expect(PairingCategory.categories(in: ["Apéro", "Dessert"]) == [.aperitif, .dessert])
    }

    @Test("Kurze Stichwörter nur als ganzes Wort, Fruchtiges ist kein Dessert")
    func guards() {
        #expect(PairingCategory.categories(in: ["Ente"]) == [.meat])
        #expect(PairingCategory.categories(in: ["Gegrilltes Gemüse"]) == [.vegetables])
        #expect(PairingCategory.categories(in: ["Fruchtig und frisch"]).isEmpty)
        #expect(PairingCategory.categories(in: []).isEmpty)
    }
}

@Suite("Katalog: Speisen")
struct CatalogPairingTests {

    private func entry(food: [String]) -> CatalogWine {
        CatalogWine(id: "x", name: "Barolo", producer: "Rocca", vintage: 2020, grape: "", region: "",
                    country: "", typeRaw: "red", alcoholPercent: 0, source: "vivino", foodPairings: food)
    }

    @Test("Ein Vorschlag mit Speisen ergänzt einen Eintrag ohne sie")
    func additionNamesPairings() {
        let existing = entry(food: [])
        let proposed = entry(food: ["Rindfleisch"])
        #expect(proposed.additions(over: existing) == [tr("Passt zu")])
    }

    @Test("Vorhandene Speisen werden nie überschrieben")
    func existingPairingsStay() {
        #expect(entry(food: ["Käse"]).additions(over: entry(food: ["Rindfleisch"])) == nil)
        var base = entry(food: ["Rindfleisch"])
        base.fillEmptyFields(from: entry(food: ["Käse"]))
        #expect(base.foodPairings == ["Rindfleisch"])
    }

    @Test("Katalogspeisen landen in den Gruppen des Filters")
    func categoriesFromCatalog() {
        let groups = PairingCategory.categories(in: ["Rindfleisch", "Hartkäse", "Meeresfrüchte"])
        #expect(groups == [.meat, .cheese, .fish])
    }

    @Test("Die Vivino-Begriffe des Imports treffen ihre Gruppe")
    func importTermsMatch() {
        let terms: [(String, PairingCategory)] = [
            ("Rindfleisch", .meat), ("Kalbfleisch", .meat), ("Lamm", .meat), ("Schweinefleisch", .meat),
            ("Geflügel", .meat), ("Wild", .meat), ("Aufschnitt", .meat), ("Fisch", .fish), ("Meeresfrüchte", .fish),
            ("Hartkäse", .cheese), ("Weichkäse", .cheese), ("Ziegenkäse", .cheese), ("Gemüse", .vegetables),
            ("Pilze", .vegetables), ("Pasta", .pasta), ("Pizza", .pasta), ("Reis", .pasta),
            ("Dessert", .dessert), ("Apéro", .aperitif)
        ]
        for (term, group) in terms {
            #expect(PairingCategory.categories(in: [term]).contains(group), "\(term)")
        }
    }
}

@Suite("Katalog: Vivino-Suche")
struct VivinoSearchTests {

    private func entry(producer: String, name: String, vintage: Int) -> CatalogWine {
        CatalogWine(id: "x", name: name, producer: producer, vintage: vintage, grape: "", region: "",
                    country: "", typeRaw: "red", alcoholPercent: 0, source: "nutzer")
    }

    @Test("Die Suche trägt Produzent, Name und Jahrgang, sauber kodiert")
    func queryContainsAllParts() throws {
        let url = try #require(AdminSubmissionEditor.vivinoSearchURL(
            for: entry(producer: " Château Müller ", name: "Cuvée Rouge", vintage: 2019)))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.host == "www.vivino.com")
        #expect(items?.first?.value == "Château Müller Cuvée Rouge 2019")
    }

    @Test("Ohne Jahrgang kein Jahr, ohne Angaben keine Suche")
    func omitsMissingParts() throws {
        let url = try #require(AdminSubmissionEditor.vivinoSearchURL(
            for: entry(producer: "", name: "Barolo", vintage: 0)))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Barolo")
        #expect(AdminSubmissionEditor.vivinoSearchURL(for: entry(producer: "", name: " ", vintage: 0)) == nil)
    }
}

@Suite("Katalog: Vivino-Abgleich")
struct VivinoLookupTests {

    private func entry(producer: String = "Donatsch", name: String = "Unique Pinot Noir", vintage: Int = 2021) -> CatalogWine {
        CatalogWine(id: "x", name: name, producer: producer, vintage: vintage, grape: "", region: "",
                    country: "", typeRaw: "red", alcoholPercent: 0, source: "nutzer")
    }

    private func candidate(_ vid: String, _ producer: String, _ name: String, _ vintage: Int,
                           grape: String = "", count: Int = 10) -> VivinoCandidate {
        VivinoCandidate(vid: vid, name: name, producer: producer, vintage: vintage, region: "Malanser",
                        country: "Schweiz", typeRaw: "red", grape: grape, foodPairings: [], rating: 4.2, ratingsCount: count)
    }

    @Test("Suchformen: Name als Wortgruppe, Produzent plus Name, dann Einzelwörter")
    func searchTerms() {
        #expect(VivinoRanker.searchTerms(for: entry()) == ["Unique Pinot Noir", "Donatsch Unique Pinot Noir", "donatsch", "unique"])
        #expect(VivinoRanker.searchTerms(for: entry(producer: "", name: "Barolo")) == ["barolo"])
        // Der Fall, der bei der Einzelwort-Suche durchfiel: 101 Weine von Antinori, der gesuchte weit hinten.
        let terms = VivinoRanker.searchTerms(for: entry(producer: "Marchesi Antinori", name: "Villa Antinori 2025"))
        #expect(terms.first == "Villa Antinori")
        #expect(terms.contains("Marchesi Antinori Villa Antinori"))
    }

    @Test("Villa Antinori findet den Toscana Bianco 2025, nicht den Rosso anderer Jahrgänge zuerst")
    func villaAntinoriRanking() {
        let list = [
            candidate("1", "Antinori", "Villa Antinori Rosso", 2023, count: 4636),
            candidate("2", "Antinori", "Villa Antinori Toscana Bianco", 2025, count: 542),
            candidate("3", "Antinori", "Villa Antinori Toscana Bianco", 2024, count: 2131)
        ]
        let ranked = VivinoRanker.rank(list, for: entry(producer: "Marchesi Antinori", name: "Villa Antinori Bianco", vintage: 2025))
        #expect(ranked.first?.candidate.vid == "2")
    }

    @Test("Der gleiche Jahrgang steht vor dem anderen, Fremdes fällt heraus")
    func rankingPrefersVintageAndDropsOthers() {
        let list = [
            candidate("1", "Donatsch", "Unique Pinot Noir", 2013, count: 195),
            candidate("2", "Donatsch", "Unique Pinot Noir", 2021),
            candidate("3", "Peter Michael", "Le Caprice Pinot Noir", 2021),
            candidate("4", "Donatsch", "Passion Pinot Noir", 2021)
        ]
        let ranked = VivinoRanker.rank(list, for: entry())
        #expect(ranked.first?.candidate.vid == "2")
        #expect(ranked.map(\.candidate.vid).contains("1"))
        #expect(!ranked.map(\.candidate.vid).contains("3"))
    }

    @Test("Ein Tippfehler im Namen findet den Treffer trotzdem")
    func typoStillMatches() {
        let ranked = VivinoRanker.rank([candidate("1", "Donatsch", "Unique Pinot Noir", 2021)],
                                       for: entry(producer: "Donatch", name: "Uniqe Pinot Noir"))
        #expect(ranked.count == 1)
    }

    @Test("Gegenüberstellung unterscheidet gleich, abweichend, fehlend und unbekannt")
    func comparisonStates() {
        var mine = entry()
        mine.region = "Graubünden"
        let theirs = candidate("1", "Donatsch", "Unique Pinot Noir", 2021, grape: "Pinot Noir")
        let rows = Dictionary(uniqueKeysWithValues: VivinoComparison.rows(entry: mine, candidate: theirs).map { ($0.field, $0.state) })
        #expect(rows[.producer] == .same)
        #expect(rows[.vintage] == .same)
        #expect(rows[.grape] == .fillable)
        #expect(rows[.region] == .different)
        #expect(rows[.food] == .vivinoEmpty)
    }

    @Test("Leere Felder füllen lässt Abweichendes stehen")
    func fillOnlyEmpty() {
        var mine = entry()
        mine.region = "Graubünden"
        let theirs = candidate("1", "Donatsch", "Unique Pinot Noir", 2021, grape: "Pinot Noir")
        let result = VivinoComparison.apply(theirs, to: mine, states: [.fillable])
        #expect(result.grape == "Pinot Noir")
        #expect(result.region == "Graubünden")
        let all = VivinoComparison.apply(theirs, to: mine, states: [.fillable, .different])
        #expect(all.region == "Malanser")
    }

    @Test("Die Antwort des Ablaufs wird gelesen, Fehler und Lücken sind kein Absturz")
    func parsing() throws {
        let good = Data(#"{"ok":true,"candidates":[{"vid":"7","name":"X","producer":"Y","vintage":2020}]}"#.utf8)
        let list = try VivinoLookup.parse(good)
        #expect(list.count == 1)
        #expect(list[0].grape.isEmpty && list[0].foodPairings.isEmpty)
        #expect(throws: VivinoLookupError.server("Zu viele")) {
            try VivinoLookup.parse(Data(#"{"ok":false,"meldung":"Zu viele"}"#.utf8))
        }
        #expect(throws: VivinoLookupError.unreadable) { try VivinoLookup.parse(Data("<html>".utf8)) }
    }
}
