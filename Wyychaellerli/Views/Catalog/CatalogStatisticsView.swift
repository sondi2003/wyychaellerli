import SwiftUI

/// „Statistik“: der gemeinsame Katalog in Zahlen (`CatalogMosaicCard`).
///
/// Ein eigenes Blatt, aufgerufen über den Statistik-Knopf links oben im Keller – gegenüber
/// dem Zahnrad. Früher stand die Karte in den Einstellungen; dort suchte sie niemand.
///
/// Der Knopf ist immer da. Ist der Katalog noch klein (`CatalogOverview.minimumForDisplay`),
/// steht statt des Mosaiks ein ehrlicher Satz: Eine Karte mit zwölf Weinen aus drei Ländern
/// würde den Katalog kleiner machen, als er in Wirklichkeit ist.
struct CatalogStatisticsView: View {

    @Environment(CatalogCenter.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var overview: CatalogOverview?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let overview, overview.isWorthShowing {
                        CatalogMosaicCard(overview: overview)
                    } else if overview != nil {
                        ContentUnavailableView(
                            "Der Katalog wächst",
                            systemImage: "books.vertical",
                            description: Text("Sobald genug Weine im gemeinsamen Katalog liegen, siehst du hier, aus welchen Ländern sie kommen.")
                        )
                        .padding(.top, 40)
                    } else {
                        ProgressView().padding(.top, 60)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .appTitle(tr("Statistik"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            // Wer die Karte aufruft, soll den aktuellen Stand sehen: nach 30 Sekunden neu laden.
            .task { await catalog.refreshDirectory(maxAge: 30) }
            // Neu rechnen, wenn die Liste neu geladen wird oder die Sprache wechselt (Ländernamen).
            .task(id: "\(catalog.directoryVersion)-\(language.rawValue)") {
                let entries = catalog.directory.entries
                let locale = language.locale
                overview = await Task.detached { CatalogOverview(entries: entries, locale: locale) }.value
            }
        }
    }
}

#Preview {
    CatalogStatisticsView()
        .environment(CatalogCenter())
}
