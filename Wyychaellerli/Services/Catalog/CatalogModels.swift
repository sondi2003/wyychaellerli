import CryptoKit
import Foundation

/// Ein Eintrag im gemeinsamen Katalog (öffentliche CloudKit-Datenbank).
///
/// Bewusst ein reiner Werttyp ohne CloudKit, damit Schlüssel, Suchwörter und Abgleich
/// ohne Netz testbar sind. Die Umwandlung von und nach `CKRecord` steht in `CatalogStore`.
struct CatalogWine: Sendable, Equatable, Identifiable {
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

    var wineType: WineType? { WineType(rawValue: typeRaw) }

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
            source: "nutzer"
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

    var catalogKey: String {
        CatalogKey.make(producer: producer, name: name, vintage: vintage)
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

    /// `ean_<ziffern>` bei bekanntem Strichcode, sonst `wine_<md5>` aus Produzent, Name
    /// und Jahrgang, je ohne Akzente, Satz- und Leerzeichen.
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
}
