import CryptoKit
import Foundation

/// Ein Eintrag im gemeinsamen Katalog (öffentliche CloudKit-Datenbank).
///
/// Bewusst ein reiner Werttyp ohne CloudKit, damit Schlüssel, Suchwörter und Abgleich
/// ohne Netz testbar sind. Die Umwandlung von und nach `CKRecord` steht in `CatalogStore`.
struct CatalogWine: Sendable, Equatable, Identifiable, Codable {
    /// Der Datensatzname, zugleich der Schlüssel gegen Doppeleinträge.
    var id: String
    var name: String
    var producer: String
    var vintage: Int
    var grape: String
    var region: String
    var country: String
    var typeRaw: String
    var alcoholPercent: Double
    /// Herkunft: `nutzer`, `admin` oder später eine externe Quelle.
    var source: String
    var sourceID: String = ""
    /// Von Richard bearbeitet – ein späterer Import darf den Eintrag nicht überschreiben.
    var adminEdited: Bool = false
    /// Bekannte Strichcodes (EAN-13/8) dieses Weins. Eine Liste, weil derselbe Wein oft
    /// mehrere trägt (Flaschengrössen, Verpackungen). Suchmerkmal, kein Schlüssel.
    var gtins: [String] = []

    var wineType: WineType? { WineType(rawValue: typeRaw) }

    /// Was dieser Eintrag dem bestehenden **hinzufügt**, als Feldnamen für die Anzeige –
    /// oder `nil`, wenn er etwas Vorhandenes ändert (dann ist es keine Ergänzung, sondern
    /// ein Überschreiben). Eine leere Liste heisst: nichts Neues.
    func additions(over existing: CatalogWine) -> [String]? {
        guard name == existing.name, vintage == existing.vintage, typeRaw == existing.typeRaw else { return nil }
        var added: [String] = []
        for (label, old, new) in [
            (tr("Produzent"), existing.producer, producer),
            (tr("Rebsorte"), existing.grape, grape),
            (tr("Region"), existing.region, region),
            (tr("Land"), existing.country, country)
        ] where new != old {
            guard old.isEmpty else { return nil }
            added.append(label)
        }
        if alcoholPercent != existing.alcoholPercent {
            guard existing.alcoholPercent == 0 else { return nil }
            added.append(tr("Alkohol"))
        }
        guard existing.gtins.allSatisfy(gtins.contains) else { return nil }
        if !gtins.allSatisfy(existing.gtins.contains) { added.append(tr("Strichcode")) }
        return added
    }

    /// Füllt leere Felder aus einem weiteren Vorschlag zum selben Wein.
    mutating func fillEmptyFields(from other: CatalogWine) {
        if producer.isEmpty { producer = other.producer }
        if grape.isEmpty { grape = other.grape }
        if region.isEmpty { region = other.region }
        if country.isEmpty { country = other.country }
        if alcoholPercent == 0 { alcoholPercent = other.alcoholPercent }
    }

    var candidate: DuplicateFinder.Candidate {
        DuplicateFinder.Candidate(name: name, producer: producer, vintage: vintage)
    }
}

/// Status eines Vorschlags. Der Rohwert steht so in CloudKit und in den Abos.
enum SubmissionStatus: String, Sendable, Codable {
    case pending
    case accepted
    case rejected

    var title: String {
        switch self {
        case .pending:  return tr("Wartet auf Prüfung")
        case .accepted: return tr("Aufgenommen")
        case .rejected: return tr("Abgelehnt")
        }
    }

    var symbolName: String {
        switch self {
        case .pending:  return "hourglass"
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal"
        }
    }
}

/// Ein Vorschlag eines Nutzers.
///
/// Trägt **nur Stammdaten** und das zugeschnittene Vorderseiten-Etikett. Notizen,
/// Bewertungen, Bestand und Regal bleiben privat – das sagt auch der Text beim Senden.
struct CatalogSubmission: Sendable, Identifiable {
    var id: String
    var name: String
    var producer: String
    var vintage: Int
    var grape: String
    var region: String
    var country: String
    var typeRaw: String
    var alcoholPercent: Double
    var catalogKey: String
    var wineUUID: String
    var status: SubmissionStatus
    var createdAt: Date?
    /// Lokale Kopie des Etiketts, solange der Datensatz geladen ist.
    var labelImageData: Data?
    /// Strichcode des vorgeschlagenen Weins oder leer.
    var barcode: String = ""

