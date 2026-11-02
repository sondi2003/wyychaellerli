import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels

/// Der Wein-Berater mit einem lokalen Modell: Apple Intelligence auf dem Gerät oder
/// Apples Private Cloud. Kein Key, kein fremder Anbieter.
///
/// - **Auf dem Gerät** gehen nur die zwölf aussichtsreichsten Flaschen ans Modell
///   (`InventoryShortlist`) und eine verkürzte Anweisung – der Kontext ist klein.
/// - **In der Private Cloud** (32000 Token) geht der ganze Keller mit der ausführlichen
///   Anweisung, genau wie zu einer externen KI.
///
/// Die Antwort läuft durch denselben `PairingValidator` wie bei den externen Anbietern:
/// unbekannte Weine und Platzhalter fliegen raus, bei Bedarf folgt ein zweiter Versuch.
@available(iOS 26.0, *)
enum LocalSommelier {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "LocalSommelier")

    static func recommend(
        _ request: PairingRequest,
        source: LocalAISource,
        language: AppLanguage,
        speed: AISpeed = .quality
    ) async throws -> PairingResponse {
        // Grosser Keller auf dem Gerät: Vorauswahl, damit das Inventar hineinpasst.
        let inventory = source == .onDevice
            ? InventoryShortlist.select(from: request.inventory, dish: request.dish)
            : request.inventory
        let scoped = PairingRequest(
            dish: request.dish,
            inventory: inventory,
            maxRecommendations: request.maxRecommendations,
            guests: request.guests
        )

        let instructions = source == .onDevice
            ? PromptBuilder.compactSystemPrompt(maxRecommendations: scoped.maxRecommendations, language: language)
            : PromptBuilder.systemPrompt(maxRecommendations: scoped.maxRecommendations, language: language)

        let maxAttempts = speed == .fast ? 1 : 2
        var repairHint: String?
        for attempt in 1...maxAttempts {
            // Eine frische Sitzung je Versuch: Ein zweiter Versuch soll nicht am Verlauf des ersten hängen.
            guard let session = LocalAI.session(for: source, instructions: instructions) else {
                throw LocalAIError.sourceMissing
            }
            let prompt = PromptBuilder.userPrompt(for: scoped, repairHint: repairHint)
            let generated = try await session.respond(to: prompt, generating: GeneratedPairing.self).content
            let raw = generated.asResponse()
            switch PairingValidator.validate(raw, inventory: inventory) {
            case .usable(let response):
                if attempt > 1 { logger.info("Empfehlung im 2. Versuch brauchbar (\(source.displayName))") }
                return response
            case .unusable(let reason):
                logger.warning("Unbrauchbare Empfehlung von \(source.displayName) (Versuch \(attempt)): \(reason)")
                repairHint = PromptBuilder.repairHint
            }
        }
        throw AIServiceError.unusableResponse
    }
}

// MARK: - Zielstruktur

/// Spiegel von `PairingResponse` für das Foundation-Models-Framework.
@available(iOS 26.0, *)
@Generable
struct GeneratedPairing {
    @Guide(description: "Bis zu drei Empfehlungen aus dem Inventar, beste zuerst. Leer, wenn keine Flasche mindestens acceptable passt.")
    var recommendations: [GeneratedRecommendation]

    @Guide(description: "Allgemeiner Hinweis zur Auswahl, höchstens 2 Sätze, in der Antwortsprache.")
    var generalNote: String

    @Guide(description: "true, wenn keine Flasche im Keller mindestens acceptable passt.")
    var noGoodMatch: Bool

    @Guide(description: "Was klassisch zu diesem Gericht passen würde (Rebsorte, Stil, Region) als Kauftipp, höchstens 2 Sätze. Immer ausfüllen.")
    var shoppingTip: String

    func asResponse() -> PairingResponse {
        PairingResponse(
            recommendations: recommendations.map(\.asRecommendation),
            generalNote: generalNote,
            noGoodMatch: noGoodMatch,
            shoppingTip: shoppingTip
        )
    }
}

@available(iOS 26.0, *)
@Generable
struct GeneratedRecommendation {
    @Guide(description: "1 = beste Empfehlung, 2 = zweitbeste, usw. Jeder Rang nur einmal.")
    var rank: Int

    @Guide(description: "Exakter Name des Weins aus dem Inventar (Feld name).")
    var wineName: String

    @Guide(description: "Jahrgang des Weins aus dem Inventar (Feld vintage).")
    var vintage: Int

    @Guide(description: "Ehrliche Passung.", .anyOf(["excellent", "good", "acceptable", "poor"]))
    var fit: String

    @Guide(description: "Konkrete Begründung, höchstens 3 Sätze, in der Antwortsprache.")
    var reasoning: String

    @Guide(description: "Kurzer Serviertipp in einem Satz (Temperatur, Dekantieren, Glas).")
    var servingTip: String

    var asRecommendation: PairingRecommendation {
        PairingRecommendation(
            rank: rank,
            wineName: wineName,
            vintage: vintage,
            fit: FitLevel(rawValue: fit) ?? .acceptable,
            reasoning: reasoning,
            servingTip: servingTip
        )
    }
}
#endif
