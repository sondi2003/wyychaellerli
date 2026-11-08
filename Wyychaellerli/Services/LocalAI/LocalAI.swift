import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wo eine lokale KI-Anfrage laufen kann – beides ohne API-Key und ohne fremden Anbieter.
enum LocalAISource: Sendable, Hashable {
    /// Das Modell von Apple Intelligence auf dem Gerät. Nichts verlässt das Telefon.
    /// Kleiner Kontext (rund 4000 Token), aber kostenlos und offline.
    case onDevice
    /// Apples Private Cloud Compute (ab iOS 27): grösseres Modell, 32000 Token Kontext.
    /// Läuft auf Apples Servern, die Anfrage wird dort nicht gespeichert und ist für Apple
    /// nicht lesbar. Braucht Netz, aber keinen Key.
    case privateCloud

    var displayName: String {
        switch self {
        case .onDevice:     return tr("Apple Intelligence (auf dem Gerät)")
        case .privateCloud: return tr("Apple Private Cloud")
        }
    }

    var shortName: String {
        switch self {
        case .onDevice:     return tr("Auf dem Gerät")
        case .privateCloud: return tr("Private Cloud")
        }
    }

    var symbolName: String {
        switch self {
        case .onDevice:     return "iphone"
        case .privateCloud: return "lock.icloud"
        }
    }

    /// Wie viel Text ein Modell ungefähr verträgt (Zeichen, nicht Token). Das Gerät hat
    /// rund 4000 Token für Anweisung, Eingabe und Antwort zusammen.
    var comfortableInputCharacters: Int {
        switch self {
        case .onDevice:     return 20_000
        case .privateCloud: return 60_000
        }
    }
}

/// Fragt ab, welche lokalen Modelle gerade zur Verfügung stehen.
enum LocalAI {

    /// Die nutzbaren Quellen in der Reihenfolge, in der sie probiert werden:
    /// erst auf dem Gerät (nichts geht hinaus), dann Apples Private Cloud.
    ///
    /// Nutzbar heisst: das Modell ist bereit **und** versteht die gewählte Sprache.
    /// Serbisch zum Beispiel kennt das Modell auf dem Gerät nicht – dann fällt es hier
    /// heraus, statt eine deutsche Antwort in einer serbischen App zu liefern.
    static func usableSources(for language: AppLanguage) async -> [LocalAISource] {
        #if canImport(FoundationModels)
        var result: [LocalAISource] = []
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable, model.supportsLocale(language.locale) {
                result.append(.onDevice)
            }
        }
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            if model.isAvailable, (try? await model.supportsLocale(language.locale)) == true {
                result.append(.privateCloud)
            }
        }
        return result
        #else
        return []
        #endif
    }

    #if canImport(FoundationModels)
    /// Eine Sitzung für die gewählte Quelle. `nil`, wenn die Quelle auf diesem System fehlt.
    @available(iOS 26.0, *)
    static func session(for source: LocalAISource, instructions: String) -> LanguageModelSession? {
        switch source {
        case .onDevice:
            return LanguageModelSession(instructions: instructions)
        case .privateCloud:
            if #available(iOS 27.0, *) {
                return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            }
            return nil
        }
    }
    #endif
}

/// Der Stand der lokalen Modelle für die Oberfläche: Welche Quelle ist aktiv, gibt es keine?
/// Wird beim Start und bei einem Sprachwechsel neu abgefragt.
@Observable
@MainActor
final class LocalAIStatus {

    private(set) var sources: [LocalAISource] = []
    private(set) var hasChecked = false

    /// Die Quelle, die als Erste drankommt.
    var primary: LocalAISource? { sources.first }

    func refresh() async {
        sources = await LocalAI.usableSources(for: AppLanguage.current)
        hasChecked = true
    }
}
