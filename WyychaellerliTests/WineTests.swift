import Foundation
import Testing
@testable import Wyychaellerli

/// Trinkreife, Bestand und Darstellung eines Weins.
@MainActor
struct WineTests {

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    @Test("Ohne Trinkfenster ist die Reife unbekannt")
    func unknownMaturity() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context)
        #expect(wine.maturity == .unknown)
        #expect(wine.drinkWindowText.isEmpty)
        #expect(!wine.needsDrinkingSoon)
    }

    @Test("Reifezustand über die Jahre")
    func maturity() {
        let context = TestStack.makeContext()

        let young = TestStack.makeWine(in: context, name: "Jung", drinkFrom: currentYear + 2, drinkTo: currentYear + 6)
        #expect(young.maturity == .tooYoung)
        #expect(!young.needsDrinkingSoon)

        let ready = TestStack.makeWine(in: context, name: "Reif", drinkFrom: currentYear - 1, drinkTo: currentYear + 3)
        #expect(ready.maturity == .ready)
        #expect(!ready.needsDrinkingSoon)

        // Letztes Jahr des Fensters: jetzt trinken.
        let soon = TestStack.makeWine(in: context, name: "Bald", drinkFrom: currentYear - 2, drinkTo: currentYear)
        #expect(soon.maturity == .drinkSoon)
        #expect(soon.needsDrinkingSoon)

        let past = TestStack.makeWine(in: context, name: "Vorbei", drinkFrom: currentYear - 5, drinkTo: currentYear - 1)
        #expect(past.maturity == .pastPeak)
        #expect(past.needsDrinkingSoon)
    }

    @Test("Trinkfenster als Text")
    func windowText() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, drinkFrom: 2022, drinkTo: 2028)
        #expect(wine.drinkWindowText == "2022–2028")
    }

    @Test("Bestand fällt nie unter null")
    func stock() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, quantity: 1)

        wine.consumeBottle()
        #expect(wine.quantity == 0)
        #expect(wine.isOutOfStock)

        // Ein zweites Abbuchen darf nicht ins Minus laufen.
        wine.consumeBottle()
        #expect(wine.quantity == 0)

        wine.addBottle()
        #expect(wine.quantity == 1)
        #expect(!wine.isOutOfStock)
    }

    @Test("Kurzform für Listen lässt Leeres weg")
    func subtitle() {
        let context = TestStack.makeContext()
        let full = TestStack.makeWine(in: context, vintage: 2019, grape: "Grenache", country: "Frankreich")
        #expect(full.subtitle.contains("2019"))
        #expect(full.subtitle.contains("Grenache"))
        // Ohne Region tritt das Land an ihre Stelle.
        #expect(full.subtitle.contains("Frankreich"))

        let sparse = TestStack.makeWine(in: context, vintage: 0, grape: "", country: "")
        #expect(!sparse.subtitle.contains("·"))
    }

    @Test("Verortete Flaschen und offene Plätze")
    func placement() {
        let context = TestStack.makeContext()
        let rack = Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
        let wine = TestStack.makeWine(in: context, quantity: 3)

        #expect(wine.unplacedCount == 3)
        #expect(wine.canPlaceAnotherBottle)

        Slot.place(wine, at: Position(row: 0, column: 0), in: rack, context: context)
        Slot.place(wine, at: Position(row: 0, column: 1), in: rack, context: context)
        Slot.place(wine, at: Position(row: 0, column: 2), in: rack, context: context)

        #expect(wine.placedCount == 3)
        #expect(wine.unplacedCount == 0)
        // Mehr Plätze als Flaschen darf es nie geben.
        #expect(!wine.canPlaceAnotherBottle)
    }

    @Test("Speiseempfehlungen als Liste")
    func pairings() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, foodPairings: ["Lamm", "Käse"])
        #expect(wine.foodPairings == ["Lamm", "Käse"])

        wine.foodPairings = []
        #expect(wine.foodPairings.isEmpty)
    }
}