    /// Als Katalogeintrag vorbereitet – Ausgangspunkt für die Prüfung im Admin-Bereich.
    var asCatalogWine: CatalogWine {
        CatalogWine(
            id: catalogKey,
            name: name,
            producer: producer,
            vintage: vintage,
            grape: grape,
            region: region,
            country: country,
            typeRaw: typeRaw,
            alcoholPercent: alcoholPercent,
            source: "nutzer",
            gtins: barcode.isEmpty ? [] : [barcode]
        )
    }
}

/// Die Daten, die beim Vorschlagen das Gerät verlassen.
struct SubmissionDraft: Sendable {
    var name: String
    var producer: String
    var vintage: Int
    var grape: String
    var region: String
    var country: String
    var typeRaw: String
    var alcoholPercent: Double
    var wineUUID: String
    var labelImageData: Data?
    var barcode: String = ""
    /// Schlüssel des Katalogeintrags, den dieser Vorschlag nur **ergänzt** (neuer
    /// Strichcode zu einem Wein, den es schon gibt). Leer bei einem neuen Wein.
    var targetKey: String = ""

    var catalogKey: String {
        targetKey.isEmpty ? CatalogKey.make(producer: producer, name: name, vintage: vintage) : targetKey
    }

    /// Ein Vorschlag, der dem bestehenden Eintrag nur einen Strichcode hinzufügt. Trägt
    /// dessen Angaben, damit das Aufnehmen nichts verändert – und kein Etikett, damit das
    /// vorhandene bleibt.
    init(adding barcode: String, to entry: CatalogWine, wineUUID: String) {
        self.init(
            name: entry.name, producer: entry.producer, vintage: entry.vintage, grape: entry.grape,
            region: entry.region, country: entry.country, typeRaw: entry.typeRaw,
            alcoholPercent: entry.alcoholPercent, wineUUID: wineUUID, labelImageData: nil,
            barcode: barcode, targetKey: entry.id
        )
    }

    /// Die Angaben, die ein Wein dem bestehenden Eintrag **hinzufügt**: Felder, die im
    /// Eintrag leer sind und die der Wein kennt, ein Strichcode, den der Eintrag noch nicht
    /// trägt, und das Etikettfoto, falls der Eintrag keines hat. `nil`, wenn nichts Neues
    /// dabei ist. Vorhandenes wird nie angefasst; Name, Jahrgang und Weinart ebenso wenig,
    /// denn der Jahrgang steckt im Schlüssel.
    init?(
        supplementing entry: CatalogWine, producer: String, grape: String, region: String,
        country: String, alcoholPercent: Double, barcode: String, labelImageData: Data?,
        entryHasImage: Bool, wineUUID: String
    ) {
        func fill(_ existing: String, _ new: String) -> String {
            existing.isEmpty ? new.trimmingCharacters(in: .whitespacesAndNewlines) : existing
        }
        let newBarcode = barcode.isEmpty || entry.gtins.contains(barcode) ? "" : barcode
        let newImage = entryHasImage ? nil : labelImageData
        let filled = (
            producer: fill(entry.producer, producer), grape: fill(entry.grape, grape),
            region: fill(entry.region, region), country: fill(entry.country, country),
            alcohol: entry.alcoholPercent > 0 ? entry.alcoholPercent : max(0, alcoholPercent)
        )
        let addsFields = filled.producer != entry.producer || filled.grape != entry.grape
            || filled.region != entry.region || filled.country != entry.country
            || filled.alcohol != entry.alcoholPercent
        guard addsFields || !newBarcode.isEmpty || newImage != nil else { return nil }
        self.init(
            name: entry.name, producer: filled.producer, vintage: entry.vintage, grape: filled.grape,
            region: filled.region, country: filled.country, typeRaw: entry.typeRaw,
            alcoholPercent: filled.alcohol, wineUUID: wineUUID, labelImageData: newImage,
            barcode: newBarcode, targetKey: entry.id
        )
    }

    init(
        name: String, producer: String, vintage: Int, grape: String, region: String,
        country: String, typeRaw: String, alcoholPercent: Double, wineUUID: String,
        labelImageData: Data?, barcode: String = "", targetKey: String = ""
    ) {
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.grape = grape
        self.region = region
        self.country = country
        self.typeRaw = typeRaw
        self.alcoholPercent = alcoholPercent
        self.wineUUID = wineUUID
        self.labelImageData = labelImageData
        self.barcode = barcode
        self.targetKey = targetKey
    }
}

// MARK: - Schlüssel und Suchwörter

