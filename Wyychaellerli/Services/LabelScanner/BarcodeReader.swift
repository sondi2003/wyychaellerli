import CoreGraphics
import Foundation
import OSLog
import Vision

/// Liest den Strichcode (EAN-13, EAN-8) aus den Etikettfotos – auf dem Gerät, ohne Netz.
///
/// Er steht meist auf der Rückseite und kommt aus denselben Fotos wie der Text: Der Scan
/// verlangt keinen zusätzlichen Schritt. Eine Amerika-Flasche mit UPC-A liest die Kamera
/// als EAN-13 mit führender Null; `Barcode.normalized` prüft die Prüfziffer.
enum BarcodeReader {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Barcode")

    /// Der erste gültige Code aus den Bildern, sonst leer. Rückseite zuerst übergeben.
    static func read(in images: [ScanImage]) async -> String {
        guard !images.isEmpty else { return "" }
        return await Task.detached(priority: .userInitiated) {
            for image in images {
                // Erst die verkleinerte Fassung (schnell), dann das volle Foto: Auf einer
                // schmalen Flasche ist der Code klein, und erst die volle Auflösung trägt ihn.
                for candidate in [image.cgImage, image.original].compactMap({ $0 }) {
                    if let code = detect(in: candidate, orientation: image.orientation) {
                        logger.info("Strichcode erkannt: \(code, privacy: .public)")
                        return code
                    }
                }
            }
            return ""
        }.value
    }

    private static func detect(in image: CGImage, orientation: CGImagePropertyOrientation) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8]
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            logger.info("Strichcode-Suche fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        for observation in request.results ?? [] {
            let code = Barcode.normalized(observation.payloadStringValue ?? "")
            if !code.isEmpty { return code }
        }
        return nil
    }
}
