import Foundation

/// Sprache der App: dem System folgen oder fest Deutsch, Englisch, Französisch, Italienisch oder Serbisch (lateinische Schrift).
///
/// Bewusst in `UserDefaults`: Es ist eine Geräte-Einstellung, wie das Erscheinungsbild.
/// Die Quellsprache der Texte ist Deutsch; die Übersetzung liegt in `Localizable.xcstrings`.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    case system
    case german
    /// Englisch ohne regionale Färbung: Kennung „en“, nicht „en-US“ oder „en-GB“.
    case english
    /// Französisch ohne regionale Färbung: Kennung „fr“, nicht „fr-CH“ oder „fr-FR“.
    case french
    /// Italienisch ohne regionale Färbung: Kennung „it“, nicht „it-CH“ oder „it-IT“.
    case italian
    case serbian

    /// Schlüssel für `@AppStorage`, an einer Stelle definiert.
    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// Name der Sprache in ihrer eigenen Sprache – so findet man sie, auch wenn die App
    /// gerade in einer unverständlichen Sprache läuft. Nur „System“ wird übersetzt.
    var title: String {
        switch self {
        case .system:  return tr("System")
        case .german:  return "Deutsch"
        case .english: return "English"
        case .french:  return "Français"
        case .italian: return "Italiano"
        case .serbian: return "Srpski"
        }
    }

    /// Sprachkennung der `.lproj`-Ordner. Bei „System“ wird aufgelöst, was das Gerät spricht.
    var resolvedIdentifier: String {
        switch self {
        case .german:  return "de"
        case .english: return "en"
        case .french:  return "fr"
        case .italian: return "it"
        case .serbian: return "sr-Latn"
        case .system:
            return Self.identifier(forPreferred: Locale.preferredLanguages.first)
        }
    }

    /// Welche Sprache der App zu einer Gerätesprache gehört. Regionen zählen nicht: „en-CH“,
    /// „en-GB“ und „en-US“ ergeben alle „en“. Alles Unbekannte fällt auf Deutsch zurück.
    static func identifier(forPreferred preferred: String?) -> String {
        let code = (preferred ?? "de").lowercased()
        if code.hasPrefix("sr") { return "sr-Latn" }
        if code.hasPrefix("en") { return "en" }
        if code.hasPrefix("fr") { return "fr" }
        if code.hasPrefix("it") { return "it" }
        return "de"
    }

    var isSerbian: Bool { resolvedIdentifier == "sr-Latn" }
    var isEnglish: Bool { resolvedIdentifier == "en" }
    var isFrench: Bool { resolvedIdentifier == "fr" }
    var isItalian: Bool { resolvedIdentifier == "it" }

    var locale: Locale { Locale(identifier: resolvedIdentifier) }

    // MARK: Für die Prompts an die KI
    //
    // Die Prompts selbst bleiben deutsch; nur die verlangte Antwortsprache wechselt.

    /// „Antworte auf …“
    var promptName: String {
        switch resolvedIdentifier {
        case "sr-Latn": return "Serbisch (lateinische Schrift, ekavisch)"
        case "en":      return "Englisch (neutral, ohne regionale Eigenheiten)"
        case "fr":      return "Französisch (neutral, ohne regionale Eigenheiten)"
        case "it":      return "Italienisch (neutral, ohne regionale Eigenheiten)"
        default:        return "Deutsch"
        }
    }

    /// „Übersetze ins …“
    var promptTarget: String {
        switch resolvedIdentifier {
        case "sr-Latn": return "Serbische (lateinische Schrift, ekavisch)"
        case "en":      return "Englische (neutral, ohne regionale Eigenheiten)"
        case "fr":      return "Französische (neutral, ohne regionale Eigenheiten)"
        case "it":      return "Italienische (neutral, ohne regionale Eigenheiten)"
        default:        return "Deutsche"
        }
    }

    /// Länderbeispiele im Etikett-Prompt, damit das Modell die Schreibweise der Sprache trifft.
    var promptCountryExamples: String {
        switch resolvedIdentifier {
        case "sr-Latn": return "\"Francuska\", \"Nemačka\", \"Italija\""
        case "en":      return "\"France\", \"Germany\", \"Italy\""
        case "fr":      return "\"France\", \"Allemagne\", \"Italie\""
        case "it":      return "\"Francia\", \"Germania\", \"Italia\""
        default:        return "\"Frankreich\", \"Deutschland\", \"Italien\""
        }
    }

    /// Speisebeispiele im Etikett-Prompt.
    var promptFoodExamples: String {
        switch resolvedIdentifier {
        case "sr-Latn": return "[\"Meso sa roštilja\", \"Tvrdi sir\"]"
        case "en":      return "[\"Grilled meat\", \"Hard cheese\"]"
        case "fr":      return "[\"Viande grillée\", \"Fromage à pâte dure\"]"
        case "it":      return "[\"Carne alla griglia\", \"Formaggio stagionato\"]"
        default:        return "[\"Gegrilltes Fleisch\", \"Hartkäse\"]"
        }
    }

    /// Beispiele für Fachbegriffe im Übersetzungs-Prompt: „schistes“ und „élevage en fût“.
    var promptTermExamples: (schist: String, barrelAging: String) {
        switch resolvedIdentifier {
        case "sr-Latn": return ("škriljac", "odležavanje u buretu")
        case "en":      return ("schist", "barrel aging")
        case "fr":      return ("schiste", "élevage en fût")
        case "it":      return ("scisto", "affinamento in botte")
        default:        return ("Schiefer", "Ausbau im Fass")
        }
    }

    var isGerman: Bool { resolvedIdentifier == "de" }

    /// Die gewählte Sprache dieses Geräts.
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }
}

/// Übersetzt einen Text ausserhalb von SwiftUI-Ansichten (Fehlermeldungen, berechnete
/// Namen, Siri). Ansichten brauchen das nicht: `Text("…")` löst über die Umgebung auf.
///
/// Beim Aufruf mit Interpolation (`tr("\(count) Flaschen")`) wird der Schlüssel samt
/// Platzhalter automatisch in den Katalog aufgenommen.
func tr(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = AppLanguage.current.locale
    return String(localized: resource)
}

/// „Flasche“ bzw. „Flaschen“ ohne Zahl, in der richtigen Pluralform der App-Sprache.
/// Für Stellen, an denen die Zahl gross daneben steht.
func bottleWord(_ count: Int) -> String {
    String(tr("\(count) Flaschen").drop { $0.isNumber || $0.isWhitespace })
}

extension Date {
    /// „17. Sept. 2026“ – im Format der App-Sprache, nicht der Region des Geräts.
    var appShortDate: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.current.locale))
    }
}
