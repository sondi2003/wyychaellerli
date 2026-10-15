import CoreData
import Foundation

/// Die Bewertung **einer Person** zu **einem Wein**.
///
/// Bewusst ein eigenes Objekt und nicht ein paar Felder am Wein: Beide Seiten eines
/// geteilten Kellers bewerten unabhängig voneinander, oft auf verschiedenen Geräten und
/// zu verschiedenen Zeiten. Als Felder am Wein würde die zweite Bewertung die erste
/// überschreiben, sobald CloudKit die Änderungen zusammenführt.
///
/// Bewertet wird der Wein, nicht die einzelne Flasche: Jeder Eintrag im Keller ist ohnehin
/// ein bestimmter Wein mit bestimmtem Jahrgang.
@objc(RatingEntity)
final class Rating: NSManagedObject, Identifiable {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Rating> {
        NSFetchRequest<Rating>(entityName: "Rating")
    }

    @NSManaged var uuid: UUID?
    /// Stabile Kennung der Apple-ID (CloudKit-Benutzerdatensatz). Trennt die Personen
    /// zuverlässig, auch wenn beide denselben Anzeigenamen wählen.
    @NSManaged var raterID: String
    /// Anzeigename, den die Person selbst eingetragen hat.
    @NSManaged var raterName: String
    /// 0,5 bis 5,0 in halben Schritten. 0 heisst „noch nicht bewertet“.
    @NSManaged var stars: Double
    @NSManaged var note: String
    @NSManaged var updatedAt: Date?
    @NSManaged var wine: Wine?

    @NSManaged private var tagsRaw: String

    var id: NSManagedObjectID { objectID }

    /// Angetippte Gründe, intern als eine Zeile pro Eintrag.
    var tags: [String] {
        get {
            tagsRaw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { tagsRaw = newValue.joined(separator: "\n") }
    }

    /// Name für die Anzeige; fällt auf etwas Neutrales zurück, wenn keiner gesetzt ist.
    var displayName: String {
        raterName.isEmpty ? tr("Ohne Namen") : raterName
    }

    /// Legt eine Bewertung an und hängt sie an den Wein.
    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        wine: Wine,
        raterID: String,
        raterName: String
    ) -> Rating {
        let rating = Rating(context: context)
        // Muss in denselben Speicher wie der Wein, sonst sieht die andere Seite sie nie.
        if let store = wine.objectID.persistentStore {
            context.assign(rating, to: store)
        }
        rating.uuid = UUID()
        rating.wine = wine
        rating.raterID = raterID
        rating.raterName = raterName
        rating.stars = 0
        rating.note = ""
        rating.tags = []
        rating.updatedAt = .now
        return rating
    }
}

// MARK: - Gründe zum Antippen

/// Kurze Gründe in Alltagssprache – bewusst keine Sommelier-Skalen.
///
/// Unterbewertungen für Säure, Tannin und Körper würden ein Fachurteil verlangen, das
/// hier niemand abgeben will. Diese Begriffe treffen das, was beim Trinken tatsächlich
/// auffällt, und kosten einen Fingertipp.
enum RatingTag: String, CaseIterable, Identifiable {

    // Lob – gleich viele wie Kritik, sonst lädt die Auswahl nur zum Nörgeln ein.
    case wantAgain = "Gerne wieder"
    case balanced = "Harmonisch"
    case fruity = "Fruchtig"
    case fresh = "Schön frisch"
    case easy = "Süffig"
    case velvety = "Samtig"
    case bold = "Kräftig"
    case longFinish = "Langer Abgang"

    // Kritik
    case tooSour = "Zu sauer"
    case tooTannic = "Zu herb"
    case tooSweet = "Zu süss"
    case weakAroma = "Wenig Aroma"
    case oddAroma = "Aroma passt nicht"
    case tooHeavy = "Zu schwer"
    case tooThin = "Zu dünn"
    case corked = "Korkig"

    var id: String { rawValue }

    /// Anzeigetext in der App-Sprache. Gespeichert wird weiter der deutsche `rawValue`,
    /// damit Bewertungen auf allen Geräten dieselbe Kennung tragen, egal welche Sprache läuft.
    var title: String {
        switch self {
        case .wantAgain:  return tr("Gerne wieder")
        case .balanced:   return tr("Harmonisch")
        case .fruity:     return tr("Fruchtig")
        case .fresh:      return tr("Schön frisch")
        case .easy:       return tr("Süffig")
        case .velvety:    return tr("Samtig")
        case .bold:       return tr("Kräftig")
        case .longFinish: return tr("Langer Abgang")
        case .tooSour:    return tr("Zu sauer")
        case .tooTannic:  return tr("Zu herb")
        case .tooSweet:   return tr("Zu süss")
        case .weakAroma:  return tr("Wenig Aroma")
        case .oddAroma:   return tr("Aroma passt nicht")
        case .tooHeavy:   return tr("Zu schwer")
        case .tooThin:    return tr("Zu dünn")
        case .corked:     return tr("Korkig")
        }
    }

    /// Übersetzt einen gespeicherten Rohwert; Unbekanntes bleibt, wie es ist.
    static func title(forStored stored: String) -> String {
        RatingTag(rawValue: stored)?.title ?? stored
    }

    /// `true` bei einem Lob – für Gruppierung und Farbe.
    var isPositive: Bool {
        switch self {
        case .wantAgain, .balanced, .fruity, .fresh, .easy, .velvety, .bold, .longFinish: return true
        case .tooSour, .tooTannic, .tooSweet, .weakAroma, .oddAroma, .tooHeavy, .tooThin, .corked: return false
        }
    }

    static var positives: [RatingTag] { allCases.filter(\.isPositive) }
    static var negatives: [RatingTag] { allCases.filter { !$0.isPositive } }
}
