import CoreGraphics
import Foundation
import ImageIO

#if canImport(FoundationModels)
import FoundationModels

/// Zuordnung des Etikett-Texts mit einem lokalen Modell: Apple Intelligence auf dem Gerät
/// (ab iOS 26, iPhone 15 Pro und neuer) oder Apples Private Cloud (ab iOS 27).
///
/// Mit dem Modell der Private Cloud geht zusätzlich das **Foto des Etiketts** mit: Es nimmt
/// Bilder an, liest damit geschwungene oder verschnörkelte Schrift besser als jede
/// Texterkennung und hat Platz genug dafür. Das kleine Modell auf dem Gerät bekommt nur den
/// Text – sein Kontext von rund 4000 Token reicht für ein Bild nicht verlässlich.
@available(iOS 26.0, *)
enum LocalLabelParser {

    static func parse(
        recognizedText: String,
        source: LocalAISource,
        language: AppLanguage,
        labelImages: [Data] = []
    ) async throws -> WineLabelExtraction {
        let instructions = PromptBuilder.labelSystemPrompt(language: language)
        guard let session = LocalAI.session(for: source, instructions: instructions) else {
            throw LocalAIError.sourceMissing
        }
        let prompt = PromptBuilder.labelUserPrompt(recognizedText: recognizedText)

        let label: GeneratedWineLabel
        if source == .privateCloud, !labelImages.isEmpty, #available(iOS 27.0, *) {
            let images = labelImages.compactMap(Self.cgImage(from:))
            let response = try await session.respond(generating: GeneratedWineLabel.self) {
                prompt
                for image in images { Attachment(image) }
            }
            label = response.content
        } else {
            label = try await session.respond(to: prompt, generating: GeneratedWineLabel.self).content
        }
        return WineLabelExtraction(
            name: label.name,
            producer: label.producer,
            vintage: label.vintage,
            grape: label.grape,
            region: label.region,
            country: label.country,
            type: label.type,
            alcoholPercent: label.alcoholPercent,
            notes: label.notes,
            foodPairings: label.foodPairings,
            drinkFrom: label.drinkFrom,
            drinkTo: label.drinkTo,
            drinkWindowFromLabel: label.drinkWindowFromLabel,
            foodPairingSource: label.foodPairingSource
        )
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Fehler der lokalen Wege, die über die Fehler von Foundation Models hinausgehen.
enum LocalAIError: Error {
    /// Die Quelle gibt es auf diesem System nicht (z. B. Private Cloud unter iOS 26).
    case sourceMissing
    /// Die Antwort war leer oder ohne brauchbaren Inhalt.
    case emptyResult
}

/// Zielstruktur für das Foundation-Models-Framework. Spiegel von `WineLabelExtraction`.
@available(iOS 26.0, *)
@Generable
struct GeneratedWineLabel {
    @Guide(description: "Name des Weins oder der Cuvée ohne Produzent, leer wenn unbekannt")
    var name: String

    @Guide(description: "Produzent, Weingut, Domaine oder Château, leer wenn unbekannt")
    var producer: String

    @Guide(description: "Jahrgang als vierstellige Zahl, 0 wenn unbekannt")
    var vintage: Int

    @Guide(description: "Rebsorten kommagetrennt in Originalschreibweise, leer wenn unbekannt")
    var grape: String

    @Guide(description: "Region oder Appellation, leer wenn unbekannt")
    var region: String

    @Guide(description: "Herkunftsland in der Antwortsprache, z. B. Frankreich. Leer wenn unklar.")
    var country: String

    @Guide(description: "Weintyp: genau einer von red, white, sparkling, rose, mulled, unknown. mulled steht für Glühwein und ähnliche Winter-Heissgetränke und geht vor der Farbangabe.")
    var type: String

    @Guide(description: "Alkoholgehalt in Volumenprozent, 0 wenn unbekannt")
    var alcoholPercent: Double

    @Guide(description: "Ein bis zwei Sätze zu Terroir, Vinifikation und Ausbau, zwingend in der Antwortsprache – fremdsprachigen Etikett-Text übersetzen, nicht kopieren. Leer, wenn nichts dazu steht.")
    var notes: String

    @Guide(description: "Speiseempfehlungen vom Etikett, in die Antwortsprache übersetzt, kurze Begriffe. Leeres Array, wenn nichts dazu auf dem Etikett steht.")
    var foodPairings: [String]

    @Guide(description: "Der wörtlich aus dem erkannten Text kopierte Abschnitt, auf dem die Speiseempfehlung beruht. Leer, wenn es keine gibt.")
    var foodPairingSource: String

    @Guide(description: "Erstes empfohlenes Trinkjahr als vierstellige Zahl, 0 wenn nicht bestimmbar")
    var drinkFrom: Int

    @Guide(description: "Letztes empfohlenes Trinkjahr als vierstellige Zahl, 0 wenn nicht bestimmbar")
    var drinkTo: Int

    @Guide(description: "true nur, wenn die Trinkreife ausdrücklich auf dem Etikett steht; bei eigener Einschätzung false")
    var drinkWindowFromLabel: Bool
}
#endif
