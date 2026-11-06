import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Lässt ein Katalogfoto unten **sanft ausblenden**, damit das Wasserzeichen verschwindet.
///
/// Die Fotos im Katalog zeigen die ganze Flasche; unten steht – oft auf dem Flaschenfuss –
/// das „vivino“-Logo, bei allen Fotos an fast derselben Stelle (rund 94–97 % der Höhe). Ein
/// Verlauf in die Durchsichtigkeit deckt es ab, ohne es suchen zu müssen: Die Flasche steht
/// „im Nebel“, auf hellem wie auf dunklem Grund. Der erste Weg (Text erkennen und darüber
/// abschneiden) scheiterte an gesperrter, heller Schrift auf Glas. Entschieden am 7.11.2026.
///
/// Gerechnet wird **auf dem Gerät** in die Bilddaten (PNG mit Alphakanal): Im Katalog bleibt das
/// Original, und der Verlauf stimmt überall, wo das Foto gezeigt wird, auch im Vollbild.
///
/// Gerechnet wird **nur an Katalogfotos** (`WineFormView.loadCatalogImage`), nie an Fotos vom Scan.
/// Früher galten nur schmale Bilder als Flasche – echte Katalogfotos haben aber breite Ränder
/// (schwarz oder weiss) und fielen durch; deshalb entscheidet nicht das Seitenverhältnis allein.
enum CatalogPhotoFade {

    /// Schmaler als das gilt als Flaschenfoto (wie `AdaptiveLabelImage.bottleAspectLimit`).
    static let bottleAspectLimit = 0.55

    /// Von hier (Anteil der Höhe, von oben) beginnt der Verlauf …
    static let fadeStart = 0.86
    /// … und hier ist das Bild ganz durchsichtig. Das Logo liegt darunter.
    static let fadeEnd = 0.94

    /// Deckkraft einer Zeile, `position` = Anteil der Höhe von oben (0…1).
    static func opacity(at position: Double) -> Double {
        if position <= fadeStart { return 1 }
        if position >= fadeEnd { return 0 }
        let t = (position - fadeStart) / (fadeEnd - fadeStart)
        // Weiche Kurve: langsam beginnen, langsam enden.
        return 1 - (t * t * (3 - 2 * t))
    }

    static func isBottle(width: Int, height: Int) -> Bool {
        height > 0 && Double(width) / Double(height) < bottleAspectLimit
    }

    /// Ist das ein Katalogfoto mit Flasche? Schmal und hoch – oder mit Alphakanal: Der Verlauf
    /// schreibt ein PNG mit Durchsichtigkeit, Fotos vom Scan (JPEG zugeschnitten) haben keine.
    static func isCatalogBottle(_ image: UIImage) -> Bool {
        if isBottle(width: Int(image.size.width), height: Int(image.size.height)) { return true }
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        switch alpha {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Das Foto mit Verlauf (PNG), oder `nil`, wenn es sich nicht lesen lässt.
    static func faded(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        // Premultipliert: alle vier Kanäle mit derselben Deckkraft multiplizieren.
        for row in 0..<h {
            let factor = opacity(at: (Double(row) + 0.5) / Double(h))
            guard factor < 1 else { continue }
            for column in 0..<w {
                let i = (row * w + column) * 4
                for channel in 0..<4 { pixels[i + channel] = UInt8((Double(pixels[i + channel]) * factor).rounded()) }
            }
        }
        let output: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        guard let output else { return nil }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        return CGImageDestinationFinalize(destination) ? encoded as Data : nil
    }
}
