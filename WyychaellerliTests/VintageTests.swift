import Testing
@testable import Wyychaellerli

/// Der Jahrgang wird **nie erfunden**.
///
/// Steht keiner auf dem Etikett, bleibt das Feld leer (0) und wird nirgends angezeigt.
/// Ein falscher Jahrgang ist schlimmer als keiner: Er sieht aus wie eine Tatsache,
/// verfälscht die Trinkreife und lässt zwei Flaschen als verschieden erscheinen.
struct VintageTests {

    // MARK: Erkennung aus dem Etikettentext

    @Test("Jahrgang wird gelesen, wenn er dasteht")
    func readsVintage() {
        let text = "Château Test\n2018\nAppellation Bordeaux Contrôlée"
        #expect(HeuristicLabelParser.parse(recognizedText: text).vintage == 2018)
    }

    @Test("Ohne Jahrgang bleibt das Feld leer")
    func noVintage() {
        let text = "Château Test\nAppellation Bordeaux Contrôlée\n13,5 % vol"
        // Kein Rückfall auf das aktuelle Jahr, keine Schätzung.
        #expect(HeuristicLabelParser.parse(recognizedText: text).vintage == 0)
    }

    @Test("Postleitzahl in der Adresse ist kein Jahrgang")
    func postalCodeIsNotVintage() {
        // Schweizer Etiketten nennen die Adresse des Winzers; „2000 Neuchâtel“ und
        // „1950 Sion“ liegen mitten im Jahrgangsbereich.
        #expect(HeuristicLabelParser.parse(recognizedText: "Cave du Test\n2000 Neuchâtel").vintage == 0)
        #expect(HeuristicLabelParser.parse(recognizedText: "Domaine Test\n1950 Sion\nFendant").vintage == 0)
    }

    @Test("Ausdrücklich bezeichneter Jahrgang schlägt die Adresse")
    func labelledVintageWins() {
        let text = "Cave du Test\n2000 Neuchâtel\nJahrgang 2019"
        #expect(HeuristicLabelParser.parse(recognizedText: text).vintage == 2019)
    }

    @Test("Fremdsprachige Bezeichnungen", arguments: [
        "Millésime 2016", "Vintage 2016", "Annata 2016", "Cosecha 2016"
    ])
    func labelledVintageForeign(line: String) {
        #expect(HeuristicLabelParser.parse(recognizedText: "Weingut Test\n\(line)").vintage == 2016)
    }

    @Test("Zahlen ausserhalb der Spanne zählen nicht")
    func outOfRange() {
        // Alkoholgehalt, Füllmenge, Jahreszahlen wie „seit 1850“ sind keine Jahrgänge.
        #expect(HeuristicLabelParser.parse(recognizedText: "Weingut Test\nseit 1850\n750 ml").vintage == 0)
    }

    // MARK: Darstellung

    @Test("Ohne Jahrgang steht in der Kurzform keine Null")
    @MainActor
    func subtitleWithoutVintage() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, vintage: 0, grape: "Merlot", country: "Schweiz")

        #expect(!wine.hasVintage)
        #expect(wine.vintageText.isEmpty)
        // Früher erschien hier „0 · Merlot · Schweiz“.
        #expect(!wine.subtitle.contains("0"))
        #expect(wine.subtitle == "Merlot · Schweiz")
    }

    @Test("Mit Jahrgang steht er vorn")
    @MainActor
    func subtitleWithVintage() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, vintage: 2019, grape: "Merlot", country: "Schweiz")

        #expect(wine.hasVintage)
        #expect(wine.subtitle == "2019 · Merlot · Schweiz")
    }

    @Test("Name mit Jahrgang für Dialoge")
    @MainActor
    func nameWithVintage() {
        let context = TestStack.makeContext()
        let withYear = TestStack.makeWine(in: context, name: "Barolo", vintage: 2018)
        let without = TestStack.makeWine(in: context, name: "Hauswein", vintage: 0)

        #expect(withYear.nameWithVintage == "Barolo 2018")
        // Nicht „Hauswein 0“.
        #expect(without.nameWithVintage == "Hauswein")
    }

    // MARK: Formular

    @Test("Ein neuer Wein startet ohne Jahrgang")
    @MainActor
    func formStartsEmpty() {
        // Vorher stand hier „aktuelles Jahr minus zwei“ – fand der Scan nichts,
        // wurde diese Erfindung gespeichert.
        let model = WineFormViewModel(mode: .add)
        #expect(model.vintage == 0)
    }

    @Test("„Ohne Jahrgang“ ist im Formular wählbar")
    @MainActor
    func formOffersNoVintage() {
        #expect(WineFormViewModel.vintageChoices.first == 0)
        #expect(WineFormViewModel.vintageChoices.contains(2019))
    }

    @Test("Ein nicht erkannter Jahrgang überschreibt nichts")
    @MainActor
    func scanKeepsEmptyVintage() {
        let model = WineFormViewModel(mode: .add)
        model.vintage = 0

        var extraction = WineLabelExtraction()
        extraction.name = "Testwein"
        extraction.vintage = 0
        model.apply(LabelScanResult(
            extraction: extraction,
            recognizedText: "Testwein",
            source: .heuristic,
            labelImageData: nil,
            backLabelImageData: nil
        ))

        #expect(model.name == "Testwein")
        #expect(model.vintage == 0)
    }
}
