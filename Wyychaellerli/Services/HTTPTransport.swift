import Foundation

/// Fehler, die aus dem KI-Layer nach oben wandern. Alle sind `LocalizedError`,
/// damit die UI sie direkt anzeigen kann.
enum AIServiceError: LocalizedError, Sendable {
    /// Es ist für keinen Anbieter ein API-Key hinterlegt.
    case noProviderConfigured
    /// Für den gewählten Anbieter ist kein API-Key hinterlegt.
    case missingAPIKey(AIProvider)
    /// Der Anbieter hat den Key abgelehnt (HTTP 401/403).
    case invalidAPIKey(AIProvider)
    /// Guthaben bzw. Kontingent aufgebraucht (z. B. OpenAI `insufficient_quota`,
    /// Anthropic „credit balance too low“, Gemini `RESOURCE_EXHAUSTED`).
    case quotaExceeded(AIProvider)
    /// Zu viele Anfragen in kurzer Zeit (HTTP 429 ohne Quota-Hinweis).
    case rateLimited(AIProvider)
    /// Der Anbieter ist gerade nicht erreichbar (HTTP 5xx).
    case providerUnavailable(AIProvider, status: Int)
    /// Der eingestellte Modellname ist dem Anbieter unbekannt.
    case unknownModel(AIProvider)
    /// Die Endpoint-URL konnte nicht gebaut werden (z. B. ungültiger Modellname bei Gemini).
    case invalidURL
    /// Sonstiger Fehlerstatus; `message` ist der (gekürzte) Body.
    case httpError(status: Int, message: String)
    /// Die Antwort enthielt keinen verwertbaren Text.
    case emptyResponse
    /// Der Text der Antwort war kein gültiges `PairingResponse`-JSON.
    case decodingFailed(String)
    /// Der Anbieter hat die Anfrage abgelehnt (Safety-Filter).
    case refused(String?)
    /// Die Antwort wurde am Token-Limit abgeschnitten.
    case truncated
    /// Die Antwort war formal gültig, aber inhaltlich unbrauchbar (Platzhalter, unbekannte Weine) – auch nach Wiederholung.
    case unusableResponse
    /// Netzwerkfehler (offline, Timeout, …).
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return tr("Es ist noch kein API-Key hinterlegt. Bitte in den Einstellungen einen Anbieter einrichten.")
        case .missingAPIKey(let provider):
            return tr("Für \(provider.displayName) ist kein API-Key hinterlegt.")
        case .invalidAPIKey(let provider):
            return tr("\(provider.shortName) hat den API-Key abgelehnt. Bitte den Key in den Einstellungen prüfen.")
        case .quotaExceeded(let provider):
            return tr("Das Guthaben bei \(provider.shortName) ist aufgebraucht oder das Kontingent erschöpft.")
        case .rateLimited(let provider):
            return tr("\(provider.shortName) bremst gerade (zu viele Anfragen). Bitte in ein paar Sekunden erneut versuchen.")
        case .providerUnavailable(let provider, let status):
            return tr("\(provider.shortName) ist im Moment nicht erreichbar (HTTP \(status)). Bitte später erneut versuchen.")
        case .unknownModel(let provider):
            return tr("\(provider.shortName) kennt das eingestellte Modell nicht. Bitte den Modellnamen in den Einstellungen prüfen oder leer lassen.")
        case .invalidURL:
            return tr("Die Anfrage-URL konnte nicht erstellt werden.")
        case .httpError(let status, let message):
            return tr("Der Anbieter hat mit HTTP \(status) geantwortet: \(message)")
        case .emptyResponse:
            return tr("Die Antwort des Anbieters war leer.")
        case .decodingFailed(let detail):
            return tr("Die Antwort konnte nicht gelesen werden: \(detail)")
        case .refused(let reason):
            return tr("Die Anfrage wurde vom Anbieter abgelehnt.") + (reason.map { " (\($0))" } ?? "")
        case .truncated:
            return tr("Die Antwort wurde abgeschnitten. Bitte erneut versuchen.")
        case .unusableResponse:
            return tr("Die KI hat zweimal keine brauchbare Empfehlung geliefert (Platzhalter oder unbekannte Weine). Bitte erneut versuchen oder das Gericht genauer beschreiben.")
        case .network(let detail):
            return tr("Netzwerkfehler: \(detail)")
        }
    }

    /// Kurzer Titel für die Fehlerbox in der UI.
    var title: String {
        switch self {
        case .noProviderConfigured, .missingAPIKey: return tr("Kein API-Key")
        case .invalidAPIKey:                       return tr("API-Key ungültig")
        case .quotaExceeded:                       return tr("Guthaben aufgebraucht")
        case .rateLimited:                         return tr("Zu viele Anfragen")
        case .providerUnavailable:                 return tr("Anbieter nicht erreichbar")
        case .unknownModel:                        return tr("Modell unbekannt")
        case .network:                             return tr("Keine Verbindung")
        case .refused:                             return tr("Anfrage abgelehnt")
        case .truncated, .unusableResponse:        return tr("Unbrauchbare Antwort")
        default:                                   return tr("Fehler")
        }
    }

    /// Bei diesen Fehlern hilft ein Blick in die Einstellungen.
    var suggestsSettings: Bool {
        switch self {
        case .noProviderConfigured, .missingAPIKey, .invalidAPIKey, .quotaExceeded, .unknownModel:
            return true
        default:
            return false
        }
    }
}

