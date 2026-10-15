import SwiftUI

/// Wie die App aussehen soll: dem System folgen oder fest hell bzw. dunkel.
///
/// Bewusst in `UserDefaults` und nicht in der Keychain oder in Core Data: Es ist eine
/// Geräte-Einstellung. Wer am iPhone dunkel und am iPad hell will, soll das haben.
enum AppearanceSetting: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    /// Schlüssel für `@AppStorage`, an einer Stelle definiert.
    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return tr("System")
        case .light:  return tr("Hell")
        case .dark:   return tr("Dunkel")
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// `nil` bedeutet: nicht eingreifen, das System entscheidet.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
