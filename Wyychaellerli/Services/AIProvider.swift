import Foundation

/// Die drei unterstützten KI-Anbieter. `rawValue` dient gleichzeitig als
/// Keychain-Account und als UserDefaults-Schlüssel – also nicht umbenennen.
enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI = "openai"
    case gemini = "gemini"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:    return "ChatGPT (OpenAI)"
        case .gemini:    return "Gemini (Google)"
        case .anthropic: return "Claude (Anthropic)"
        }
    }

    var shortName: String {
        switch self {
        case .openAI:    return "ChatGPT"
        case .gemini:    return "Gemini"
        case .anthropic: return "Claude"
        }
    }

    /// Modell, das verwendet wird, solange der Nutzer in den Einstellungen nichts anderes einträgt.
    var defaultModel: String {
        switch self {
        case .openAI:    return "gpt-5"
        case .gemini:    return "gemini-2.5-pro"
        // Sonnet 5 ist für ein Wein-Pairing schnell genug und deutlich günstiger als Opus 5.
        // Wer die ausführlichere Begründung will, trägt in den Einstellungen claude-opus-5 ein.
        case .anthropic: return "claude-sonnet-5"
        }
    }

    /// Schnelleres Modell für Siri-Anfragen. Siri wartet nicht lange, deshalb zählt hier
    /// Antwortzeit mehr als die letzte Nuance in der Begründung.
    var defaultFastModel: String {
        switch self {
        case .openAI:    return "gpt-5-mini"
        case .gemini:    return "gemini-2.5-flash"
        case .anthropic: return "claude-sonnet-5"
        }
    }

    /// Hilfetext für das API-Key-Feld.
    var apiKeyHint: String {
        switch self {
        case .openAI:    return tr("Beginnt mit „sk-…“ – erstellen unter platform.openai.com/api-keys")
        case .gemini:    return tr("Erstellen unter aistudio.google.com/app/apikey")
        case .anthropic: return tr("Beginnt mit „sk-ant-…“ – erstellen unter console.anthropic.com")
        }
    }

    var symbolName: String {
        switch self {
        case .openAI:    return "bubble.left.and.text.bubble.right"
        case .gemini:    return "sparkles"
        case .anthropic: return "brain"
        }
    }
}