/// Schlüssel und Suchwörter für den Katalog.
///
/// Der Schlüssel verhindert Doppeleinträge **im Katalog** und fasst gleiche Vorschläge
/// zusammen. Für den Abgleich mit einem Scan taugt er allein nicht: Ein fehlender Akzent
/// oder ein weggelassenes „Domaine“ ergäbe einen anderen Wert. Dafür gibt es die
/// Suchwörter plus die Ähnlichkeitsregel aus `DuplicateFinder`.
enum CatalogKey {

    /// `ean_<ziffern>` bei übergebenem Strichcode, sonst `wine_<md5>` aus Produzent, Name
    /// und Jahrgang, je ohne Akzente, Satz- und Leerzeichen.
    ///
    /// **Die App übergibt nie einen Strichcode.** Derselbe Code kann über mehrere Jahrgänge
    /// gleich bleiben, der Schlüssel muss aber je Jahrgang verschieden sein. Der Strichcode
    /// ist ein Suchmerkmal (`CatalogWine.gtins`). Der Parameter ist für einen späteren
    /// Import aus einer externen Quelle gedacht, die genau eine Flasche je Code liefert.
    static func make(gtin: String = "", producer: String, name: String, vintage: Int) -> String {
        let digits = gtin.filter(\.isNumber)
        if digits.count >= 8 { return "ean_\(digits)" }
        let basis = [
            DuplicateFinder.normalized(producer),
            DuplicateFinder.normalized(name),
            String(max(0, vintage))
        ].joined(separator: "_")
        let digest = Insecure.MD5.hash(data: Data(basis.utf8))
        return "wine_" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Wörter, über die CloudKit Kandidaten findet: kleingeschrieben, ohne Akzente,
    /// mindestens drei Buchstaben, ohne Füllwörter wie „Domaine“ oder „Weingut“.
    static func tokens(name: String, producer: String) -> [String] {
        let words = (producer + " " + name)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !fillers.contains($0) && !$0.allSatisfy(\.isNumber) }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    /// Das aussagekräftigste Suchwort: das längste aus dem Produzenten, sonst aus dem Namen.
    /// Lange Wörter sind seltener und liefern weniger, aber passendere Kandidaten.
    static func searchToken(name: String, producer: String) -> String? {
        let fromProducer = tokens(name: "", producer: producer)
        let pool = fromProducer.isEmpty ? tokens(name: name, producer: "") : fromProducer
        return pool.max { $0.count < $1.count }
    }

    /// Wörter, die auf fast jedem Etikett stehen und deshalb nichts unterscheiden.
    private static let fillers: Set<String> = [
        "domaine", "chateau", "weingut", "cantina", "cantine", "bodega", "bodegas",
        "tenuta", "azienda", "agricola", "cave", "caves", "maison", "winery", "estate",
        "vin", "vino", "wein", "wine", "rouge", "rosso", "rotwein", "blanc", "bianco",
        "weisswein", "the", "les", "del", "della", "von", "und"
    ]
}

// MARK: - Abgleich

enum CatalogMatcher {

    /// Der passendste Katalogeintrag nach der Regel der Doppelerkennung, oder `nil`.
    ///
    /// Dieselbe Regel wie im eigenen Keller: gleicher Jahrgang (wenn beide bekannt),
    /// Name ab 0,85, Produzent ab 0,6 – so trifft „La Pinede“ den „La Pinède“, aber
    /// „Barolo Riserva“ nicht den „Barolo“.
    static func bestMatch(for candidate: DuplicateFinder.Candidate, in entries: [CatalogWine]) -> CatalogWine? {
        entries
            .compactMap { entry -> (CatalogWine, Double)? in
                guard let score = DuplicateFinder.similarity(candidate, entry.candidate) else { return nil }
                return (entry, score)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Der Eintrag zu einem Strichcode – **mit dem Jahrgang als Entscheider**.
    ///
    /// Derselbe Code gehört oft zu mehreren Jahrgängen. Ist der Jahrgang bekannt, zählt
    /// nur der gleiche; ein Eintrag ohne Jahrgang springt ein, wenn es keinen gleichen
    /// gibt. Ist er unbekannt, gilt nur ein **eindeutiger** Treffer – bei mehreren
    /// Jahrgängen zu raten hiesse, einen Jahrgang zu erfinden.
    static func match(barcode: String, vintage: Int, in entries: [CatalogWine]) -> CatalogWine? {
        guard !barcode.isEmpty else { return nil }
        let hits = entries.filter { $0.gtins.contains(barcode) }
        guard !hits.isEmpty else { return nil }
        if vintage > 0 {
            return hits.first { $0.vintage == vintage } ?? hits.first { $0.vintage == 0 }
        }
        return hits.count == 1 ? hits[0] : nil
    }
}
