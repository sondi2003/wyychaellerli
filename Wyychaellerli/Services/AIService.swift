import Foundation
import OSLog

// MARK: - Geschwindigkeit

/// Wie viel Zeit die Anfrage kosten darf.
/// `fast` wird für Siri verwendet: kleineres Modell, weniger Denkaufwand.
enum AISpeed: Sendable {
    case quality
    case fast
}

// MARK: - Provider-Schnittstelle

/// Ein Client pro Anbieter. Jeder Client kennt seinen Endpoint und sein Payload-Format
/// und liefert Text, der einem JSON-Schema folgt (Structured Output).
protocol AIProviderClient: Sendable {
    var provider: AIProvider { get }

    /// Ob das Schema `additionalProperties: false` enthalten darf (Gemini lehnt es ab).
    var supportsAdditionalProperties: Bool { get }

    /// Schickt System- und User-Prompt und liefert den Antworttext, der `schema` folgt.
    func structuredText(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        speed: AISpeed,
        apiKey: String,
        model: String
    ) async throws -> String
}

extension AIProviderClient {

    /// Wein-Empfehlung zu einem Gericht – roh, noch nicht validiert.
    func recommend(
        _ request: PairingRequest,
        repairHint: String? = nil,
        speed: AISpeed = .quality,
        apiKey: String,
        model: String
    ) async throws -> (PairingResponse, rawText: String) {
        let text = try await structuredText(
            system: PromptBuilder.systemPrompt(maxRecommendations: request.maxRecommendations),
            user: PromptBuilder.userPrompt(for: request, repairHint: repairHint),
            schemaName: "wine_pairing",
            schema: RecommendationSchema.jsonSchema(includeAdditionalProperties: supportsAdditionalProperties),
            speed: speed,
            apiKey: apiKey,
            model: model
        )
        return (try PairingResponse.decode(fromModelText: text), text)
    }

    /// Etikett-Text zu Feldern zuordnen.
    func extractLabel(recognizedText: String, apiKey: String, model: String) async throws -> WineLabelExtraction {
        let text = try await structuredText(
            system: PromptBuilder.labelSystemPrompt(),
            user: PromptBuilder.labelUserPrompt(recognizedText: recognizedText),
            schemaName: "wine_label",
            schema: LabelSchema.jsonSchema(includeAdditionalProperties: supportsAdditionalProperties),
            speed: .quality,
            apiKey: apiKey,
            model: model
        )
        return try JSONDecoding.decode(WineLabelExtraction.self, fromModelText: text)
    }

    /// Übersetzt einen kurzen Etikett-Text in die gewählte App-Sprache. Wird nur aufgerufen,
    /// wenn die Spracherkennung sicher ist, dass der Text noch nicht in dieser Sprache ist.
    func translateToGerman(_ text: String, apiKey: String, model: String) async throws -> String {
        let answer = try await structuredText(
            system: PromptBuilder.translationSystemPrompt(),
            user: PromptBuilder.translationUserPrompt(text: text),
            schemaName: "translation",
            schema: TranslationSchema.jsonSchema(includeAdditionalProperties: supportsAdditionalProperties),
            speed: .fast,
            apiKey: apiKey,
            model: model
        )
        return try JSONDecoding.decode(TranslationResult.self, fromModelText: answer).german
    }
}

/// Antwort der Übersetzungsanfrage.
struct TranslationResult: Codable, Sendable {
    let german: String
}

enum TranslationSchema {
    static func jsonSchema(includeAdditionalProperties: Bool) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": [
                "german": ["type": "string", "description": "Der übersetzte Text in der verlangten Zielsprache, ohne Zusätze."]
            ],
            "required": ["german"]
        ]
        if includeAdditionalProperties {
            schema["additionalProperties"] = false
        }
        return schema
    }
}

// MARK: - Fassade

