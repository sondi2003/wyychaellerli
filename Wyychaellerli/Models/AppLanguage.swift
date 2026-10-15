import Foundation

/// Sprache der App: dem System folgen oder fest Deutsch bzw. Serbisch (lateinische Schrift).
///
/// Bewusst in `UserDefaults`: Es ist eine Geräte-Einstellung, wie das Erscheinungsbild.
/// Die Quellsprache der Texte ist Deutsch; die Übersetzung liegt in `Localizable.xcstrings`.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    case system
    case german
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
        case .serbian: return "Srpski"
        }
    }

    /// Sprachkennung der `.lproj`-Ordner. Bei „System“ wird aufgelöst, was das Gerät spricht.
    var resolvedIdentifier: String {
        switch self {
        case .german:  return "de"
        case .serbian: return "sr-Latn"
        case .system:
            let first = Locale.preferredLanguages.first ?? "de"
            return first.hasPrefix("sr") ? "sr-Latn" : "de"
        }
    }

    var isSerbian: Bool { resolvedIdentifier == "sr-Latn" }

    var locale: Locale { Locale(identifier: resolvedIdentifier) }

    // MARK: Für die Prompts an die KI
    //
    // Die Prompts selbst bleiben deutsch; nur die verlangte Antwortsprache wechselt.

    /// „Antworte auf …“
    var promptName: String {
        isSerbian ? "Serbisch (lateinische Schrift, ekavisch)" : "Deutsch"
    }

    /// „Übersetze ins …“
    var promptTarget: String {
        isSerbian ? "Serbische (lateinische Schrift, ekavisch)" : "Deutsche"
    }

    /// Länderbeispiele im Etikett-Prompt, damit das Modell die Schreibweise der Sprache trifft.
    var promptCountryExamples: String {
        isSerbian ? "\"Francuska\", \"Nemačka\", \"Italija\"" : "\"Frankreich\", \"Deutschland\", \"Italien\""
    }

    /// Speisebeispiele im Etikett-Prompt.
    var promptFoodExamples: String {
        isSerbian ? "[\"Meso sa roštilja\", \"Tvrdi sir\"]" : "[\"Gegrilltes Fleisch\", \"Hartkäse\"]"
    }

    var isGerman: Bool { !isSerbian }

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
