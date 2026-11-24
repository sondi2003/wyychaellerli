import SwiftUI

/// „Statistik“: der gemeinsame Katalog in Zahlen (`CatalogCountryGrid`).
///
/// Ein eigenes Blatt, aufgerufen über den Statistik-Knopf links oben im Keller – gegenüber
/// dem Zahnrad. Früher stand die Karte in den Einstellungen; dort suchte sie niemand.
///
/// Der Knopf ist immer da. Ist der Katalog noch klein (`CatalogOverview.minimumForDisplay`),
/// steht statt des Rasters ein ehrlicher Satz: Eine Karte mit zwölf Weinen aus drei Ländern
/// würde den Katalog kleiner machen, als er in Wirklichkeit ist.
struct CatalogStatisticsView: View {

    /// Der Umschalter „Mein Keller / Katalog“ aus `StatisticsView`, oben im Blatt.
    var header: AnyView? = nil

    @Environment(CatalogCenter.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var overview: CatalogOverview?
    /// Die Liste, aus der die Zahlen gerechnet sind: Quelle der Weinliste im Blatt.
    @State private var entries: [CatalogWine] = []
    @State private var selection: CatalogSelection?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let header { header }
                if let overview, overview.isWorthShowing {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                CatalogCountryGrid(overview: overview, selectedID: selection?.id) { tapped in
                                    // Dieselbe Kachel noch einmal: Wahl aufheben.
                                    selection = (selection == tapped) ? nil : tapped
                                }
                                if selection == nil {
                                    Text("Tippe auf ein Land, um seine Weine zu sehen.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                            .padding([.horizontal, .top])
                            // Mit offenem Blatt Platz darunter lassen, damit auch die unterste Reihe nach oben rutschen kann.
                            .padding(.bottom, selection == nil ? 24 : 360)
                        }
                        // Die gewählte Kachel soll nicht unter dem Blatt verschwinden.
                        .onChange(of: selection?.id) { _, id in
                            guard let id else { return }
                            withAnimation { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.25)) }
                        }
                    }
                } else if overview != nil {
                    EmptyState(title: "Der Katalog wächst", symbol: "books.vertical",
                               message: "Sobald genug Weine im gemeinsamen Katalog liegen, siehst du hier, aus welchen Ländern sie kommen.",
                               fillsScreen: false)
                    .padding(.top, 40)
                    Spacer(minLength: 0)
                } else {
                    ProgressView().padding(.top, 60)
                    Spacer(minLength: 0)
                }
            }
            .background(Color(.systemGroupedBackground))
            // Die Weine des Landes in einem Blatt: erst halb hoch, das Raster bleibt oben bedienbar;
            // hochziehen für die ganze Liste, nach unten wischen schliesst es.
            .sheet(isPresented: Binding(
                get: { selection != nil },
                set: { if !$0 { selection = nil } }
            )) {
                if let selection {
                    CatalogSelectionList(selection: selection, entries: entries)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            }
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
