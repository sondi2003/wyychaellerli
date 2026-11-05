import Foundation
import Testing
@testable import Wyychaellerli

/// Ergänzungen: Ein Wein liefert dem Katalog nur, was dort fehlt – nie eine Änderung.
struct SupplementTests {

    private let code = "7612345678900"

    private func entry(grape: String = "", region: String = "", alcohol: Double = 0, gtins: [String] = []) -> CatalogWine {
        CatalogWine(
            id: "wine_x", name: "Pinot Noir", producer: "Cicero", vintage: 2022, grape: grape,
            region: region, country: "Schweiz", typeRaw: "red", alcoholPercent: alcohol,
            source: "import", gtins: gtins
        )
    }

    private func draft(_ entry: CatalogWine, grape: String = "", region: String = "", alcohol: Double = 0,
                       barcode: String = "", image: Data? = nil, hasImage: Bool = true) -> SubmissionDraft? {
        SubmissionDraft(
            supplementing: entry, producer: "Anderer Name", grape: grape, region: region,
            country: "Frankreich", alcoholPercent: alcohol, barcode: barcode, labelImageData: image,
            entryHasImage: hasImage, wineUUID: "u"
        )
    }

    @Test("Leere Felder des Eintrags werden gefüllt, vorhandene bleiben")
    func fillsOnlyGaps() throws {
        let result = try #require(draft(entry(), grape: "Pinot Noir", region: "Bündner Herrschaft", alcohol: 13))
        #expect(result.grape == "Pinot Noir")
        #expect(result.region == "Bündner Herrschaft")
        #expect(result.alcoholPercent == 13)
        // Produzent und Land standen schon im Katalog.
        #expect(result.producer == "Cicero")
        #expect(result.country == "Schweiz")
        #expect(result.catalogKey == "wine_x")
    }

    @Test("Ohne etwas Neues gibt es keine Ergänzung")
    func nothingNew() {
        #expect(draft(entry(grape: "Pinot Noir"), grape: "Merlot") == nil)
        #expect(draft(entry(gtins: [code]), barcode: code) == nil)
    }

    @Test("Ein neuer Strichcode ist eine Ergänzung")
    func newBarcode() throws {
        let result = try #require(draft(entry(gtins: []), barcode: code))
        #expect(result.barcode == code)
    }

    @Test("Das Foto geht nur mit, wenn der Eintrag keines hat")
    func imageOnlyWhenMissing() throws {
        let photo = Data([1, 2, 3])
        #expect(draft(entry(), image: photo, hasImage: true) == nil)
        let result = try #require(draft(entry(), image: photo, hasImage: false))
        #expect(result.labelImageData == photo)
    }

    @Test("Der Admin erkennt eine reine Ergänzung an den Zusätzen")
    func additionsAreListed() {
        let existing = entry()
        var proposed = existing
        proposed.grape = "Pinot Noir"
        proposed.gtins = [code]
        #expect(proposed.additions(over: existing) == [tr("Rebsorte"), tr("Strichcode")])
    }

    @Test("Wer Vorhandenes ändert, liefert keine Ergänzung")
    func changeIsNoAddition() {
        let existing = entry(grape: "Pinot Noir")
        var proposed = existing
        proposed.grape = "Merlot"
        #expect(proposed.additions(over: existing) == nil)
        proposed = existing
        proposed.vintage = 2023
        #expect(proposed.additions(over: existing) == nil)
    }

    @Test("Mehrere Vorschläge zum selben Wein ergänzen sich")
    func suggestionsComplementEachOther() {
        func submission(_ id: String, grape: String, region: String) -> CatalogSubmission {
            CatalogSubmission(
                id: id, name: "Pinot Noir", producer: "Cicero", vintage: 2022, grape: grape, region: region,
                country: "Schweiz", typeRaw: "red", alcoholPercent: 0, catalogKey: "wine_x", wineUUID: "",
                status: .pending, createdAt: nil
            )
        }
        let group = SubmissionGroup(id: "wine_x", items: [submission("1", grape: "", region: "Wallis"), submission("2", grape: "Pinot Noir", region: "")])
        #expect(group.asCatalogWine.grape == "Pinot Noir")
        #expect(group.asCatalogWine.region == "Wallis")
    }

    @Test("Ein Treffer wird gefragt, ausser der Strichcode bestätigt ihn")
    @MainActor
    func candidateIsAsked() {
        let model = WineFormViewModel(mode: .add)
        model.name = "Pinot Noir"
        model.offerCatalogEntry(entry())
        #expect(model.catalogCandidate != nil)
        #expect(model.catalogMatch == nil)
        model.declineCatalogCandidate()
        #expect(model.catalogCandidate == nil)
        // Abgelehnt: derselbe Treffer kommt nicht wieder.
        model.offerCatalogEntry(entry())
        #expect(model.catalogCandidate == nil)

        let sure = WineFormViewModel(mode: .add)
        sure.barcode = code
        sure.offerCatalogEntry(entry(gtins: [code]))
        #expect(sure.catalogCandidate == nil)
        #expect(sure.catalogMatch != nil)
    }
}
