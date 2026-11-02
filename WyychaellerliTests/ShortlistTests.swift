import Foundation
import Testing
@testable import Wyychaellerli

/// Vorauswahl für das kleine Modell auf dem Gerät: Es hat Platz für etwa ein Dutzend Flaschen.
struct ShortlistTests {

    private func item(
        _ name: String,
        type: String = "Rotwein",
        vintage: Int = 2020,
        drinkWindow: String = "",
        labelPairings: [String] = [],
        rating: String = ""
    ) -> WineInventoryItem {
        WineInventoryItem(
            name: name, producer: "", vintage: vintage, grape: "", region: "", type: type,
            alcohol: "", notes: "", labelPairings: labelPairings, drinkWindow: drinkWindow,
            rating: rating, ratingReasons: "", quantity: 1
        )
    }

    private func cellar(_ count: Int) -> [WineInventoryItem] {
        (0..<count).map { item("Wein \($0)", type: ["Rotwein", "Weisswein", "Schaumwein", "Rosé"][$0 % 4], vintage: 2000 + $0) }
    }

    @Test("Ein kleiner Keller geht vollständig durch")
    func smallCellarUnchanged() {
        let small = cellar(8)
        #expect(InventoryShortlist.select(from: small, dish: "Raclette") == small)
    }

    @Test("Ein grosser Keller wird auf das Limit gekürzt")
    func largeCellarIsCapped() {
        #expect(InventoryShortlist.select(from: cellar(300), dish: "Raclette").count == InventoryShortlist.onDeviceLimit)
    }

    @Test("Von jeder Weinart bleiben mindestens die Besten – nie nur Rotwein bei einem Fischgericht")
    func everyTypeSurvives() {
        let chosen = InventoryShortlist.select(from: cellar(300), dish: "Gegrillter Lachs")
        let types = Set(chosen.map(\.type))
        #expect(types.contains("Rotwein"))
        #expect(types.contains("Weisswein"))
        #expect(types.contains("Schaumwein"))
        #expect(types.contains("Rosé"))
    }

    @Test("Zu Fisch kommt Weisswein vor Rotwein, zu Lamm umgekehrt")
    func typeAffinityFollowsTheDish() {
        #expect(InventoryShortlist.typeAffinity("Weisswein", dish: "Lachs") > InventoryShortlist.typeAffinity("Rotwein", dish: "Lachs"))
        #expect(InventoryShortlist.typeAffinity("Rotwein", dish: "Lammrücken") > InventoryShortlist.typeAffinity("Weisswein", dish: "Lammrücken"))
        // Wo nichts eindeutig ist, bleibt es neutral.
        #expect(InventoryShortlist.typeAffinity("Rotwein", dish: "Lasagne") == InventoryShortlist.typeAffinity("Weisswein", dish: "Lasagne"))
    }

    @Test("Was jetzt dran ist, schlägt was noch zu jung oder vorbei ist")
    func drinkWindowCounts() {
        let ready = item("Bereit", drinkWindow: "2020–2030")
        let tooYoung = item("Zu jung", drinkWindow: "2035–2045")
        let pastPeak = item("Vorbei", drinkWindow: "2005–2015")
        let year = 2026
        #expect(InventoryShortlist.score(ready, dish: "", year: year) > InventoryShortlist.score(tooYoung, dish: "", year: year))
        #expect(InventoryShortlist.score(ready, dish: "", year: year) > InventoryShortlist.score(pastPeak, dish: "", year: year))
        // Letztes Jahr der Spanne: jetzt trinken.
        let last = item("Letztes Jahr", drinkWindow: "2018–2026")
        #expect(InventoryShortlist.score(last, dish: "", year: year) > InventoryShortlist.score(ready, dish: "", year: year))
    }

    @Test("Eine Etikett-Empfehlung, die das Gericht nennt, bringt die Flasche nach vorn")
    func labelPairingHelps() {
        let named = item("Mit Etikett", labelPairings: ["Gegrilltes Fleisch", "Hartkäse"])
        let plain = item("Ohne")
        #expect(InventoryShortlist.score(named, dish: "gegrilltes Fleisch", year: 2026) > InventoryShortlist.score(plain, dish: "gegrilltes Fleisch", year: 2026))
    }

    @Test("Schwach bewertete Flaschen werden nicht ausgeschlossen")
    func lowRatedIsNotExcluded() {
        let low = item("Schwach", rating: "2,0 von 5 (1 Bewertung)")
        let normal = item("Normal")
        #expect(InventoryShortlist.score(low, dish: "", year: 2026) == InventoryShortlist.score(normal, dish: "", year: 2026))
    }

    @Test("Die Auswahl ist stabil: gleicher Keller, gleiches Ergebnis")
    func deterministic() {
        let wines = cellar(120)
        #expect(InventoryShortlist.select(from: wines, dish: "Pizza") == InventoryShortlist.select(from: wines, dish: "Pizza"))
    }

    @Test("Die externe KI ist standardmässig nur der Rückfall")
    @MainActor
    func externalIsOptionalByDefault() {
        let defaults = UserDefaults(suiteName: "ShortlistTests-\(UUID().uuidString)")!
        #expect(AISettings(defaults: defaults).prefersExternal == false)
    }
}
