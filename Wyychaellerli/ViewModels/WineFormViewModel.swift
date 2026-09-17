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
            case .add:  return "Wein hinzufügen"
            case .edit: return "Wein bearbeiten"
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
    var quantity: Int
    var notes: String
    /// Volumenprozent; 0 heisst „keine Angabe“.
    var alcoholPercent: Double
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
        if let wineType = extraction.wineType { type = wineType }
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

        var extraNotes: [String] = []
        if !extraction.notes.isEmpty { extraNotes.append(extraction.notes) }
        if !extraNotes.isEmpty {
            let existing = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            notes = ([existing] + extraNotes).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        lastScanSource = scan.source
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
            vintage: vintage
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
        context.saveChanges()
    }

    /// Schreibt das Formular in den Context (neu anlegen oder aktualisieren).
    func save(in context: NSManagedObjectContext) {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch mode {
        case .add:
            Wine.create(
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
            wine.foodPairings = pairingList
            wine.labelImageData = labelImageData
            wine.backLabelImageData = backLabelImageData
            wine.drinkFrom = Int64(max(0, drinkFrom))
            wine.drinkTo = Int64(max(0, drinkTo))
            wine.drinkWindowFromLabel = drinkWindowFromLabel
        }
        context.saveChanges()
    }
}
