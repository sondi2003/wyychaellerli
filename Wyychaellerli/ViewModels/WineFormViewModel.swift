import CoreData
import Foundation
import Observation

/// Formularzustand für „Wein hinzufügen“ und „Wein bearbeiten“.
@Observable
@MainActor
final class WineFormViewModel {

    enum Mode {
        case add
        case edit(Wine)

        var title: String {
            switch self {
            case .add:  return tr("Wein hinzufügen")
            case .edit: return tr("Wein bearbeiten")
            }
        }
    }

    let mode: Mode

    var name: String
    var producer: String
    var vintage: Int
    var grape: String
    var region: String
    var country: String
    var type: WineType
    /// `true`, wenn ein Scan die Weinart nicht erkannt hat und die Vorgabe nur geraten ist.
    var typeNeedsReview = false
    var quantity: Int
    var notes: String
    /// Volumenprozent; 0 heisst „keine Angabe“.
    var alcoholPercent: Double
    /// Strichcode, wie getippt oder gescannt. Gespeichert wird nur ein gültiger.
    var barcode: String
    /// Kommagetrennt im Formular, als Liste am Wein.
    var foodPairings: String
    /// Zugeschnittenes Etikett-Foto der Vorderseite (JPEG), wird mit dem Wein gespeichert.
    var labelImageData: Data?
    /// Dasselbe für die Rückseite.
    var backLabelImageData: Data?
    /// Empfohlene Trinkjahre; 0 heisst „keine Angabe“.
    var drinkFrom: Int
    var drinkTo: Int
    /// Merkt sich, ob die Spanne vom Etikett stammt oder geschätzt wurde.
    var drinkWindowFromLabel: Bool

    /// Quelle der letzten Etikett-Erkennung – für den Hinweis im Formular.
    var lastScanSource: LabelExtractionSource?

    /// Flaschen, die es offenbar schon gibt – auch archivierte und leere.
    /// Wird beim Tippen und direkt nach dem Scan neu bestimmt.
    var duplicates: [DuplicateFinder.Match] = []
    /// Nach „Trotzdem neu anlegen“ soll der Hinweis nicht wieder aufpoppen.
    var ignoresDuplicates = false

