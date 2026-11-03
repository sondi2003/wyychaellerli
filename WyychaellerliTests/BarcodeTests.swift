import Testing
@testable import Wyychaellerli

/// Strichcodes: Prüfziffer, Normalisierung, Abgleich mit dem Katalog und dem eigenen Keller.
///
/// Der Strichcode ist ein Suchmerkmal, kein Schlüssel – derselbe Code kann über mehrere
/// Jahrgänge gleich bleiben. Diese Tests halten fest, dass der Jahrgang entscheidet.
struct BarcodeTests {

    // 4006381333931 ist ein gültiger EAN-13, 96385074 ein gültiger EAN-8.
    private let valid13 = "4006381333931"
    private let valid8 = "96385074"

    // MARK: Prüfziffer

    @Test("Gültige Codes bestehen die Prüfziffer")
    func validCodes() {
        #expect(Barcode.normalized(valid13) == valid13)
        #expect(Barcode.normalized(valid8) == valid8)
    }

    @Test("Eine vertauschte oder falsche Ziffer fällt durch")
    func invalidCodes() {
        #expect(Barcode.normalized("4006381333932").isEmpty)  // letzte Ziffer falsch
        #expect(Barcode.normalized("4006381333391").isEmpty)  // zwei Ziffern vertauscht
        #expect(Barcode.normalized("96385075").isEmpty)
    }

    @Test("Falsche Länge fällt durch")
    func wrongLength() {
        #expect(Barcode.normalized("12345").isEmpty)
        #expect(Barcode.normalized("").isEmpty)
        #expect(Barcode.normalized("40063813339310000").isEmpty)
    }

    @Test("Leerzeichen und Bindestriche stören nicht")
    func formatting() {
        #expect(Barcode.normalized("4006381 333931") == valid13)
        #expect(Barcode.normalized("4006-3813-33931") == valid13)
    }

    @Test("UPC-A bekommt eine führende Null wie von der Kamera gelesen")
    func upcA() {
        // 036000291452 ist ein gültiger UPC-A.
        #expect(Barcode.normalized("036000291452") == "0036000291452")
    }

    // MARK: Listen

    @Test("Mehrere Codes, ungültige und doppelte fallen weg")
    func list() {
        let text = "\(valid13), 12345; \(valid8) \(valid13)"
        #expect(Barcode.list(from: text) == [valid13, valid8])
    }

    @Test("Tippfehler werden gemeldet")
    func invalidEntry() {
        #expect(Barcode.hasInvalidEntry(in: "4006381333932"))
        #expect(!Barcode.hasInvalidEntry(in: valid13))
        #expect(!Barcode.hasInvalidEntry(in: ""))
    }

    // MARK: Katalog

    private func entry(_ name: String, vintage: Int, gtins: [String]) -> CatalogWine {
        CatalogWine(
            id: name + String(vintage), name: name, producer: "Cicero", vintage: vintage,
            grape: "", region: "", country: "", typeRaw: "red", alcoholPercent: 0,
            source: "nutzer", gtins: gtins
        )
    }

    @Test("Bei bekanntem Jahrgang entscheidet er zwischen Einträgen mit demselben Code")
    func vintageDecides() {
        let entries = [
            entry("Pinot Noir", vintage: 2022, gtins: [valid13]),
            entry("Pinot Noir", vintage: 2023, gtins: [valid13])
        ]
        #expect(CatalogMatcher.match(barcode: valid13, vintage: 2023, in: entries)?.vintage == 2023)
        #expect(CatalogMatcher.match(barcode: valid13, vintage: 2022, in: entries)?.vintage == 2022)
    }

    @Test("Ein neuer Jahrgang trifft keinen alten Eintrag")
    func newVintageIsNotFound() {
        let entries = [entry("Pinot Noir", vintage: 2022, gtins: [valid13])]
        #expect(CatalogMatcher.match(barcode: valid13, vintage: 2024, in: entries) == nil)
    }

    @Test("Ein Eintrag ohne Jahrgang springt ein, wenn es keinen gleichen gibt")
    func entryWithoutVintageFallsIn() {
        let entries = [entry("Pinot Noir", vintage: 0, gtins: [valid13])]
        #expect(CatalogMatcher.match(barcode: valid13, vintage: 2024, in: entries)?.vintage == 0)
    }

    @Test("Ohne Jahrgang gilt nur ein eindeutiger Treffer")
    func unknownVintageNeedsUniqueHit() {
        let one = [entry("Pinot Noir", vintage: 2022, gtins: [valid13])]
        #expect(CatalogMatcher.match(barcode: valid13, vintage: 0, in: one) != nil)
        // Bei mehreren Jahrgängen zu raten hiesse, einen Jahrgang zu erfinden.
        let two = one + [entry("Pinot Noir", vintage: 2023, gtins: [valid13])]
        #expect(CatalogMatcher.match(barcode: valid13, vintage: 0, in: two) == nil)
    }

    @Test("Ein anderer Code trifft nichts, ein leerer erst recht")
    func otherCode() {
        let entries = [entry("Pinot Noir", vintage: 2022, gtins: [valid13])]
        #expect(CatalogMatcher.match(barcode: valid8, vintage: 2022, in: entries) == nil)
        #expect(CatalogMatcher.match(barcode: "", vintage: 2022, in: entries) == nil)
    }

