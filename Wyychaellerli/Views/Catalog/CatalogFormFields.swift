import SwiftUI
import UIKit

/// Die Felder eines Katalogeintrags – gleich beim Prüfen eines Vorschlags und beim
/// Bearbeiten im Katalog.
///
/// Jedes Feld hat links eine feste Beschriftung. Ein blosser Platzhalter verschwindet,
/// sobald etwas drinsteht – dann stand „2026“ oder „0“ da ohne Hinweis, wofür.
struct CatalogFormFields: View {

    @Binding var entry: CatalogWine

    var body: some View {
        Section("Wein") {
            field("Name", text: $entry.name)
            field("Produzent", text: $entry.producer)
            LabeledContent("Jahrgang") {
                TextField("Jahrgang", value: $entry.vintage, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Weinart", selection: $entry.typeRaw) {
                ForEach(WineType.allCases) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            }
        }

        Section("Herkunft") {
            field("Rebsorte", text: $entry.grape)
            field("Region", text: $entry.region)
            field("Land", text: $entry.country)
            LabeledContent("Alkohol (Prozent)") {
                TextField("Alkohol (Prozent)", value: $entry.alcoholPercent, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Bereitet ein neues Etikettfoto für den Katalog auf: derselbe Zuschnitt wie beim Scan.
/// Findet der Zuschnitt nichts, geht das verkleinerte Foto.
enum CatalogLabelPhoto {
    static func prepare(_ image: UIImage) async -> Data? {
        let resized = image.resizedForRecognition(maxDimension: 2400)
        if let cgImage = resized.cgImage {
            let scan = ScanImage(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(resized.imageOrientation),
                original: image.cgImage
            )
            if let lines = try? await LabelTextRecognizer.recognizeLines(in: scan),
               let crop = await LabelImageCropper.cropLabel(from: scan, textLines: lines) {
                return crop.jpegData
            }
        }
        return image.resizedForRecognition(maxDimension: 1200).jpegData(compressionQuality: 0.8)
    }
}
