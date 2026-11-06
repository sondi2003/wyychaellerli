import CoreGraphics
import Foundation
import ImageIO

/// Schneidet aus einem Katalogfoto das Etikett heraus.
///
/// Die Fotos im Katalog zeigen die **ganze Flasche** vor einheitlichem Grund; das Etikett
/// macht davon etwa ein Fünftel aus. Im Keller soll nur das Etikett stehen – wie bei einem
/// selbst gescannten Foto. Das geht **auf dem Gerät** mit demselben Zuschnitt wie beim Scan
/// (`LabelTextRecognizer` + `LabelImageCropper`), nicht beim Import: Im Katalog bleibt so das
/// ganze Foto, nichts geht verloren, und eine bessere Erkennung gilt rückwirkend für alle
/// Einträge. Entschieden am 6.11.2026.
///
/// **Im Zweifel bleibt das Original.** Findet sich kein Text, deckt der Zuschnitt fast das
/// ganze Bild oder musste gedreht werden, liefert `croppedLabel` `nil` – dann steht weiter die
/// ganze Flasche da, nie ein falscher Ausschnitt.
enum CatalogLabelCrop {

    /// Ab diesem Anteil an der Bildfläche gilt der Zuschnitt als nicht gelungen: Auf einem
    /// Katalogfoto ist das Etikett höchstens ein Drittel der Fläche. Gemessen: 20–26 %.
    static let maximumAreaShare = 0.5

    /// Mindestens so viele Textzeilen braucht es, um dem Ergebnis zu trauen.
    static let minimumLines = 2

    /// Wasserzeichen und Logos der Quelle sind kein Etikett und dürfen den Zuschnitt nicht
    /// nach unten ziehen („vivino“ steht unter jeder Flasche).
    private static let ignoredWords = ["vivino"]

    /// Das Etikett als JPEG, oder `nil`, wenn nichts Sicheres gefunden wurde.
    static func croppedLabel(from data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let scan = ScanImage(cgImage: image, orientation: .up, original: image)
        guard let lines = try? await LabelTextRecognizer.recognizeLines(in: scan) else { return nil }
        let usable = lines.filter { line in
            let lowered = line.text.lowercased()
            return !ignoredWords.contains(where: lowered.contains)
        }
        guard usable.count >= minimumLines,
              let result = await LabelImageCropper.cropLabel(from: scan, textLines: usable),
              let cropped = CGImageSourceCreateWithData(result.jpegData as CFData, nil)
                .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return nil }
        let share = Double(cropped.width * cropped.height) / Double(image.width * image.height)
        return accepts(strategy: result.strategy, rotation: result.rotation, areaShare: share) ? result.jpegData : nil
    }

    /// Die Entscheidung allein, ohne Bild – damit sie sich testen lässt.
    static func accepts(strategy: LabelCropResult.Strategy, rotation: Int, areaShare: Double) -> Bool {
        strategy != .fullImage && rotation == 0 && areaShare <= maximumAreaShare
    }
}