    var visibleDuplicate: Wine? {
        guard case .add = mode, !ignoresDuplicates else { return nil }
        return duplicates.first?.wine
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            name = ""
            producer = ""
            // **Keine Vorgabe.** Vorher stand hier „aktuelles Jahr minus zwei“ – fand der
            // Scan keinen Jahrgang, wurde diese Erfindung gespeichert. Lieber kein
            // Jahrgang als ein falscher.
            vintage = 0
            grape = ""
            region = ""
            country = ""
            type = .red
            quantity = 1
            notes = ""
            alcoholPercent = 0
            barcode = ""
            foodPairings = ""
            labelImageData = nil
            backLabelImageData = nil
            drinkFrom = 0
            drinkTo = 0
            drinkWindowFromLabel = false
        case .edit(let wine):
            name = wine.name
            producer = wine.producer
            vintage = Int(wine.vintage)
            grape = wine.grape
            region = wine.region
            country = wine.country
            type = wine.type
            quantity = Int(wine.quantity)
            notes = wine.notes
            alcoholPercent = wine.alcoholPercent
            barcode = wine.barcode
            foodPairings = wine.foodPairings.joined(separator: ", ")
            labelImageData = wine.labelImageData
            backLabelImageData = wine.backLabelImageData
            drinkFrom = Int(wine.drinkFrom)
            drinkTo = Int(wine.drinkTo)
            drinkWindowFromLabel = wine.drinkWindowFromLabel
        }
    }

    /// Auswahl für die Trinkreife: rückwirkend, weil ältere Flaschen ihr Fenster schon
    /// hinter sich haben können, und weit nach vorne für lagerfähige Weine.
    static var drinkYearRange: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array((current - 30)...(current + 40))
    }

    /// Sinnvolle Jahrgangsspanne für den Picker.
    static var vintageRange: ClosedRange<Int> {
        let current = Calendar.current.component(.year, from: .now)
        return 1950...current
    }

    /// Auswahl im Formular: „ohne Jahrgang“ (0) zuoberst, dann die Jahre absteigend.
    static var vintageChoices: [Int] {
        [0] + vintageRange.reversed()
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Der gültige Strichcode oder leer.
    var validBarcode: String { Barcode.normalized(barcode) }

    /// Etwas eingetippt, das die Prüfziffer nicht besteht – das Formular sagt es, statt es
    /// still zu verwerfen.
    var barcodeIsInvalid: Bool { !barcode.isEmpty && validBarcode.isEmpty }

    var canSave: Bool {
        !trimmedName.isEmpty && quantity >= 0
    }

    /// Übernimmt erkannte Etikett-Felder. Leere Werte überschreiben nichts.
    func apply(_ scan: LabelScanResult) {
        let extraction = scan.extraction
        if !extraction.name.isEmpty { name = extraction.name }
        if !extraction.producer.isEmpty { producer = extraction.producer }
        if Self.vintageRange.contains(extraction.vintage) { vintage = extraction.vintage }
        if !extraction.grape.isEmpty { grape = extraction.grape }
        if !extraction.region.isEmpty { region = extraction.region }
        if !extraction.country.isEmpty { country = extraction.country }
        if let wineType = extraction.wineType {
            type = wineType
            typeNeedsReview = false
        } else if case .add = mode {
            // Die Vorgabe „Rotwein“ darf nicht still als Erkennung durchgehen.
            typeNeedsReview = true
        }
        // Der Code kommt aus der Kamera, nicht aus dem Modell. Ein neuer Scan ersetzt den alten.
        if !scan.barcode.isEmpty { barcode = scan.barcode }
        if let imageData = scan.labelImageData { labelImageData = imageData }
        if let backImageData = scan.backLabelImageData { backLabelImageData = backImageData }
        if extraction.drinkFrom > 0, extraction.drinkTo >= extraction.drinkFrom {
            drinkFrom = extraction.drinkFrom
            drinkTo = extraction.drinkTo
            drinkWindowFromLabel = extraction.drinkWindowFromLabel
        }
        if !extraction.foodPairings.isEmpty {
            foodPairings = extraction.foodPairings.joined(separator: ", ")
        }

        // Der Alkoholgehalt hat ein eigenes Feld – früher wurde er als Textzeile in die
        // Notizen geschrieben und für die Anzeige per Mustersuche wieder herausgeklaubt.
        if extraction.alcoholPercent > 0 { alcoholPercent = extraction.alcoholPercent }

        // Ein zweiter Scan darf dieselbe Notiz nicht nochmals anhängen.
        let scannedNote = extraction.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scannedNote.isEmpty {
            let existing = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !existing.localizedCaseInsensitiveContains(scannedNote) {
                notes = [existing, scannedNote].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        lastScanSource = scan.source
    }

    /// Der Katalogeintrag, aus dem nach dem Scan Lücken gefüllt wurden.
    var catalogMatch: CatalogWine?

    /// Ein Treffer, der dem Nutzer gezeigt wird und auf seine Antwort wartet.
    var catalogCandidate: CatalogWine?
    /// „Anderer Wein“: Dieser Treffer wird nicht noch einmal angeboten.
    private(set) var declinedCatalogID: String?

    /// Das Etikettfoto des Katalogeintrags. Hat der Nutzer noch kein eigenes Foto, wird es mit
    /// der Bestätigung des Weins übernommen (`adoptCatalogImageIfFree`); ein eigenes Foto
    /// ersetzt es **nie** von selbst, dann bleibt es ein Angebot („Verwenden“).
    var catalogImageData: Data?
    /// Das eigene Foto, solange das Katalogfoto an seiner Stelle steht (für „Mein Foto“).
    private var ownImageData: Data?

    /// Der Katalogeintrag stammt aus der Auswahl unter dem Namensfeld (nicht aus einem Scan).
    private var pickedFromSuggestions = false
    private var pickedAt: Date?
    /// So lange gilt eine Änderung am Namen nach der Wahl nicht als Absicht (Autokorrektur).
    static let suggestionGrace: TimeInterval = 1.0

    /// Ändert der Nutzer den Namen, nachdem er einen Vorschlag gewählt hat, und es ist nicht
    /// mehr derselbe Wein, gilt die Wahl nicht mehr: Die Vorschläge erscheinen wieder, das
    /// Katalogfoto verschwindet. Bereits ergänzte Felder bleiben, sie gehören jetzt ihm.
    func releaseSuggestionIfNameChanged() {
        guard pickedFromSuggestions, let match = catalogMatch,
              CatalogDirectory.fold(trimmedName) != CatalogDirectory.fold(match.name) else { return }
        // Eine Sekunde Schonfrist nach der Wahl: Was die Tastatur gleich danach noch am Namen
        // ändert, ist keine Entscheidung des Nutzers. Der Name wird dann zurückgesetzt.
        if let picked = pickedAt, Date().timeIntervalSince(picked) < Self.suggestionGrace {
            name = match.name
            return
        }
        pickedFromSuggestions = false
        pickedAt = nil
        catalogMatch = nil
        if labelImageData != nil, labelImageData == catalogImageData {
            labelImageData = ownImageData
            ownImageData = nil
        }
        catalogImageData = nil
    }

    /// Die Vorschläge unter dem Namensfeld (Suche beim Tippen auf dem Gerät).
    var suggestions: [CatalogDirectory.Suggestion] = []

    /// Zeigt die Suche Vorschläge, hat der Nutzer sie aber nicht angenommen? Dann bleibt der
    /// Katalog beim Sichern unberührt: Es ist unklar, ob er einen davon meinte.
    func updateSuggestions(_ found: [CatalogDirectory.Suggestion]) {
        guard case .add = mode, catalogMatch == nil, catalogCandidate == nil else {
            suggestions = []
            return
        }
        if found != suggestions { suggestions = found }
    }

    /// Der Nutzer wählt einen Wein aus den Vorschlägen: Name, Produzent und Jahrgang kommen
    /// aus dem Katalog, leere Felder werden ergänzt, Eigenes bleibt.
    func selectSuggestion(_ entry: CatalogWine) {
        pickedFromSuggestions = true
        pickedAt = Date()
        name = entry.name
        if producer.isEmpty { producer = entry.producer }
        if Self.vintageRange.contains(entry.vintage) { vintage = entry.vintage }
        catalogCandidate = nil
        declinedCatalogID = nil
        suggestions = []
        fillGaps(from: entry)
    }

    /// Was beim Sichern an den Katalog geht, je nach Antwort des Nutzers.
    var catalogChoice: CatalogCenter.CatalogChoice {
        if let catalogMatch { return .confirmed(catalogMatch) }
        if let catalogCandidate { return .ignored(id: catalogCandidate.id) }
        if let offered = suggestions.first?.entries.first { return .ignored(id: offered.id) }
        if let declinedCatalogID { return .declined(id: declinedCatalogID) }
        return .none
    }

    /// Ein Treffer des Katalogs. Ein Strichcodetreffer mit gleichem Jahrgang ist so gut wie
    /// sicher und wird gleich übernommen; alles andere fragt zuerst.
    func offerCatalogEntry(_ entry: CatalogWine?) {
        guard let entry else {
            catalogCandidate = nil
            return
        }
        guard entry.id != declinedCatalogID, entry.id != catalogMatch?.id else { return }
        let code = validBarcode
        if !code.isEmpty, entry.gtins.contains(code), vintage == 0 || entry.vintage == vintage {
            catalogCandidate = nil
            fillGaps(from: entry)
        } else {
            catalogCandidate = entry
        }
    }

    func confirmCatalogCandidate() {
        guard let entry = catalogCandidate else { return }
        catalogCandidate = nil
        fillGaps(from: entry)
    }

    func declineCatalogCandidate() {
        declinedCatalogID = catalogCandidate?.id
        catalogCandidate = nil
    }

    /// Wer einen Wein aus dem Katalog bestätigt hat und noch kein Foto besitzt, bekommt das
    /// des Katalogs. Vorher musste man „Verwenden“ antippen – das übersah man, und der Wein
    /// landete ohne Bild im Keller (TestFlight, 5.11.2026).
    func adoptCatalogImageIfFree() {
        guard let catalogImageData, labelImageData == nil else { return }
        ownImageData = nil
        labelImageData = catalogImageData
    }

    /// Gibt es ein eigenes Foto, zu dem „Mein Foto“ zurückführen kann?
    var hasOwnImageToRestore: Bool { ownImageData != nil }

    /// Wechselt zwischen dem eigenen Foto und dem aus dem Katalog.
    func toggleCatalogImage() {
        guard let catalogImageData else { return }
        if labelImageData == catalogImageData {
            labelImageData = ownImageData
            ownImageData = nil
        } else {
            ownImageData = labelImageData
            labelImageData = catalogImageData
        }
    }

    /// Ergänzt aus dem gemeinsamen Katalog, was der Scan nicht gefunden hat. Überschreibt
    /// nie etwas: Das Etikett in der Hand gilt mehr als der Katalog.
    func fillGaps(from entry: CatalogWine) {
        catalogMatch = entry
        if producer.isEmpty { producer = entry.producer }
        if vintage == 0, Self.vintageRange.contains(entry.vintage) { vintage = entry.vintage }
        if grape.isEmpty { grape = entry.grape }
        if region.isEmpty { region = entry.region }
        if country.isEmpty { country = entry.country }
        if alcoholPercent == 0 { alcoholPercent = entry.alcoholPercent }
        // Speisen aus dem Katalog nur, wenn das Etikett keine nennt.
        if foodPairings.trimmingCharacters(in: .whitespaces).isEmpty, !entry.foodPairings.isEmpty {
            foodPairings = entry.foodPairings.joined(separator: ", ")
        }
        if typeNeedsReview, let wineType = entry.wineType {
            type = wineType
            typeNeedsReview = false
        }
    }

    /// Kommaliste in einzelne Begriffe zerlegen.
    private var pairingList: [String] {
        foodPairings
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Sucht nach einer Flasche, die es schon gibt. Läuft bei jeder Änderung an Name,
    /// Produzent oder Jahrgang – der Keller ist klein genug, dass das nichts kostet.
    func checkForDuplicates(in context: NSManagedObjectContext) {
        guard case .add = mode else { duplicates = []; return }
        let candidate = DuplicateFinder.Candidate(
            name: trimmedName,
            producer: producer.trimmingCharacters(in: .whitespacesAndNewlines),
            vintage: vintage,
            barcode: validBarcode
        )
        duplicates = DuplicateFinder.findDuplicates(of: candidate, in: context)
    }

    /// Bucht auf die bestehende Flasche statt einen zweiten Eintrag anzulegen.
    ///
    /// Holt sie dabei aus dem Archiv zurück: Wer nachkauft, will den Wein wieder im Keller
    /// sehen und nicht im Archiv suchen müssen.
    func addToExisting(_ wine: Wine, in context: NSManagedObjectContext) {
        wine.quantity += Int64(max(1, quantity))
        wine.isArchived = false
        // Fehlende Etikettfotos aus dem frischen Scan ergänzen – nie vorhandene ersetzen.
        if wine.labelImageData == nil, let labelImageData { wine.labelImageData = labelImageData }
        if wine.backLabelImageData == nil, let backLabelImageData { wine.backLabelImageData = backLabelImageData }
        if wine.barcode.isEmpty { wine.barcode = validBarcode }
        context.saveChanges()
    }

    /// Schreibt das Formular in den Context (neu anlegen oder aktualisieren).
    /// Gibt den neu angelegten Wein zurück, beim Bearbeiten `nil`.
    @discardableResult
    func save(in context: NSManagedObjectContext) -> Wine? {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        var created: Wine?
        switch mode {
        case .add:
            created = Wine.create(
                in: context,
                cellar: Cellar.active(in: context),
                name: trimmedName,
                producer: trimmed(producer),
                vintage: vintage,
                grape: trimmed(grape),
                region: trimmed(region),
                country: trimmed(country),
                type: type,
                quantity: quantity,
                notes: trimmed(notes),
                alcoholPercent: alcoholPercent,
                barcode: barcode,
                foodPairings: pairingList,
                labelImageData: labelImageData,
                backLabelImageData: backLabelImageData,
                drinkFrom: drinkFrom,
                drinkTo: drinkTo,
                drinkWindowFromLabel: drinkWindowFromLabel
            )
        case .edit(let wine):
            wine.name = trimmedName
            wine.producer = trimmed(producer)
            wine.vintage = Int64(vintage)
            wine.grape = trimmed(grape)
            wine.region = trimmed(region)
            wine.country = trimmed(country)
            wine.type = type
            wine.quantity = Int64(max(0, quantity))
            wine.notes = trimmed(notes)
            wine.alcoholPercent = max(0, alcoholPercent)
            wine.barcode = validBarcode
            wine.foodPairings = pairingList
            wine.labelImageData = labelImageData
            wine.backLabelImageData = backLabelImageData
            wine.drinkFrom = Int64(max(0, drinkFrom))
            wine.drinkTo = Int64(max(0, drinkTo))
            wine.drinkWindowFromLabel = drinkWindowFromLabel
        }
        context.saveChanges()
        return created
    }
}
