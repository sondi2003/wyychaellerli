import SwiftUI
import CoreData
import TipKit

/// Tab 1: Liste aller Weine mit Bestand, Schnell-Abbuchung und Hinzufügen.
struct CellarView: View {

    private let consumeTip = ConsumeTip()
    private let scanOptionsTip = ScanOptionsTip()

    @Environment(\.managedObjectContext) private var context
    @Environment(\.openSettings) private var openSettings
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
        animation: .default
    ) private var fetchedWines: FetchedResults<Wine>
    @State private var viewModel = CellarViewModel()
    @State private var isShowingFilters = false
    @State private var isShowingStatistics = false
    /// Wein, der gerade bewertet wird – nach dem Austrinken der letzten Flasche.
    @State private var wineToRate: Wine?
    /// Wein, dessen Löschen noch bestätigt werden muss. Löschen ist endgültig und geht
    /// über iCloud auf alle Geräte – deshalb nie mit einem einzigen Wisch.
    @State private var wineToDelete: Wine?

    /// FetchedResults als Array, damit Filter und Zusammenfassung damit rechnen können.
    private var wines: [Wine] { Array(fetchedWines) }

    var body: some View {
        NavigationStack {
            // Getrennt, weil die lange Modifier-Kette den Typprüfer sonst überfordert.
            rootContent
                .confirmationDialog(
                    "Wein löschen?",
                    isPresented: Binding(
                        get: { wineToDelete != nil },
                        set: { if !$0 { wineToDelete = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: wineToDelete
                ) { wine in
                    Button("Endgültig löschen", role: .destructive) {
                        viewModel.delete(wine, in: context)
                        wineToDelete = nil
                    }
                    Button("Abbrechen", role: .cancel) { wineToDelete = nil }
                } message: { wine in
                    Text("„\(wine.nameWithVintage)“ wird mit Etikett, Bewertungen und Regalplatz entfernt – auch auf den anderen Geräten. Zum Aufbewahren lieber archivieren.")
                }
        }
    }

    private var rootContent: some View {
            Group {
                if wines.isEmpty {
                    emptyCellar
                } else {
                    wineList
                }
            }
            .appTitle(tr("Wyychällerli"))
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingStatistics) {
                CatalogStatisticsView()
            }
            .sheet(isPresented: $isShowingFilters) {
                CellarFilterSheet(viewModel: viewModel, countries: viewModel.countryOptions(in: wines))
            }
            // Der Tipp zum langen Drücken auf den Scan-Knopf kommt erst mit dem ersten Wein.
            .task(id: wines.isEmpty) { ScanOptionsTip.hasWines = !wines.isEmpty }
            // Fest unter dem Titel: Ohne Systemleiste setzt iOS 26 die Suche sonst nach unten,
            // wo sie unter der eigenen Leiste (`BrandTabBar`) verschwindet.
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name, Rebsorte, Region, Jahrgang"
            )
            .sheet(item: $viewModel.addMode) { mode in
                WineFormView(mode: .add, startWithScanner: mode == .scan)
            }
            .sheet(item: $viewModel.wineToEdit) { wine in
                WineFormView(mode: .edit(wine))
            }
            .confirmationDialog(
                "Letzte Flasche getrunken",
                isPresented: Binding(
                    get: { viewModel.justEmptiedWine != nil },
                    set: { if !$0 { viewModel.justEmptiedWine = nil } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.justEmptiedWine
            ) { wine in
                // Der natürliche Moment zum Bewerten: Die Flasche ist gerade ausgetrunken.
                Button("Bewerten") { wineToRate = wine }
                Button("Archivieren") { viewModel.archive(wine) }
                Button("Löschen", role: .destructive) { wineToDelete = wine }
                Button("Im Keller behalten", role: .cancel) { }
            } message: { wine in
                Text("„\(wine.nameWithVintage)“ ist jetzt leer. Was soll damit passieren?")
            }
            .sheet(item: $wineToRate) { wine in
                RatingSheet(wine: wine)
            }
            .sheet(item: $viewModel.wineToTakeFromRack) { wine in
                WineRackSheet(wine: wine, mode: .take)
            }
            .sensoryFeedback(.decrease, trigger: viewModel.consumeCount)
    }

    // MARK: Liste

    private var wineList: some View {
        let visible = viewModel.filtered(wines)
        let groups = viewModel.grouped(visible)

        return List {
            Section {
                summaryHeader
                    // Ohne seitlichen Rand, damit die Filterknöpfe bis an den
                    // Bildschirmrand laufen – dann sieht man, dass sie scrollen.
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                // Erst wenn es etwas abzubuchen gibt; im leeren Keller wäre er nur Rauschen.
                if !groups.isEmpty {
                    TipView(consumeTip)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                    // Als Karte hier, nicht als Blase am Scan-Knopf – siehe `ScanButton`.
                    TipView(scanOptionsTip)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            if groups.isEmpty {
                Group {
                    if !viewModel.searchText.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else if viewModel.showArchived {
                        ContentUnavailableView(
                            "Archiv ist leer",
                            systemImage: "archivebox",
                            description: Text("Archivierte Weine erscheinen hier.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Nichts in dieser Ansicht",
                            systemImage: "wineglass",
                            description: Text("Ändere den Filter oder lege einen neuen Wein an.")
                        )
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(groups, id: \.type) { group in
                Section {
                    ForEach(group.wines) { wine in
                        NavigationLink(value: wine) {
                            WineRowView(wine: wine) {
                                consumeTip.invalidate(reason: .actionPerformed)
                                viewModel.consume(wine)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                wineToDelete = wine
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            if wine.isArchived {
                                Button {
                                    viewModel.unarchive(wine)
                                } label: {
                                    Label("Zurück in den Keller", systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            } else {
                                Button {
                                    viewModel.archive(wine)
                                } label: {
                                    Label("Archivieren", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                viewModel.wineToEdit = wine
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(Brand.burgundy)
                        }
                    }
                } header: {
                    // Fette Überschrift in Textfarbe, nur das Symbol trägt die Weinart.
                    Label {
                        Text(group.type.displayName)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: group.type.symbolName)
                            .foregroundStyle(group.type.color)
                    }
                    .font(.title3.weight(.bold))
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Wine.self) { wine in
            WineDetailView(wine: wine)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.showArchived ? tr("Archiv") : viewModel.summary(for: wines))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            typeFilterChips
        }
    }

    /// Eine Reihe: vorne der Filter-Chip und was davon eingeschaltet ist, dahinter die
    /// Weinarten. Der Filter steht vorne, nicht hinten – hinten läge er bei sechs Weinarten
    /// ausserhalb des Bildschirms. Aktive Filter stehen als eigene Chips da, damit man
    /// jederzeit sieht, warum die Liste kürzer ist.
    private var typeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterButtonChip(count: viewModel.activeFilterCount) {
                    isShowingFilters = true
                }
                if viewModel.showOnlyDrinkSoon {
                    RemovableChip(title: tr("Bald trinken")) { viewModel.showOnlyDrinkSoon = false }
                }
                if let strength = viewModel.strengthFilter {
                    RemovableChip(title: strength.title) { viewModel.strengthFilter = nil }
                }
                if let key = viewModel.countryFilter {
                    RemovableChip(title: viewModel.countryOptions(in: wines).first { $0.key == key }?.label ?? key) {
                        viewModel.countryFilter = nil
                    }
                }
                if viewModel.showArchived {
                    RemovableChip(title: tr("Archiv")) { viewModel.showArchived = false }
                }
                PillChip(title: tr("Alle"), isSelected: viewModel.typeFilter == nil) {
                    viewModel.typeFilter = nil
                }
                ForEach(WineType.allCases) { type in
                    PillChip(
                        title: type.displayName,
                        symbol: type.symbolName,
                        symbolColor: type.color,
                        isSelected: viewModel.typeFilter == type
                    ) {
                        viewModel.typeFilter = (viewModel.typeFilter == type) ? nil : type
                    }
                }
            }
        }
        // Der Rand gehört in die Scroll-Fläche: Der erste Knopf steht bündig, der
        // letzte schiebt sich sichtbar unter den Bildschirmrand, statt abgeschnitten
        // dort zu kleben.
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    // MARK: Leerer Keller

    private var emptyCellar: some View {
        ContentUnavailableView {
            Label("Der Keller ist leer", systemImage: "wineglass")
        } description: {
            Text("Lege deine erste Flasche an, damit der Wein-Berater etwas empfehlen kann.")
        } actions: {
            VStack(spacing: 10) {
                Button {
                    viewModel.addMode = .scan
                } label: {
                    Label("Etikett scannen", systemImage: "text.viewfinder")
                }
                .buttonStyle(.brandFilled)

                Button {
                    viewModel.addMode = .manual
                } label: {
                    Label("Manuell eingeben", systemImage: "plus")
                }
                .buttonStyle(.brandOutline)
            }
        }
    }

    // MARK: Toolbar

    /// Statistik links, Zahnrad rechts. Filter liegen in der Chip-Reihe, Neuzugänge kommen über den
    /// Scan-Knopf der Leiste, Regal und Bewertungen sind Reiter, die Party liegt im Berater.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Links, dem Zahnrad gegenüber: der Katalog in Zahlen.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingStatistics = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .accessibilityLabel("Statistik")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Einstellungen")
        }
    }
}

#Preview("Mit Weinen") {
    CellarView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(PartySession())
}

#Preview("Leer") {
    CellarView()
        .environment(\.managedObjectContext, PreviewData.emptyContext)
        .environment(PartySession())
}
