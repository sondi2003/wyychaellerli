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
    /// Die Liste, aus der die Zahlen gerechnet sind: Quelle der Weinliste unter dem Mosaik.
    @State private var entries: [CatalogWine] = []
    @State private var selection: CatalogSelection?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let overview, overview.isWorthShowing {
                    CatalogMosaicCard(overview: overview, selectedID: selection?.id) { tapped in
                        // Dieselbe Kachel noch einmal: Wahl aufheben.
                        selection = (selection == tapped) ? nil : tapped
                    }
                    .padding([.horizontal, .top])
                    .padding(.bottom, 8)
                    if let selection {
                        CatalogSelectionList(selection: selection, entries: entries)
                    } else {
                        Text("Tippe auf ein Land, um seine Weine zu sehen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 12)
                    }
                } else if overview != nil {
                    ContentUnavailableView(
                        "Der Katalog wächst",
                        systemImage: "books.vertical",
                        description: Text("Sobald genug Weine im gemeinsamen Katalog liegen, siehst du hier, aus welchen Ländern sie kommen.")
                    )
                    .padding(.top, 40)
                    Spacer(minLength: 0)
                } else {
                    ProgressView().padding(.top, 60)
                    Spacer(minLength: 0)
                }
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
                let current = catalog.directory.entries
                let locale = language.locale
                entries = current
                let fresh = await Task.detached { CatalogOverview(entries: current, locale: locale) }.value
                overview = fresh
                // Die Wahl bleibt beim Land, trägt aber die aktuelle Zahl; ein Land, das es nicht mehr gibt, fällt weg.
                if let chosen = selection {
                    selection = fresh.countries.first { $0.id == chosen.id }.map(CatalogSelection.init(country:))
                }
            }
        }
    }
}

#Preview {
    CatalogStatisticsView()
        .environment(CatalogCenter())
}