/// Zentrale Anlaufstelle für die UI / ViewModels.
///
/// Der Service ist bewusst zustandslos: Anbieter, Key und Modell werden pro Aufruf übergeben
/// (typischerweise aus `AISettings`). Dadurch lässt er sich in Tests mit Fake-Clients füttern
/// und ist nicht an den Main Actor gebunden.
final class AIService: Sendable {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "AIService")
    private let clients: [AIProvider: any AIProviderClient]

    /// Standard-Konfiguration mit den drei echten Clients.
    convenience init(session: URLSession = .shared) {
        let transport = HTTPTransport(session: session)
        self.init(clients: [
            OpenAIClient(transport: transport),
            GeminiClient(transport: transport),
            AnthropicClient(transport: transport)
        ])
    }

    /// Für Tests oder um einzelne Anbieter auszutauschen.
    init(clients: [any AIProviderClient]) {
        self.clients = Dictionary(uniqueKeysWithValues: clients.map { ($0.provider, $0) })
    }

    private func client(for provider: AIProvider) -> any AIProviderClient {
        guard let client = clients[provider] else {
            preconditionFailure("Kein Client für \(provider) registriert.")
        }
        return client
    }

    // MARK: Wein-Empfehlung

    /// Holt eine Top-N-Empfehlung vom gewünschten Anbieter, prüft sie auf Plausibilität
    /// und wiederholt die Anfrage einmal mit Korrekturhinweis, falls sie unbrauchbar war.
    func recommend(
        _ request: PairingRequest,
        provider: AIProvider,
        apiKey: String,
        model: String,
        speed: AISpeed = .quality
    ) async throws -> PairingResponse {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingAPIKey(provider) }
        guard !request.inventory.isEmpty else {
            // Kein Netzwerkaufruf nötig – die KI könnte ohnehin nichts empfehlen.
            return PairingResponse(
                recommendations: [],
                generalNote: tr("Der Weinkeller ist leer. Lege zuerst Flaschen an, damit ich etwas empfehlen kann.")
            )
        }

        let client = client(for: provider)
        var repairHint: String?
        // Bei Siri zählt Tempo: nur ein Versuch, kein Reparaturlauf.
        let maxAttempts = speed == .fast ? 1 : 2
        for attempt in 1...maxAttempts {
            let (raw, rawText) = try await client.recommend(request, repairHint: repairHint, speed: speed, apiKey: key, model: model)
            let validation = PairingValidator.validate(raw, inventory: request.inventory)
            switch validation {
            case .usable(let response):
                if attempt > 1 { Self.logger.info("Empfehlung im 2. Versuch brauchbar (\(provider.shortName))") }
                return response
            case .unusable(let reason):
                Self.logger.warning("Unbrauchbare Empfehlung von \(provider.shortName) (Versuch \(attempt)): \(reason). Rohantwort: \(rawText.prefix(1500))")
                repairHint = PromptBuilder.repairHint
            }
        }
        throw AIServiceError.unusableResponse
    }

    /// Bequemer Einstieg direkt aus den Einstellungen heraus: verwendet automatisch
    /// den Anbieter, für den ein API-Key hinterlegt ist.
    @MainActor
    func recommend(_ request: PairingRequest, using settings: AISettings, speed: AISpeed = .quality) async throws -> PairingResponse {
        guard let provider = settings.activeProvider else {
            throw AIServiceError.noProviderConfigured
        }
        return try await recommend(
            request,
            provider: provider,
            apiKey: settings.apiKey(for: provider),
            model: settings.model(for: provider, speed: speed),
            speed: speed
        )
    }

    // MARK: Etikett-Erkennung

    /// Ordnet OCR-Text den Weinfeldern zu – über den angegebenen Cloud-Anbieter.
    func extractLabel(
        recognizedText: String,
        provider: AIProvider,
        apiKey: String,
        model: String
    ) async throws -> WineLabelExtraction {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingAPIKey(provider) }
        return try await client(for: provider).extractLabel(recognizedText: recognizedText, apiKey: key, model: model)
    }

    /// Übersetzt eine fremdsprachige Etikett-Notiz ins Deutsche.
    func translateToGerman(
        _ text: String,
        provider: AIProvider,
        apiKey: String,
        model: String
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingAPIKey(provider) }
        return try await client(for: provider).translateToGerman(text, apiKey: key, model: model)
    }
}

// MARK: - Plausibilitätsprüfung

