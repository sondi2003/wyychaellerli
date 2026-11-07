import UIKit
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

/// Katalogfoto: Der untere Rand blendet aus, damit das Wasserzeichen verschwindet.
@Suite("Katalogfoto: unten ausblenden")
struct CatalogPhotoFadeTests {

    @Test("Oben bleibt alles deckend, unten ist nichts mehr da")
    func ends() {
        #expect(CatalogPhotoFade.opacity(at: 0) == 1)
        #expect(CatalogPhotoFade.opacity(at: CatalogPhotoFade.fadeStart) == 1)
        #expect(CatalogPhotoFade.opacity(at: CatalogPhotoFade.fadeEnd) == 0)
        #expect(CatalogPhotoFade.opacity(at: 1) == 0)
    }

    @Test("Der Verlauf fällt gleichmässig")
    func monotone() {
        var last = 1.0
        for step in 0...100 {
            let value = CatalogPhotoFade.opacity(at: Double(step) / 100)
            #expect(value <= last + 1e-9)
            last = value
        }
    }

    @Test("Das Wasserzeichen (94–97 % der Höhe) liegt ganz im durchsichtigen Teil")
    func coversWatermark() {
        #expect(CatalogPhotoFade.opacity(at: 0.94) == 0)
        #expect(CatalogPhotoFade.opacity(at: 0.95) == 0)
        #expect(CatalogPhotoFade.opacity(at: 0.97) == 0)
    }

    @Test("Ein breites Foto mit Rand gilt als Flasche, sobald der Verlauf es bearbeitet hat")
    func wideCatalogPhotoIsBottleAfterFade() throws {
        // Echte Katalogfotos sind breit (schwarzer Rand), nicht schmal wie meine Demobilder.
        let size = CGSize(width: 745, height: 1026)
        let renderer = UIGraphicsImageRenderer(size: size)
        let wide = renderer.image { context in
            UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        let png = try #require(wide.pngData())
        let fadedData = try #require(CatalogPhotoFade.faded(from: png))
        let fadedImage = try #require(UIImage(data: fadedData))
        #expect(CatalogPhotoFade.isCatalogBottle(fadedImage))
        // Dasselbe Foto ohne Verlauf (JPEG vom Scan) bleibt ein Etikettfoto.
        let jpegData = try #require(wide.jpegData(compressionQuality: 0.9))
        let jpegImage = try #require(UIImage(data: jpegData))
        #expect(!CatalogPhotoFade.isCatalogBottle(jpegImage))
    }

    @Test("Nur schmale, hohe Fotos gelten als Flasche")
    func bottleDetection() {
        #expect(CatalogPhotoFade.isBottle(width: 163, height: 600))
        #expect(CatalogPhotoFade.isBottle(width: 440, height: 1650))
        #expect(!CatalogPhotoFade.isBottle(width: 226, height: 320))   // Etikettfoto
        #expect(!CatalogPhotoFade.isBottle(width: 1200, height: 900))
    }
}

@Suite("Miniatur: Etikett oder Flasche")
struct AdaptiveLabelImageTests {

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in }
    }

    @Test("Ein schmales, hohes Foto gilt als Flasche")
    func bottle() {
        let view = AdaptiveLabelImage(image: image(width: 163, height: 470), width: 44, height: 55)
        #expect(view.image.size.width / view.image.size.height < AdaptiveLabelImage.bottleAspectLimit)
    }

    @Test("Ein Etikettfoto bleibt unter der Grenze nicht hängen")
    func label() {
        let size = image(width: 226, height: 320).size
        #expect(size.width / size.height >= AdaptiveLabelImage.bottleAspectLimit)
    }
}

@Suite("Geteiltes Bild mit Namen der App")
struct SharedBrandingTests {

    private func faded(_ name: String) throws -> UIImage {
        let path = "/private/tmp/claude-501/-Users-richard-GitHub-wyychaellerli/0f527c51-90ec-407a-8859-4a38d1566c40/scratchpad/crop/\(name)"
        let data = try #require(FileManager.default.contents(atPath: path))
        let out = try #require(CatalogPhotoFade.faded(from: data))
        let image = UIImage(data: out)
        return try #require(image)
    }

    @Test("Ein Etikettfoto vom Scan bleibt unverändert")
    func scanPhotoUntouched() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 500)).image { _ in }
        let jpeg = UIImage(data: image.jpegData(compressionQuality: 0.9)!)!
        #expect(jpeg.brandedForSharing() === jpeg)
    }

    @Test("Eine Katalogflasche bekommt weissen Grund und den Namen, gleiche Grösse")
    func bottleBranded() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 900)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 900))
        }
        let sourcePNG = try #require(source.pngData())
        let png = try #require(CatalogPhotoFade.faded(from: sourcePNG))
        let decoded = UIImage(data: png)
        let bottle = try #require(decoded)
        let branded = bottle.brandedForSharing()
        #expect(branded.size == bottle.size)
        #expect(branded !== bottle)
        // Unten links (Verlauf) war durchsichtig, jetzt weiss und deckend.
        let cg = try #require(branded.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: -2, y: 0, width: cg.width, height: cg.height))
        #expect(pixel[3] == 255)
    }

    @Test("Vorführung: geteilte Bilder zum Ansehen ablegen")
    func writeSamples() throws {
        for name in ["enemigo.png", "riomistico.png"] {
            guard let image = try? faded(name) else { continue }
            let out = "/private/tmp/claude-501/-Users-richard-GitHub-wyychaellerli/0f527c51-90ec-407a-8859-4a38d1566c40/scratchpad/crop/shared-\(name)"
            try image.brandedForSharing().pngData()?.write(to: URL(fileURLWithPath: out))
        }
    }
}
