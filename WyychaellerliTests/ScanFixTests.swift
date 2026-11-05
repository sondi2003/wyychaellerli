import Foundation
import Testing
@testable import Wyychaellerli

/// Drei Fehler aus der Analyse des Scan-Wegs vom 2.11.2026.
@MainActor
struct ScanFixTests {

    // MARK: Jahrgang beim Auffüllen einer KI-Antwort

    @Test("„Depuis 1952“ ist kein Jahrgang – weder für die Regeln noch zum Auffüllen")
    func foundingYearIsNotAVintage() {
        let text = "Domaine Test\nDepuis 1952\nLa Pinède\n13,5 % vol"
        #expect(HeuristicLabelParser.parse(recognizedText: text).vintage == 0)
        #expect(HeuristicLabelParser.confidentVintage(recognizedText: text) == 0)
    }

    @Test("Abfüllung ist kein Jahrgang")
    func bottlingYearIsNotAVintage() {
        let text = "Château Test\nMis en bouteille 2021\nAbgefüllt 2022"
        #expect(HeuristicLabelParser.parse(recognizedText: text).vintage == 0)
    }

    @Test("Zum Auffüllen zählt nur, was ausdrücklich dasteht")
    func confidentVintage() {
        #expect(HeuristicLabelParser.confidentVintage(recognizedText: "Cave\nMillésime 2019") == 2019)
        #expect(HeuristicLabelParser.confidentVintage(recognizedText: "Cave\n2018\nBordeaux") == 2018)
        // In der Namenszeile: für die Regeln allein genug, zum Auffüllen nicht.
        #expect(HeuristicLabelParser.confidentVintage(recognizedText: "Château Margaux 2015") == 0)
        #expect(HeuristicLabelParser.parse(recognizedText: "Château Margaux 2015").vintage == 2015)
    }

    @Test("Das Auffüllen setzt keinen Jahrgang ein, den die KI bewusst leer liess")
    func mergeKeepsEmptyVintage() {
        var primary = WineLabelExtraction()
        primary.name = "La Pinède"
        var filler = WineLabelExtraction()
        filler.vintage = 0
        filler.alcoholPercent = 13.5
        let merged = LabelScanService.merge(primary, with: filler)
        #expect(merged.vintage == 0)
        // Was die Regeln sicher lesen, füllt weiter auf.
        #expect(merged.alcoholPercent == 13.5)
    }

    // MARK: Weinart

    @Test("Erkennt der Scan die Weinart nicht, wird das sichtbar")
    func unknownTypeNeedsReview() {
        let model = WineFormViewModel(mode: .add)
        var extraction = WineLabelExtraction()
        extraction.name = "Test"
        extraction.type = "unknown"
        model.apply(LabelScanResult(extraction: extraction, recognizedText: "", source: .heuristic, labelImageData: nil, backLabelImageData: nil))
        #expect(model.typeNeedsReview)

        extraction.type = "white"
        model.apply(LabelScanResult(extraction: extraction, recognizedText: "", source: .heuristic, labelImageData: nil, backLabelImageData: nil))
        #expect(!model.typeNeedsReview)
        #expect(model.type == .white)
    }

    // MARK: Notizen

    @Test("Ein zweiter Scan hängt dieselbe Notiz nicht nochmals an")
    func notesAreNotDuplicated() {
        let model = WineFormViewModel(mode: .add)
        var extraction = WineLabelExtraction()
        extraction.name = "Test"
        extraction.notes = "Schieferterrassen, lange Mazeration."
        let result = LabelScanResult(extraction: extraction, recognizedText: "", source: .heuristic, labelImageData: nil, backLabelImageData: nil)
        model.apply(result)
        model.apply(result)
        #expect(model.notes == "Schieferterrassen, lange Mazeration.")
    }

    // MARK: Sommelier-Daten

    @Test("Alkohol, Gründe der Bewertung und längere Notizen gehen an den Sommelier")
    func inventoryCarriesMore() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Barolo", alcoholPercent: 14.5)
        wine.notes = String(repeating: "x", count: 450)
        let item = wine.inventoryItem
        #expect(item.alcohol.contains("14,5"))
        #expect(item.notes.count == 450)
        #expect(item.ratingReasons.isEmpty)
    }

    @Test("Die Gründe der Bewertungen werden gezählt")
    func ratingReasonsAreCounted() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Barolo")
        let first = Rating.create(in: context, wine: wine, raterID: "a", raterName: "A")
        first.stars = 3
        first.tags = ["Zu herb", "Gerne wieder"]
        let second = Rating.create(in: context, wine: wine, raterID: "b", raterName: "B")
        second.stars = 2
        second.tags = ["Zu herb"]
        #expect(wine.ratingReasonsText == "Zu herb (2×), Gerne wieder (1×)")
    }

    @Test("Die Personenzahl steht im Prompt, wenn sie angegeben ist")
    func guestsInPrompt() {
        let withGuests = PairingRequest(dish: "Raclette", inventory: [], guests: 8)
        #expect(PromptBuilder.userPrompt(for: withGuests).contains("Personen: 8"))
        let without = PairingRequest(dish: "Raclette", inventory: [])
        #expect(!PromptBuilder.userPrompt(for: without).contains("Personen"))
        #expect(PairingRequest(dish: "x", inventory: [], guests: 0).guests == nil)
    }
}

/// Der Name stammt von der Vorderseite, nicht aus den Pflichtangaben hinten.
/// Fall aus dem Katalog (5.11.2026): „Nettoinhalt / Netto inhoud / Volume net“ wurde als
/// Weinname vorgeschlagen, weil die Regeln die erste gemischt geschriebene Zeile nahmen.
@Suite("Weinname aus der Texterkennung")
struct NameDetectionTests {

    private let prosecco = """
    [Vorderseite]
    VALDOBBIADENE
    PROSECCO
    SUPERIORE
    EXTRA
    DRY
    2025
    ITALIA

    [Rückseite]
    etinhalt:/ Netto inhoud: / Volume net: /
    750 ml
    Contiene solfiti / Contains sulphites
    """

    @Test("Pflichtangaben der Rückseite sind kein Name")
    func ignoresBackLabelBoilerplate() {
        let name = HeuristicLabelParser.parse(recognizedText: prosecco).name
        #expect(!name.lowercased().contains("inhoud"))
        #expect(name == "Valdobbiadene")
    }

    @Test("Der Name kommt von vorne, auch wenn hinten schöner geschrieben steht")
    func prefersFront() {
        let text = "[Vorderseite]\nLa Pinède\n\n[Rückseite]\nMis en bouteille au domaine\nVin de Pays"
        #expect(HeuristicLabelParser.parse(recognizedText: text).name == "La Pinède")
    }

    @Test("Hinten allein genügt, wenn vorne nichts Brauchbares steht")
    func fallsBackToBack() {
        let text = "[Vorderseite]\n2019\n\n[Rückseite]\nLa Pinède"
        #expect(HeuristicLabelParser.parse(recognizedText: text).name == "La Pinède")
    }

    @Test("Zeilen mit Doppelpunkt, Schrägstrich oder Land sind nie ein Name")
    func rejectsSeparatorsAndCountries() {
        let text = "[Vorderseite]\nNetto inhoud: / Volume net\nItalia\nMerlot del Veneto"
        #expect(HeuristicLabelParser.parse(recognizedText: text).name == "Merlot del Veneto")
    }
}