/// Dünne Schicht über `URLSession`: JSON senden, Statuscode prüfen, Rohdaten zurückgeben.
/// Wird von allen drei Provider-Clients geteilt.
struct HTTPTransport: Sendable {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sendet `body` als JSON per POST und liefert den Antwort-Body.
    /// Wirft einen sprechenden `AIServiceError` bei Nicht-2xx und `.network` bei Transportproblemen.
    func postJSON(
        url: URL,
        provider: AIProvider,
        headers: [String: String],
        body: [String: Any],
        timeout: TimeInterval = 90
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIServiceError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.network("Keine HTTP-Antwort erhalten.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.classify(status: http.statusCode, body: data, provider: provider)
        }
        return data
    }

    // MARK: Fehler-Klassifikation

    /// Ordnet Statuscode + Fehlertext einem sprechenden Fehler zu.
    static func classify(status: Int, body: Data, provider: AIProvider) -> AIServiceError {
        let message = errorMessage(from: body)
        let lowered = message.lowercased()

        // Guthaben/Kontingent: die Anbieter signalisieren das unterschiedlich.
        let quotaHints = [
            "insufficient_quota", "quota", "credit balance", "billing",
            "resource_exhausted", "exceeded your current", "purchase credits"
        ]
        if quotaHints.contains(where: lowered.contains) {
            return .quotaExceeded(provider)
        }

        // Ungültiger Key: Gemini meldet das mit HTTP 400 statt 401.
        let keyHints = ["api key not valid", "invalid x-api-key", "incorrect api key", "invalid api key", "authentication_error"]
        if keyHints.contains(where: lowered.contains) {
            return .invalidAPIKey(provider)
        }

        // Unbekannter Modellname (Tippfehler oder nicht freigeschaltet).
        let modelHints = ["model", "models/"]
        let missingHints = ["not found", "does not exist", "not_found_error", "unsupported"]
        if modelHints.contains(where: lowered.contains), missingHints.contains(where: lowered.contains) {
            return .unknownModel(provider)
        }

        switch status {
        case 401, 403:
            return .invalidAPIKey(provider)
        case 402:
            return .quotaExceeded(provider)
        case 429:
            return .rateLimited(provider)
        case 500...599:
            return .providerUnavailable(provider, status: status)
        default:
            return .httpError(status: status, message: message)
        }
    }

    /// Versucht, aus einem Fehler-Body eine lesbare Nachricht zu ziehen.
    /// Alle drei Anbieter liefern `{"error": {"message": "…"}}` – mit leicht
    /// unterschiedlichen Zusatzfeldern.
    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? ""
            // OpenAI: "type"/"code", Gemini: "status", Anthropic: "type"
            let code = (error["code"] as? String) ?? (error["status"] as? String) ?? (error["type"] as? String) ?? ""
            let combined = [code, message].filter { !$0.isEmpty }.joined(separator: ": ")
            if !combined.isEmpty { return combined }
        }
        let raw = String(decoding: data, as: UTF8.self)
        return raw.isEmpty ? tr("(kein Fehlertext)") : String(raw.prefix(400))
    }
}

