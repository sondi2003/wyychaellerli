import Foundation
import Observation

/// Persistente Einstellungen für den KI-Layer.
///
/// - Modellnamen und bevorzugter Anbieter: `UserDefaults` (unkritisch).
/// - API-Keys: Keychain (siehe `KeychainStore`).
///
/// Aktiv ist automatisch der Anbieter, für den ein API-Key hinterlegt ist.
/// Sind mehrere Keys hinterlegt, entscheidet `preferredProvider` (wählbar in den Einstellungen).
///
/// Als `@Observable` kann die Klasse direkt in SwiftUI-Views eingebunden werden;
/// die Views aktualisieren sich, wenn sich Keys oder Modelle ändern.
@Observable
@MainActor
final class AISettings {

    private enum Keys {
        static let preferredProvider = "ai.preferredProvider"
        static let prefersExternal = "ai.prefersExternal"
        static func model(for provider: AIProvider) -> String { "ai.model.\(provider.rawValue)" }
        static func fastModel(for provider: AIProvider) -> String { "ai.fastModel.\(provider.rawValue)" }
    }

    private let defaults: UserDefaults

    /// Nur relevant, wenn mehr als ein Anbieter einen Key hat.
    var preferredProvider: AIProvider {
        didSet { defaults.set(preferredProvider.rawValue, forKey: Keys.preferredProvider) }
    }

    /// Wenn gesetzt, kommt die externe KI vor den lokalen Modellen dran. Standard ist das
    /// Gegenteil: Zuerst Apple (auf dem Gerät, dann Private Cloud), die externe KI nur als
    /// Rückfall – und nur, wenn überhaupt ein Key hinterlegt ist.
    var prefersExternal: Bool {
        didSet { defaults.set(prefersExternal, forKey: Keys.prefersExternal) }
    }

    /// Spiegel der Keychain, damit SwiftUI Änderungen mitbekommt.
    /// Die Keychain selbst ist nicht observierbar.
    private(set) var apiKeys: [AIProvider: String] = [:]

    /// Modellnamen pro Anbieter; leer = `provider.defaultModel`.
    private(set) var models: [AIProvider: String] = [:]

    /// Schnelle Modelle für Siri; leer = `provider.defaultFastModel`.
    private(set) var fastModels: [AIProvider: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.string(forKey: Keys.preferredProvider)
            .flatMap(AIProvider.init(rawValue:))
        self.preferredProvider = stored ?? .anthropic
        self.prefersExternal = defaults.bool(forKey: Keys.prefersExternal)

        for provider in AIProvider.allCases {
            apiKeys[provider] = KeychainStore.string(for: provider.rawValue) ?? ""
            models[provider] = defaults.string(forKey: Keys.model(for: provider)) ?? ""
            fastModels[provider] = defaults.string(forKey: Keys.fastModel(for: provider)) ?? ""
        }
    }

    // MARK: API-Keys

    func apiKey(for provider: AIProvider) -> String {
        apiKeys[provider] ?? ""
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    /// Speichert den Key in der Keychain. Ein leerer String löscht ihn.
    func setAPIKey(_ key: String, for provider: AIProvider) throws {
        try KeychainStore.set(key, for: provider.rawValue)
        apiKeys[provider] = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Modelle

    /// Das effektiv verwendete Modell (Nutzer-Eingabe oder Standard).
    func model(for provider: AIProvider) -> String {
        let custom = (models[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? provider.defaultModel : custom
    }

    /// Der rohe, vom Nutzer eingegebene Modellname (für das Textfeld in den Einstellungen).
    func customModel(for provider: AIProvider) -> String {
        models[provider] ?? ""
    }

    func setCustomModel(_ model: String, for provider: AIProvider) {
        models[provider] = model
        defaults.set(model, forKey: Keys.model(for: provider))
    }

    /// Das Modell für Siri-Anfragen (Nutzer-Eingabe oder Standard).
    func fastModel(for provider: AIProvider) -> String {
        let custom = (fastModels[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? provider.defaultFastModel : custom
    }

    func customFastModel(for provider: AIProvider) -> String {
        fastModels[provider] ?? ""
    }

    func setCustomFastModel(_ model: String, for provider: AIProvider) {
        fastModels[provider] = model
        defaults.set(model, forKey: Keys.fastModel(for: provider))
    }

    /// Modell passend zur gewünschten Geschwindigkeit.
    func model(for provider: AIProvider, speed: AISpeed) -> String {
        switch speed {
        case .quality: return model(for: provider)
        case .fast:    return fastModel(for: provider)
        }
    }

    // MARK: Aktiver Anbieter

    /// Alle Anbieter mit hinterlegtem Key, in der Reihenfolge von `AIProvider.allCases`.
    var configuredProviders: [AIProvider] {
        AIProvider.allCases.filter { hasAPIKey(for: $0) }
    }

    /// Der Anbieter, der für Anfragen verwendet wird – oder `nil`, wenn kein Key hinterlegt ist.
    ///
    /// Genau ein Key → dieser Anbieter. Mehrere Keys → `preferredProvider`, sofern er
    /// einen Key hat, sonst der erste konfigurierte.
    var activeProvider: AIProvider? {
        let configured = configuredProviders
        if configured.contains(preferredProvider) { return preferredProvider }
        return configured.first
    }

    /// Modell des aktiven Anbieters.
    var activeModel: String? {
        activeProvider.map { model(for: $0) }
    }

    /// Modell, das Siri verwenden würde.
    var activeFastModel: String? {
        activeProvider.map { fastModel(for: $0) }
    }

    /// `true`, wenn der Nutzer zwischen mehreren konfigurierten Anbietern wählen kann.
    var hasMultipleProviders: Bool {
        configuredProviders.count > 1
    }
}
