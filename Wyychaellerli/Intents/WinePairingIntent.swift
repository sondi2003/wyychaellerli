import AppIntents
import Foundation
import OSLog
import CoreData
import SwiftUI

/// Siri-Befehl: „Wein-Berater in Wyychällerli“ → Siri fragt nach dem Essen und
/// liest die beste Empfehlung aus dem eigenen Keller vor.
///
/// Läuft ohne die App zu öffnen. Für Tempo wird das schnelle Modell verwendet
/// (`AISpeed.fast`), da Siri nicht lange auf eine Antwort wartet.
struct WinePairingIntent: AppIntent {

    static let title: LocalizedStringResource = "Wein zum Essen empfehlen"
    static let description = IntentDescription(
        "Schlägt einen passenden Wein aus deinem Weinkeller zum geplanten Essen vor."
    )
    /// Antwort direkt in Siri, ohne die App in den Vordergrund zu holen.
    static let openAppWhenRun = false

    @Parameter(
        title: "Gericht",
        description: "Was gibt es zu essen?",
        requestValueDialog: "Was gibt es zu essen?"
    )
    var dish: String

    static var parameterSummary: some ParameterSummary {
        Summary("Wein zu \(\.$dish) empfehlen")
    }

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "SiriIntent")

    /// Alles, was Siri am Ende braucht: gesprochener Text plus Karte.
    /// Wird in `perform` schrittweise gefüllt, damit es nur eine Rückgabe gibt
    /// (der Rückgabetyp eines App Intents muss an allen Stellen identisch sein).
    private struct Ausgabe {
        var gesprochen: String
        var titel: String
        var text: String
        var wein: WineSnapshot?
        var kauftipp: String

        init(gesprochen: String, titel: String, text: String, wein: WineSnapshot? = nil, kauftipp: String = "") {
            self.gesprochen = gesprochen
            self.titel = titel
            self.text = text
            self.wein = wein
            self.kauftipp = kauftipp
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let ausgabe = await Self.ergebnis(fuer: dish)
        return .result(
            dialog: IntentDialog(stringLiteral: ausgabe.gesprochen),
            view: PairingSnippetView(
                headline: ausgabe.titel,
                message: ausgabe.text,
                wine: ausgabe.wein,
                shoppingTip: ausgabe.kauftipp
            )
        )
    }

    // MARK: Ablauf

    @MainActor
    private static func ergebnis(fuer gerichtRoh: String) async -> Ausgabe {
        let gericht = gerichtRoh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gericht.isEmpty else {
            return Ausgabe(
                gesprochen: tr("Ich habe nicht verstanden, was es zu essen gibt."),
                titel: tr("Kein Gericht erkannt"),
                text: tr("Sag zum Beispiel: Lasagne, Raclette oder gegrillter Lachs.")
            )
        }

        let settings = AISettings()
        guard settings.activeProvider != nil else {
            return Ausgabe(
                gesprochen: tr("In deinem Weinkeller ist noch kein Schlüssel für den Wein-Berater hinterlegt. Trag ihn in den Einstellungen der App ein."),
                titel: tr("Kein Anbieter eingerichtet"),
                text: tr("Der Wein-Berater braucht einen API-Key. Du findest das in den Einstellungen der App.")
            )
        }

        let wines = PersistenceController.shared.availableWines()
        guard !wines.isEmpty else {
            return Ausgabe(
                gesprochen: tr("In deinem Weinkeller liegt gerade keine Flasche mit Bestand."),
                titel: tr("Keller ist leer"),
                text: tr("Lege zuerst Flaschen an, damit ich etwas empfehlen kann.")
            )
        }

        do {
            let response = try await AIService().recommend(
                PairingRequest(dish: gericht, inventory: wines.map(\.inventoryItem), maxRecommendations: 2),
                using: settings,
                speed: .fast
            )
            return antwort(for: response, gericht: gericht, wines: wines)
        } catch {
            logger.error("Siri-Empfehlung fehlgeschlagen: \(error.localizedDescription)")
            return Ausgabe(
                gesprochen: tr("Das hat gerade nicht geklappt. Versuch es in der App noch einmal."),
                titel: tr("Keine Empfehlung möglich"),
                text: error.localizedDescription
            )
        }
    }

    // MARK: Antwort formulieren

    @MainActor
    private static func antwort(for response: PairingResponse, gericht: String, wines: [Wine]) -> Ausgabe {
        guard let beste = response.sortedRecommendations.first else {
            // Ehrliche Absage – genau wie in der App.
            let begruendung = response.generalNote.isEmpty
                ? tr("Zu \(gericht) passt aus deinem Keller gerade nichts wirklich.")
                : response.generalNote
            let gesprochen = response.shoppingTip.isEmpty
                ? begruendung
                : "\(begruendung) \(response.shoppingTip)"
            return Ausgabe(
                gesprochen: gesprochen,
                titel: tr("Keine passende Flasche"),
                text: begruendung,
                kauftipp: response.shoppingTip
            )
        }

        let wein = passenderWein(zu: beste, in: wines)
        let bezeichnung = wein.map { $0.producer.isEmpty ? $0.name : "\($0.name) von \($0.producer)" } ?? beste.wineName
        let jahrgang = wein.map { Int($0.vintage) } ?? beste.vintage

        var gesprochen = tr("Zu \(gericht) empfehle ich \(bezeichnung), Jahrgang \(String(jahrgang)).")
        if beste.fit == .acceptable || beste.fit == .poor {
            gesprochen += " " + tr("Perfekt passt es nicht, aber es ist die beste Flasche im Keller.")
        }
        if !beste.reasoning.isEmpty {
            gesprochen += " \(beste.reasoning)"
        }

        return Ausgabe(
            gesprochen: gesprochen,
            titel: beste.wineName,
            text: beste.reasoning,
            wein: wein.map { WineSnapshot(wine: $0, fit: beste.fit) },
            kauftipp: response.noGoodMatch ? response.shoppingTip : ""
        )
    }

    /// Ordnet die Empfehlung dem Wein im Keller zu (Name + Jahrgang, sonst Name).
    private static func passenderWein(zu empfehlung: PairingRecommendation, in wines: [Wine]) -> Wine? {
        let name = empfehlung.wineName.lowercased()
        return wines.first { $0.name.lowercased() == name && Int($0.vintage) == empfehlung.vintage }
            ?? wines.first { $0.name.lowercased() == name }
    }
}
