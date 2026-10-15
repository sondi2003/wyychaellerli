import SwiftUI
import UIKit

/// Eine Etikettseite für den Blätterbereich der Detailseite.
struct LabelPage: Identifiable, Hashable {
    let title: String
    let image: UIImage
    var id: String { title }
}

/// Zeigt die Etikettfotos und lässt zwischen Vorder- und Rückseite wischen.
///
/// Bei nur einer Seite verhält sich die Ansicht wie ein einzelnes Bild: keine Punkte,
/// keine Beschriftung, kein Hinweis auf eine zweite Seite, die es nicht gibt.
struct LabelPager: View {

    let pages: [LabelPage]
    let wineName: String

    @State private var selection = 0
    @State private var isZooming = false

    private var hasMultiplePages: Bool { pages.count > 1 }

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Image(uiImage: page.image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                        // Die Lupe sitzt auf dem Bild, nicht auf dem Rahmen – so ist klar,
                        // dass sie zu diesem Foto gehört.
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                isZooming = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(9)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .accessibilityLabel("\(page.title) vergrössern")
                        }
                        // Rand, damit der Schatten nicht am Rahmen abgeschnitten wird.
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                        .tag(index)
                        .accessibilityLabel("\(page.title) des Etiketts von \(wineName)")
                }
            }
            // Eigene Anzeige statt der Systempunkte: Die sind auf hellem Grund kaum sichtbar.
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            .fullScreenCover(isPresented: $isZooming) {
                LabelZoomView(pages: pages, selection: selection)
            }

            if hasMultiplePages {
                HStack(spacing: 8) {
                    Text(pages[min(selection, pages.count - 1)].title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.identity)
                    HStack(spacing: 6) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selection ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: pages.count) { _, count in
            // Wird eine Seite entfernt, darf die Auswahl nicht ins Leere zeigen.
            selection = min(selection, max(count - 1, 0))
        }
    }
}

#Preview {
    LabelPager(
        pages: [
            LabelPage(title: tr("Vorderseite"), image: UIImage(systemName: "tag.fill")!),
            LabelPage(title: tr("Rückseite"), image: UIImage(systemName: "text.alignleft")!)
        ],
        wineName: "La Pinède"
    )
}
