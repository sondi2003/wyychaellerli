import Foundation
import NaturalLanguage
import OSLog

#if canImport(Translation)
import Translation
#endif

/// Sorgt dafür, dass die Notizen vom Etikett in der gewählten App-Sprache landen
/// (Deutsch oder Serbisch).
///
/// Der Prompt verlangt Deutsch, aber die Modelle halten sich nicht zuverlässig daran –
/// besonders das kleine Modell auf dem Gerät übernimmt den französischen oder italienischen
/// Rückseitentext gern wörtlich. Deshalb wird hinterher **geprüft** statt gehofft.
///
/// Reihenfolge, absichtlich vom Billigsten zum Teuersten:
/// 1. Apples Übersetzung auf dem Gerät – kostenlos, offline, keine Anfrage nach aussen.
///    Braucht iOS 26 und ein bereits geladenes Sprachpaket.
/// 2. Der aktive Cloud-Anbieter – kostet eine zusätzliche Anfrage, aber nur dann,
///    wenn die Notiz wirklich fremdsprachig ist.
/// 3. Nichts davon möglich: Originaltext behalten. Eine fremdsprachige Notiz ist
///    immer noch besser als gar keine.
enum LabelNotesTranslator {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "LabelScan")

    /// Kürzere Texte erkennt `NLLanguageRecognizer` zu unzuverlässig, um darauf eine
    /// Übersetzung zu stützen.
    private static let minimumLength = 25

    /// Unter dieser Sicherheit wird nichts angefasst – lieber das Original stehen lassen,
    /// als eine deutsche Notiz „übersetzen“ zu lassen.
    private static let minimumConfidence = 0.65

    /// Liefert die Notiz in der App-Sprache, oder unverändert, wenn sie es schon ist.
    static func localized(
        _ notes: String,
        aiService: AIService,
        cloud: CloudCredentials?,
        target: AppLanguage = .current
    ) async -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let language = foreignLanguage(in: trimmed, target: target) else { return notes }
        logger.info("Notiz ist nicht in der App-Sprache (\(language.rawValue)) – wird übersetzt")

        if let translated = await appleTranslation(of: trimmed, from: language, target: target) {
            logger.info("Notiz mit Apples Übersetzung auf dem Gerät übersetzt")
            return translated
        }
        if let cloud, let translated = try? await aiService.translateToGerman(
            trimmed,
            provider: cloud.provider,
            apiKey: cloud.apiKey,
            model: cloud.model
        ), !translated.isEmpty {
            logger.info("Notiz über \(cloud.provider.shortName) übersetzt")
            return translated
        }
        logger.warning("Keine Übersetzung möglich – fremdsprachige Notiz bleibt stehen")
        return notes
    }

    // MARK: Spracherkennung

    /// Die erkannte Sprache, falls es sicher **nicht** die Zielsprache ist. Sonst `nil`.
    ///
    /// Beim Serbischen zählen auch Kroatisch und Bosnisch als Zielsprache: Die Erkennung
    /// trennt die drei nicht zuverlässig, und eine Übersetzung wäre dort nur Rauschen.
    static func foreignLanguage(in text: String, target: AppLanguage = .german) -> NLLanguage? {
        guard text.count >= minimumLength else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let targetCodes: Set<String> = target.isSerbian ? ["sr", "sr-Latn", "hr", "bs"] : ["de"]
        guard !targetCodes.contains(language.rawValue) else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 3)[language] ?? 0
        guard confidence >= minimumConfidence else { return nil }
        return language
    }

    // MARK: Apples Übersetzung

    /// Übersetzt auf dem Gerät, wenn das Sprachpaket schon installiert ist.
    ///
    /// Ein fehlendes Paket wird bewusst **nicht** nachgeladen: Das ginge nur über einen
    /// Systemdialog aus einer View heraus, und der gehört nicht mitten in einen Scan.
    private static func appleTranslation(of text: String, from language: NLLanguage, target: AppLanguage) async -> String? {
        #if canImport(Translation)
        guard #available(iOS 26.0, *) else { return nil }
        let source = Locale.Language(identifier: language.rawValue)
        let targetLanguage = Locale.Language(identifier: target.resolvedIdentifier)
        guard await LanguageAvailability().status(from: source, to: targetLanguage) == .installed else {
            return nil
        }
        let session = TranslationSession(installedSource: source, target: targetLanguage)
        guard let response = try? await session.translate(text) else { return nil }
        let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        return translated.isEmpty ? nil : translated
        #else
        return nil
        #endif
    }
}
