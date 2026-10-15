import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Zuordnung des Etikett-Texts mit Apple Intelligence – vollständig auf dem Gerät.
/// Verfügbar ab iOS 26 auf Geräten mit Apple Intelligence (iPhone 15 Pro und neuer),
/// sofern Apple Intelligence in den Systemeinstellungen aktiviert ist.
@available(iOS 26.0, *)
enum OnDeviceLabelParser {

    /// `true`, wenn das Sprachmodell auf diesem Gerät gerade einsatzbereit ist.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func parse(recognizedText: String) async throws -> WineLabelExtraction {
        let session = LanguageModelSession(instructions: PromptBuilder.labelSystemPrompt(language: .german))
        let response = try await session.respond(
            to: PromptBuilder.labelUserPrompt(recognizedText: recognizedText),
            generating: GeneratedWineLabel.self
        )
        let label = response.content
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

    @Guide(description: "Herkunftsland auf Deutsch, z. B. Frankreich. Leer wenn unklar.")
    var country: String

    @Guide(description: "Weintyp: genau einer von red, white, sparkling, rose, mulled, unknown. mulled steht für Glühwein und ähnliche Winter-Heissgetränke und geht vor der Farbangabe.")
    var type: String

    @Guide(description: "Alkoholgehalt in Volumenprozent, 0 wenn unbekannt")
    var alcoholPercent: Double

    @Guide(description: "Ein bis zwei Sätze zu Terroir, Vinifikation und Ausbau, zwingend auf Deutsch – fremdsprachigen Etikett-Text übersetzen, nicht kopieren. Leer, wenn nichts dazu steht.")
    var notes: String

    @Guide(description: "Speiseempfehlungen vom Etikett, ins Deutsche übersetzt, kurze Begriffe. Leeres Array, wenn nichts dazu auf dem Etikett steht.")
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
