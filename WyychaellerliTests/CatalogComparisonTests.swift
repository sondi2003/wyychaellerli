import Foundation
import Testing
@testable import Wyychaellerli

/// Der Abgleich eines Weins im Keller mit dem Katalog: Was bietet der Katalog an, und wann
/// meldet sich ein Wein wieder?
struct CatalogComparisonTests {

    private func entry(
        name: String = "Unique", producer: String = "Donatsch", grape: String = "Pinot Noir",
        region: String = "Graubünden", country: String = "Schweiz", type: String = "red",
        alcohol: Double = 13.5, food: [String] = ["Wild"]
    ) -> CatalogWine {
        CatalogWine(
            id: "k", name: name, producer: producer, vintage: 2021, grape: grape, region: region,
            country: country, typeRaw: type, alcoholPercent: alcohol, source: "admin", foodPairings: food)
    }

    private func mine(
        name: String = "Unique", producer: String = "Donatsch", grape: String = "Pinot Noir",
        region: String = "Graubünden", country: String = "Schweiz", type: WineType = .red,
        alcohol: Double = 13.5, food: String = "Wild"
    ) -> WineDetails {
        WineDetails(
            name: name, producer: producer, grape: grape, region: region, country: country,
            type: type, alcoholPercent: alcohol, foodPairings: food)
    }

    @Test("Gleiche Angaben: nichts anzubieten, auch bei anderer Gross- und Kleinschreibung")
    func sameIsQuiet() {
        #expect(CatalogComparison.differences(entry: entry(), mine: mine()).isEmpty)
        #expect(CatalogComparison.differences(entry: entry(region: "GRAUBÜNDEN"), mine: mine()).isEmpty)
    }

    @Test("Leere Felder des Nutzers sind Ergänzungen, abweichende Angaben Unterschiede")
    func fillableAndDifferent() {
        let rows = CatalogComparison.differences(
            entry: entry(grape: "Pinot Noir", region: "Bündner Herrschaft"),
            mine: mine(grape: "", region: "Graubünden"))
        #expect(rows.first { $0.field == .grape }?.kind == .fillable)
        #expect(rows.first { $0.field == .region }?.kind == .different)
        #expect(rows.count == 2)
    }

    @Test("Was der Katalog nicht kennt, bleibt: leere Katalogfelder löschen nichts")
    func catalogEmptyChangesNothing() {
        let rows = CatalogComparison.differences(
            entry: entry(grape: "", alcohol: 0, food: []), mine: mine(grape: "Merlot", alcohol: 14, food: "Käse"))
        #expect(rows.isEmpty)
    }

    @Test("Weinart und Alkohol: Abweichung wird gezeigt, Kleinigkeiten nicht")
    func typeAndAlcohol() {
        let rows = CatalogComparison.differences(entry: entry(type: "white", alcohol: 13.0), mine: mine(alcohol: 13.5))
        #expect(rows.map(\.field).sorted { "\($0)" < "\($1)" } == [.alcohol, .type].sorted { "\($0)" < "\($1)" })
        #expect(CatalogComparison.differences(entry: entry(alcohol: 13.52), mine: mine(alcohol: 13.5)).isEmpty)
    }

    @Test("Übernehmen schreibt nur das gewählte Feld")
    func applyOne() {
        var details = mine(grape: "", region: "Graubünden")
        CatalogComparison.apply(.grape, from: entry(), to: &details)
        #expect(details.grape == "Pinot Noir")
        #expect(details.region == "Graubünden")
    }

    @Test("Der Fingerabdruck ändert sich mit den Angaben, nicht mit der Schreibweise")
    func fingerprint() {
        #expect(entry().fingerprint == entry(region: "graubünden").fingerprint)
        #expect(entry().fingerprint != entry(grape: "Merlot").fingerprint)
        #expect(entry().fingerprint != entry(food: ["Wild", "Käse"]).fingerprint)
    }

    @Test("Beim Bearbeiten meldet sich ein Wein nur bei Neuem und nur, wenn etwas zu übernehmen ist")
    @MainActor func offerRules() throws {
        let context = TestStack.makeContext()
        let wine = Wine.create(
            in: context, cellar: Cellar.findOrCreateOwn(in: context), name: "Unique", producer: "Donatsch",
            vintage: 2021, grape: "", type: .red)
        let model = WineFormViewModel(mode: .edit(wine))
        model.editCatalogEntry = entry(grape: "Pinot Noir")
        #expect(model.offersCatalogEntry)

        model.takeCatalogFields(fillOnly: true)
        #expect(model.grape == "Pinot Noir")
        #expect(!model.offersCatalogEntry)   // nichts mehr zu übernehmen

        wine.catalogSeen = entry(grape: "Pinot Noir").fingerprint
        model.editCatalogEntry = entry(grape: "Pinot Noir")
        model.grape = ""
        #expect(!model.offersCatalogEntry)   // schon gesehen und unverändert
        model.editCatalogEntry = entry(grape: "Merlot")
        #expect(model.offersCatalogEntry)    // der Admin hat geändert
    }
}
