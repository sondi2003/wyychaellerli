import SwiftUI
import UIKit

/// Lupe auf einem Etikettfoto: Tipp öffnet das Bild gross in einem eigenen Fenster
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
        content
            .overlay(alignment: .bottomTrailing) {
                if let image = data.flatMap(UIImage.init(data:)) {
                    Button {
                        isZooming = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font((isCompact ? Font.caption2 : Font.subheadline).weight(.semibold))
                            .padding(isCompact ? 5 : 9)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(isCompact ? 2 : 10)
                    .accessibilityLabel(tr("\(title) vergrössern"))
                    .fullScreenCover(isPresented: $isZooming) {
                        LabelZoomView(pages: [LabelPage(title: title, image: image)], selection: 0)
                    }
                }
            }
    }
}

extension View {

    /// Legt eine Lupe unten rechts auf das Bild. Ohne Bilddaten passiert nichts.
    /// `compact` für kleine Vorschaubilder (rund 50 pt), sonst die grosse Fassung.
    func labelLens(_ data: Data?, title: String = tr("Etikett"), compact: Bool = false) -> some View {
        modifier(LabelLensModifier(data: data, title: title, isCompact: compact))
    }
}
