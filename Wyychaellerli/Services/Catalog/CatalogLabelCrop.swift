import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Bereitet ein Katalogfoto für die Anzeige auf: **VIVINO-Wasserzeichen unten abschneiden**.
/// Das Bild selbst wird sonst nicht verändert.
///
/// Die Fotos im Katalog zeigen die ganze Flasche vor einheitlichem Grund; unten steht klein
/// „vivino“. Es ist der unterste Text im Bild. Die App sucht ihn mit der Texterkennung des
/// Scans (`LabelTextRecognizer`) und schneidet **knapp darüber** ab: Die Flasche bleibt ganz, das
/// Wasserzeichen und der leere Boden darunter fallen weg. (Ein erster Entwurf schnitt das
/// Etikett selbst heraus – das scheiterte an Bildmotiven, Rändern und runden Etiketten.
/// Entschieden am 6.11.2026.)
///
/// Gerechnet wird **auf dem Gerät**, nicht beim Import: Im Katalog bleibt das ganze Foto, und
/// eine bessere Regel gilt rückwirkend.
///
/// **Im Zweifel bleibt das Original.** Wird das Wasserzeichen nicht gefunden – etwa bei einem
/// Foto, das jemand selbst vorgeschlagen hat –, passiert nichts.
enum CatalogLabelCrop {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Catalog")

    /// Abstand zwischen Wasserzeichen und Schnitt, in Anteilen der Bildhöhe.
    static let margin = 0.012

    /// Das Wasserzeichen steht ganz unten. Eine Zeile „vivino“ weiter oben ist keines, sondern
    /// vielleicht ein Wort auf dem Etikett („Vino“) – dann wird nicht geschnitten.
    static let watermarkZone = 0.2

    /// Katalogfotos sind klein (gemessen: 163×600 px). Die Texterkennung findet darin das kleine
    /// Logo nicht, deshalb wird das Bild vor dem Lesen auf diese längste Kante vergrössert.
    static let recognitionLongestEdge = 2000

    /// Ist das die Wasserzeichen-Zeile? Mit Spielraum für Lesefehler („VIVI“, „vivn“).
    static func isWatermark(_ text: String) -> Bool {
        let letters = text.lowercased().filter(\.isLetter)
        guard (3...9).contains(letters.count) else { return false }
        return editDistance(letters, "vivino") <= 3
    }

    /// Das Foto ohne Wasserzeichen unten (PNG mit Transparenz, sonst JPEG), oder `nil`.
    static func cleaned(from data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let trimmed = await trimmedWatermark(from: image) else { return nil }
        return encoded(trimmed, asPNG: hasAlpha(trimmed))
    }

    /// Das Bild ohne den Streifen mit dem Wasserzeichen, oder `nil`.
    private static func trimmedWatermark(from image: CGImage) async -> CGImage? {
        // Gelesen wird eine vergrösserte Fassung, geschnitten wird das Original: Die Koordinaten
        // der Erkennung sind Anteile und gelten für beide.
        let enlarged = upscaled(image)
        let scan = ScanImage(cgImage: enlarged, orientation: .up, original: enlarged)
        guard let lines = try? await LabelTextRecognizer.recognizeLines(in: scan) else { return nil }
        logger.info("Katalogfoto \(image.width)x\(image.height): \(lines.count) Zeilen: \(lines.map(\.text).joined(separator: " | "), privacy: .public)")

        // Die unterste Zeile, die wie das Wasserzeichen aussieht und ganz unten steht.
        let watermark = lines
            .filter { isWatermark($0.text) && $0.boundingBox.midY <= watermarkZone }
            .min { $0.boundingBox.minY < $1.boundingBox.minY }
        guard let watermark else { return nil }

        let kept = keptShare(watermarkTop: watermark.boundingBox.maxY)
        logger.info("Wasserzeichen „\(watermark.text, privacy: .public)“ gefunden, Flasche bleibt zu \(kept)")
        guard accepts(keptShare: kept) else { return nil }
        let rows = Int((Double(image.height) * kept).rounded())
        return image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: rows))
    }

    // MARK: Regeln (ohne Bild, damit sie sich testen lassen)

    /// Wie viel von der Bildhöhe stehen bleibt, von oben gerechnet. `watermarkTop` ist die
    /// Oberkante der Wasserzeichen-Zeile in Vision-Koordinaten (0 = unten, 1 = oben).
    static func keptShare(watermarkTop: Double) -> Double {
        1 - (watermarkTop + margin)
    }

    /// Es muss etwas wegfallen, aber nur ein schmaler Streifen unten: Bliebe weniger als
    /// 80 % stehen, wurde etwas anderes als das Wasserzeichen gefunden.
    static func accepts(keptShare: Double) -> Bool {
        keptShare >= 1 - watermarkZone && keptShare < 0.995
    }

    // MARK: Bild

    private static func upscaled(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest < recognitionLongestEdge else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.scale = Float(recognitionLongestEdge) / Float(longest)
        filter.aspectRatio = 1
        guard let output = filter.outputImage,
              let result = CIContext().createCGImage(output, from: output.extent) else { return image }
        return result
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func encoded(_ image: CGImage, asPNG: Bool) -> Data? {
        let output = NSMutableData()
        let type = asPNG ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = asPNG ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