    @Test("Der Schlüssel hängt nicht am Strichcode")
    func keyIgnoresBarcode() {
        // Zwei Jahrgänge mit demselben Code müssen zwei Einträge bleiben.
        let a = SubmissionDraft(name: "Pinot Noir", producer: "Cicero", vintage: 2022, grape: "", region: "",
                                country: "", typeRaw: "red", alcoholPercent: 0, wineUUID: "", labelImageData: nil, barcode: valid13)
        let b = SubmissionDraft(name: "Pinot Noir", producer: "Cicero", vintage: 2023, grape: "", region: "",
                                country: "", typeRaw: "red", alcoholPercent: 0, wineUUID: "", labelImageData: nil, barcode: valid13)
        #expect(a.catalogKey != b.catalogKey)
        #expect(a.catalogKey.hasPrefix("wine_"))
    }

    @Test("Eine Ergänzung trägt die Angaben und den Schlüssel des bestehenden Eintrags")
    func additionKeepsEntry() {
        let existing = entry("Pinot Noir", vintage: 2022, gtins: [])
        let draft = SubmissionDraft(adding: valid13, to: existing, wineUUID: "x")
        #expect(draft.catalogKey == existing.id)
        #expect(draft.labelImageData == nil)
        #expect(draft.barcode == valid13)
    }

    @Test("Aus einem Vorschlag wird ein Eintrag mit seinem Strichcode")
    func submissionCarriesBarcode() {
        let submission = CatalogSubmission(
            id: "1", name: "Pinot Noir", producer: "Cicero", vintage: 2023, grape: "", region: "", country: "",
            typeRaw: "red", alcoholPercent: 0, catalogKey: "k", wineUUID: "", status: .pending, createdAt: nil,
            labelImageData: nil, barcode: valid13
        )
        #expect(submission.asCatalogWine.gtins == [valid13])
        let without = CatalogSubmission(
            id: "2", name: "Pinot Noir", producer: "Cicero", vintage: 2023, grape: "", region: "", country: "",
            typeRaw: "red", alcoholPercent: 0, catalogKey: "k", wineUUID: "", status: .pending, createdAt: nil
        )
        #expect(without.asCatalogWine.gtins.isEmpty)
    }

    @Test("Die Gruppe sammelt die Strichcodes aller Einreicher")
    func groupMergesBarcodes() {
        func submission(_ id: String, _ code: String) -> CatalogSubmission {
            CatalogSubmission(
                id: id, name: "Pinot Noir", producer: "Cicero", vintage: 2023, grape: "", region: "", country: "",
                typeRaw: "red", alcoholPercent: 0, catalogKey: "k", wineUUID: "", status: .pending, createdAt: nil,
                labelImageData: nil, barcode: code
            )
        }
        let group = SubmissionGroup(id: "k", items: [submission("1", valid13), submission("2", valid8), submission("3", valid13), submission("4", "")])
        #expect(group.asCatalogWine.gtins == [valid13, valid8])
    }

    @Test("Im Admin-Bereich lässt sich nach einem Strichcode suchen")
    func filterFindsBarcode() {
        let entries = [entry("Pinot Noir", vintage: 2022, gtins: [valid13]), entry("Chardonnay", vintage: 2022, gtins: [])]
        #expect(CatalogFilter(text: valid13).apply(to: entries).map(\.name) == ["Pinot Noir"])
    }

    @Test("Eine Ergänzung erkennt der Admin an gleichen Angaben")
    func additionIsRecognised() {
        let existing = entry("Pinot Noir", vintage: 2022, gtins: [valid8])
        var proposed = existing
        proposed.gtins = [valid13]
        proposed.source = "nutzer"
        #expect(AdminSubmissionEditor.differsOnlyByBarcode(proposed, from: existing))
        proposed.grape = "Pinot Noir"
        #expect(!AdminSubmissionEditor.differsOnlyByBarcode(proposed, from: existing))
        // Dieselben Codes: nichts Neues.
        proposed = existing
        #expect(!AdminSubmissionEditor.differsOnlyByBarcode(proposed, from: existing))
    }

    // MARK: Eigener Keller

    @Test("Gleicher Code und gleicher Jahrgang ist dieselbe Flasche, auch bei anderem Namen")
    func duplicateByBarcode() {
        let a = DuplicateFinder.Candidate(name: "Pinot Nolr", producer: "", vintage: 2023, barcode: valid13)
        let b = DuplicateFinder.Candidate(name: "Pinot Noir Réserve", producer: "Cicero", vintage: 2023, barcode: valid13)
        #expect(DuplicateFinder.similarity(a, b) == 1)
    }

    @Test("Gleicher Code, aber anderer Jahrgang ist eine andere Flasche")
    func duplicateByBarcodeOtherVintage() {
        let a = DuplicateFinder.Candidate(name: "Pinot Noir", producer: "Cicero", vintage: 2022, barcode: valid13)
        let b = DuplicateFinder.Candidate(name: "Pinot Noir", producer: "Cicero", vintage: 2023, barcode: valid13)
        #expect(DuplicateFinder.similarity(a, b) == nil)
    }

    // MARK: Wein

    @MainActor
    @Test("Am Wein wird nur ein gültiger Code gespeichert")
    func wineStoresOnlyValid() {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        let good = Wine.create(in: context, cellar: cellar, name: "A", producer: "", vintage: 2020, grape: "", region: "",
                               country: "", type: .red, quantity: 1, notes: "", barcode: valid13)
        let bad = Wine.create(in: context, cellar: cellar, name: "B", producer: "", vintage: 2020, grape: "", region: "",
                              country: "", type: .red, quantity: 1, notes: "", barcode: "4006381333932")
        #expect(good.barcode == valid13)
        #expect(bad.barcode.isEmpty)
    }
}
