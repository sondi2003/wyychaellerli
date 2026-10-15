import Foundation
import Observation
import CoreData

/// Zustand des Tabs „Wein-Berater“: Eingabe, Ladezustand, Ergebnis, Fehler.
@Observable
@MainActor
final class PairingViewModel {

    /// Schnellvorschläge für die Eingabe.
    static let suggestions = [
        tr("Raclette"), tr("Spaghetti Bolognese"), tr("Gegrillter Lachs"), tr("Rindsfilet"),
        tr("Pizza Margherita"), tr("Sushi"), tr("Käseplatte"), tr("Thai-Curry"), tr("Apéro")
    ]

    /// Ein Wein, dessen Etikett das gesuchte Gericht ausdrücklich nennt.
    struct LabelMatch: Identifiable {
        let wine: Wine
        let terms: [String]
        var id: NSManagedObjectID { wine.objectID }
    }

    var dish = ""
    var isLoading = false
    var response: PairingResponse?

    /// Wie der lokale Abgleich mit den Etiketten ausgegangen ist.
    enum LabelCheckOutcome: Equatable {
        /// Mindestens ein Etikett nennt das Gericht.
        case matched
        /// Etiketten sind hinterlegt, keines passt zum Gericht.
        case noMatch
        /// Bei keiner Flasche im Keller sind Etikett-Angaben erfasst.
        case nothingStored
    }

    /// Treffer aus den Etiketten – ohne KI, ohne Kosten.
    private(set) var labelMatches: [LabelMatch] = []
    /// Für welches Gericht die Etikett-Treffer gelten.
    private(set) var labelMatchDish = ""
    /// `nil`, solange noch nichts gesucht wurde.
    private(set) var labelCheckOutcome: LabelCheckOutcome?

    /// Letzter Fehler, typisiert – damit die UI Titel und passende Aktionen anbieten kann.
    var error: AIServiceError?

    /// Für welchen Anbieter und welches Gericht das aktuelle Ergebnis gilt.
    private(set) var resultProvider: AIProvider?
    private(set) var resultModel = ""
    private(set) var resultDish = ""

    var trimmedDish: String { dish.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasLabelMatches: Bool { !labelMatches.isEmpty }

    /// Auch ohne API-Key möglich: Der Abgleich mit den Etiketten läuft lokal.
    func canRequest(hasInventory: Bool) -> Bool {
        !trimmedDish.isEmpty && !isLoading && hasInventory
    }

    /// Sucht zuerst in den Etiketten. Nur wenn dort nichts steht – oder der Nutzer
    /// ausdrücklich mehr will – wird die KI gefragt.
    func requestRecommendation(
        wines: [Wine],
        settings: AISettings,
        service: AIService,
        forceAI: Bool = false
    ) async {
        let dish = trimmedDish
        guard !dish.isEmpty else { return }

        error = nil
        if !forceAI {
            response = nil
            let matches = wines.compactMap { wine -> LabelMatch? in
                let terms = LabelPairingMatcher.matchingTerms(dish: dish, pairings: wine.foodPairings)
                return terms.isEmpty ? nil : LabelMatch(wine: wine, terms: terms)
            }
            labelMatches = matches
            labelMatchDish = dish
            if !matches.isEmpty {
                labelCheckOutcome = .matched
                // Treffer auf dem Etikett: keine Anfrage nötig.
                return
            }
            // Unterscheiden, ob nichts passt oder schlicht nichts erfasst ist.
            labelCheckOutcome = wines.contains { !$0.foodPairings.isEmpty } ? .noMatch : .nothingStored
        }

        guard settings.activeProvider != nil else {
            error = .noProviderConfigured
            return
        }

        isLoading = true
        response = nil
        defer { isLoading = false }

        let provider = settings.activeProvider
        let model = settings.activeModel ?? ""
        do {
            let result = try await service.recommend(
                PairingRequest(dish: dish, inventory: wines.map(\.inventoryItem)),
                using: settings
            )
            response = result
            resultProvider = provider
            resultModel = model
            resultDish = dish
        } catch let serviceError as AIServiceError {
            error = serviceError
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

    func reset() {
        response = nil
        error = nil
        labelMatches = []
        labelMatchDish = ""
        labelCheckOutcome = nil
        resultProvider = nil
        resultModel = ""
        resultDish = ""
    }
}