/// Prüft, ob eine Empfehlung inhaltlich brauchbar ist, und bereinigt sie:
/// unbekannte Weine und Platzhalter fliegen raus, Ränge werden neu vergeben.
enum PairingValidator {

    enum Result {
        case usable(PairingResponse)
        case unusable(String)
    }

    private static let placeholderWords = ["placeholder", "platzhalter", "lorem", "todo", "n/a", "tbd", "xxx"]

    static func validate(_ response: PairingResponse, inventory: [WineInventoryItem]) -> Result {
        // 1. Nur Empfehlungen behalten, die einem Inventar-Eintrag zuzuordnen sind und echten Text haben.
        var seen = Set<String>()
        var cleaned: [PairingRecommendation] = []
        for rec in response.sortedRecommendations {
            guard let item = match(rec, in: inventory) else { continue }
            guard isRealText(rec.reasoning, minLength: 20) else { continue }
            let key = "\(item.name.lowercased())|\(item.vintage)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            var fixed = rec
            fixed.wineName = item.name          // exakte Schreibweise aus dem Inventar
            fixed.vintage = item.vintage
            if !isRealText(fixed.servingTip, minLength: 5) { fixed.servingTip = "" }
            cleaned.append(fixed)
        }
        for index in cleaned.indices { cleaned[index].rank = index + 1 }

        let noteOK = isRealText(response.generalNote, minLength: 10)
        let tipOK = isRealText(response.shoppingTip, minLength: 5)

        // 2. Entscheiden: Wenn das Modell Empfehlungen geliefert hat, muss mindestens eine überleben.
        if cleaned.isEmpty {
            if !response.recommendations.isEmpty {
                return .unusable("alle \(response.recommendations.count) Empfehlungen ungültig (unbekannter Wein oder Platzhalter)")
            }
            // Ehrliches „nichts passt“ ist nur mit Erklärung brauchbar.
            guard noteOK else { return .unusable("keine Empfehlungen und keine Begründung") }
        } else if !noteOK && !tipOK {
            return .unusable("Begründung und Kauftipp fehlen oder sind Platzhalter")
        }

        var result = response
        result.recommendations = cleaned
        if !noteOK { result.generalNote = "" }
        if !tipOK { result.shoppingTip = "" }
        // Wenn nichts oder nur eine Notlösung übrig ist, ehrlich markieren.
        if cleaned.isEmpty || cleaned.allSatisfy({ $0.fit == .poor || $0.fit == .acceptable }) {
            result.noGoodMatch = true
        }
        return .usable(result)
    }

    /// Findet den Inventar-Eintrag: exakt Name + Jahrgang, sonst Name, sonst enthaltener Name.
    static func match(_ rec: PairingRecommendation, in inventory: [WineInventoryItem]) -> WineInventoryItem? {
        let name = rec.wineName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard name.count >= 2 else { return nil }
        if let exact = inventory.first(where: { $0.name.lowercased() == name && $0.vintage == rec.vintage }) { return exact }
        if let byName = inventory.first(where: { $0.name.lowercased() == name }) { return byName }
        return inventory.first { item in
            let itemName = item.name.lowercased()
            let full = "\(item.producer) \(item.name)".lowercased()
            return name.contains(itemName) || full.contains(name)
        }
    }

    static func isRealText(_ text: String, minLength: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return false }
        let lowered = trimmed.lowercased()
        return !placeholderWords.contains(where: lowered.contains)
    }
}

// MARK: - Gemeinsames Decoding strukturierter Antworten

enum JSONDecoding {

    /// Dekodiert den JSON-Text, den ein Anbieter im Structured-Output-Modus liefert.
    /// Entfernt vorsorglich Markdown-Codefences (```json … ```), falls ein Modell sie doch mitschickt.
    static func decode<T: Decodable>(_ type: T.Type, fromModelText text: String) throws -> T {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8), !data.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed(error.localizedDescription)
        }
    }
}

extension PairingResponse {
    static func decode(fromModelText text: String) throws -> PairingResponse {
        var response = try JSONDecoding.decode(PairingResponse.self, fromModelText: text)
        response.recommendations = response.sortedRecommendations
        return response
    }
}
