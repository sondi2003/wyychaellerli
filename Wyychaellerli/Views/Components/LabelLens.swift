import SwiftUI
import UIKit

/// Tipp aufs Etikettfoto öffnet das Bild gross in einem eigenen Fenster
/// (`LabelZoomView` – Fingerspreizen bis 6×, Doppeltipp 3×).
///
/// Ein Baustein für alle Stellen, an denen ein Etikett nur klein zu sehen ist: Katalogfoto
/// im Formular, Fotozeilen, Vorschläge prüfen, Katalog verwalten. Die Detailseite hat mit
/// `LabelPager` ihre eigene Fassung, die zwischen Vorder- und Rückseite blättert.
private struct LabelLensModifier: ViewModifier {

    let data: Data?
    let title: String
    let isCompact: Bool

    @State private var isZooming = false

    func body(content: Content) -> some View {
        // Keine sichtbare Lupe mehr (7.11.2026): Ein Tipp aufs Foto öffnet es gross, wie in der
        // Fotos-App. Die Lupe verdeckte bei Flaschenfotos den Namen der App unter der Flasche.
        content
            .contentShape(Rectangle())
            .onTapGesture { if image != nil { isZooming = true } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(tr("\(title) vergrössern"))
            .fullScreenCover(isPresented: $isZooming) {
                if let image {
                    LabelZoomView(pages: [LabelPage(title: title, image: image)], selection: 0)
                }
            }
    }

    private var image: UIImage? { data.flatMap(UIImage.init(data:)) }
}

extension View {

    /// Macht das Bild antippbar (Vollbild). Ohne Bilddaten passiert nichts. `compact` ist ohne
    /// Wirkung und bleibt nur, damit die Aufrufe nicht geändert werden müssen.
    func labelLens(_ data: Data?, title: String = tr("Etikett"), compact: Bool = false) -> some View {
        modifier(LabelLensModifier(data: data, title: title, isCompact: compact))
    }
}
