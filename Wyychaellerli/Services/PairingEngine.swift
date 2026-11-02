import Foundation
import OSLog

/// Woher eine Empfehlung kam – für die Anzeige im Berater.
enum PairingSource: Sendable, Equatable {
    case local(LocalAISource)
    case external(AIProvider, model: String)

    var displayName: String {
        switch self {
        case .local(let source):      return source.displayName
        case .external(let provider, _): return provider.shortName
        }
    }

    var symbolName: String {
        switch self {
        case .local(let source):      return source.symbolName
        case .external(let provider, _): return provider.symbolName
        }
    }

    /// Kleingedrucktes für den Tooltip: Modellname bei einer externen KI.
    var detail: String {
        switch self {
        case .local:                       return ""
        case .external(_, let model):      return model
        }
    }
}

/// Wählt, wer die Empfehlung gibt – **lokal zuerst**.
///
/// Reihenfolge: Apple Intelligence auf dem Gerät → Apples Private Cloud (iOS 27) → externe
/// KI mit eigenem Key. Die externe KI ist **optional**: Ohne Key gibt es sie nicht, und mit
/// Key kommt sie nur als Rückfall dran – es sei denn, `prefersExternal` dreht die Reihenfolge.
/// Ein Fehler einer Stufe führt zur nächsten; erst wenn keine mehr übrig ist, sieht man ihn.
@MainActor
enum PairingEngine {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "PairingEngine")

    /// Ob es überhaupt jemanden gibt, den man fragen kann.
    static func hasAnySource(settings: AISettings, local: LocalAIStatus) -> Bool {
        !local.sources.isEmpty || settings.activeProvider != nil
    }

    static func recommend(
        _ request: PairingRequest,
        settings: AISettings,
        service: AIService,
        local: LocalAIStatus,
        speed: AISpeed = .quality
    ) async throws -> (PairingResponse, PairingSource) {
        guard !request.inventory.isEmpty else {
            return (
                PairingResponse(
                    recommendations: [],
                    generalNote: tr("Der Weinkeller ist leer. Lege zuerst Flaschen an, damit ich etwas empfehlen kann.")
                ),
                .local(.onDevice)
            )
        }

        var lastError: Error?
        let order: [PairingSource] = {
            let locals = local.sources.map(PairingSource.local)
            let external = settings.activeProvider.map { [PairingSource.external($0, model: settings.model(for: $0, speed: speed))] } ?? []
            return settings.prefersExternal ? external + locals : locals + external
        }()

        for source in order {
            do {
                switch source {
                case .local(let localSource):
                    #if canImport(FoundationModels)
                    guard #available(iOS 26.0, *) else { continue }
                    let response = try await LocalSommelier.recommend(
                        request,
                        source: localSource,
                        language: AppLanguage.current,
                        speed: speed
                    )
                    return (response, source)
                    #else
                    continue
                    #endif
                case .external(let provider, let model):
                    let response = try await service.recommend(
                        request,
                        provider: provider,
                        apiKey: settings.apiKey(for: provider),
                        model: model,
                        speed: speed
                    )
                    return (response, source)
                }
            } catch {
                logger.warning("\(source.displayName) hat nicht geklappt: \(String(describing: error)) – nächste Stufe")
                lastError = error
            }
        }
        if let lastError {
            // Ein Fehler des lokalen Modells ist kein Netzwerkfehler und soll auch nicht so heissen.
            if lastError is AIServiceError { throw lastError }
            throw AIServiceError.localFailed(lastError.localizedDescription)
        }
        throw AIServiceError.noProviderConfigured
    }
}
