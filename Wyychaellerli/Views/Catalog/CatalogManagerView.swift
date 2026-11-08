import PhotosUI
import SwiftUI

/// Admin-Bereich „Katalog verwalten“: den ganzen Katalog durchsuchen, filtern und
/// einzelne Einträge korrigieren oder löschen.
///
/// Geladen wird der Katalog einmal ohne Etiketten; Suche und Filter laufen auf dem Gerät
/// (`CatalogFilter`). Das Etikett holt erst der Editor.
struct CatalogManagerView: View {

    @Environment(CatalogCenter.self) private var catalog

    /// Nur für die Vorführung im Simulator: feste Einträge statt CloudKit.
    var demoEntries: [CatalogWine]?

    @State private var entries: [CatalogWine] = []
    @State private var filter = CatalogFilter()
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filtered: [CatalogWine] { filter.apply(to: entries) }
    private var countryCounts: [(country: String, count: Int)] { CatalogFilter.countryCounts(in: entries) }

    var body: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            if !isLoading, errorMessage == nil {
                Section {
                    if filtered.isEmpty {
                        Text(entries.isEmpty ? tr("Der Katalog ist noch leer.") : tr("Keine Treffer."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { entry in
                        NavigationLink {
                            CatalogWineEditor(original: entry, isDemo: demoEntries != nil) { saved, previousID in
                                entries.removeAll { $0.id == previousID || $0.id == saved.id }
                                entries.append(saved)
                            } onDeleted: { id in
                                entries.removeAll { $0.id == id }
                            }
                        } label: {
                            row(entry)
                        }
                    }
                } header: {
                    // Zwei Zahlen in einem Satz vertragen die serbischen Pluralformen nicht.
                    Text(filter.isActive ? tr("\(filtered.count) Treffer") : tr("\(entries.count) Einträge"))
                }
            }
        }
        .appTitle(tr("Katalog verwalten"))
        .navigationBarTitleDisplayMode(.inline)
        // Ohne Systemleiste setzt iOS 26 die Suche sonst nach unten unter die eigene Leiste.
        .searchable(text: $filter.text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Name, Produzent, Rebsorte, Jahrgang"))
        .overlay {
            if isLoading { ProgressView() }
        }
        .refreshable { await load() }
        .task { if entries.isEmpty { await load() } }
    }

    // MARK: Filter

    /// Weinart als Chips, darunter Land, Herkunft und „Lückenhaft“.
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PillChip(title: tr("Alle"), isSelected: filter.type == nil) { filter.type = nil }
                    ForEach(WineType.allCases) { type in
                        PillChip(title: type.displayName, symbol: type.symbolName, symbolColor: type.color,
                                 isSelected: filter.type == type) {
                            filter.type = filter.type == type ? nil : type
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("\(tr("Alle Länder")) (\(entries.count))") { filter.country = nil }
                        ForEach(countryCounts, id: \.country) { item in
                            Button("\(Self.countryLabel(item.country)) (\(item.count))") { filter.country = item.country }
                        }
                    } label: {
                        menuChip(filter.country.map(Self.countryLabel) ?? tr("Land"), isActive: filter.country != nil)
                    }
                    Menu {
                        Button("\(tr("Alle Jahrgänge")) (\(entries.count))") { filter.vintage = nil }
                        ForEach(CatalogFilter.vintageCounts(in: entries), id: \.vintage) { item in
                            Button("\(item.vintage > 0 ? String(item.vintage) : tr("Ohne Jahrgang")) (\(item.count))") {
                                filter.vintage = item.vintage
                            }
                        }
                    } label: {
                        menuChip(filter.vintage.map { $0 > 0 ? String($0) : tr("Ohne Jahrgang") } ?? tr("Jahrgang"),
                                 isActive: filter.vintage != nil)
                    }
                    Menu {
                        Button(tr("Alle Herkünfte")) { filter.source = nil }
                        Button(tr("Aus Vorschlägen")) { filter.source = "nutzer" }
                        Button(tr("Von dir angepasst")) { filter.source = "admin" }
                    } label: {
                        menuChip(sourceTitle, isActive: filter.source != nil)
                    }
                    PillChip(title: tr("Lückenhaft"), symbol: "exclamationmark.circle",
                             isSelected: filter.onlyIncomplete) {
                        filter.onlyIncomplete.toggle()
                    }
                    if filter.isActive {
                        Button(tr("Zurücksetzen")) { filter = CatalogFilter() }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var sourceTitle: String {
        switch filter.source {
        case "nutzer": return tr("Aus Vorschlägen")
        case "admin":  return tr("Von dir angepasst")
        default:       return tr("Herkunft")
        }
    }

    /// Sieht aus wie ein `PillChip`, öffnet aber ein Menü.
    private func menuChip(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: title)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(isActive ? Color(.systemBackground) : .primary)
        .background(isActive ? Color.primary : .clear, in: Capsule())
        .overlay { if !isActive { Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1) } }
        .fixedSize()
    }

    private static func countryLabel(_ country: String) -> String {
        if let flag = CountryFlag.emoji(for: country) { return "\(flag) \(country)" }
        return country
    }

    // MARK: Zeile

    private func row(_ entry: CatalogWine) -> some View {
        let type = entry.wineType ?? .red
        return HStack(spacing: 12) {
            Image(systemName: type.symbolName)
                .foregroundStyle(type.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.vintage > 0 ? "\(entry.name) \(String(entry.vintage))" : entry.name)
                Text(verbatim: [entry.producer, entry.country].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if CatalogFilter.isIncomplete(entry) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Lückenhaft"))
            }
        }
    }

    private func load() async {
        if let demoEntries {
            entries = demoEntries
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await catalog.allCatalogWines()
            errorMessage = nil
        } catch {
            errorMessage = CatalogStore.friendlyMessage(for: error, asAdmin: true)
        }
    }
}

// MARK: - Eintrag bearbeiten

/// Ein Katalogeintrag zum Korrigieren: Felder, Etikett austauschen, löschen.
struct CatalogWineEditor: View {

    let original: CatalogWine
    var isDemo = false
    let onSaved: (CatalogWine, String) -> Void
    let onDeleted: (String) -> Void

    @Environment(CatalogCenter.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarClearance) private var tabBarClearance

    @State private var entry: CatalogWine
    @State private var imageData: Data?
    @State private var imageChange: CatalogStore.ImageChange = .keep
    @State private var isLoadingImage = true
    @State private var isPreparingImage = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var isWorking = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(original: CatalogWine, isDemo: Bool = false,
         onSaved: @escaping (CatalogWine, String) -> Void,
         onDeleted: @escaping (String) -> Void) {
        self.original = original
        self.isDemo = isDemo
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _entry = State(initialValue: original)
    }

    private var hasChanges: Bool {
        if case .keep = imageChange { return entry != original }
        return true
    }

    var body: some View {
        Form {
            Section {
                // Bild und Knöpfe in einer Zeile – getrennt zerschnitt die leere Zeile
                // der Knöpfe die Karte.
                VStack(spacing: 12) {
                labelImage
                HStack(spacing: 10) {
                    if CameraCaptureView.isSupported {
                        Button {
                            isCapturing = true
                        } label: {
                            Label("Kamera", systemImage: "camera")
                        }
                        .buttonStyle(.brandOutline)
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Aus Fotos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.brandOutline)
                    if imageData != nil {
                        Button {
                            imageData = nil
                            imageChange = .remove
                        } label: {
                            Label("Entfernen", systemImage: "trash")
                        }
                        .buttonStyle(.brand(.destructive))
                    }
                }
                .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Etikett")
            }

            CatalogFormFields(entry: $entry)

            Section {
                LabeledContent("Herkunft", value: entry.source == "admin" ? tr("Von dir angepasst") : tr("Aus Vorschlägen"))
            } footer: {
                Text("Änderungen gelten für alle, die den Wein künftig scannen. Wer ihn schon im Keller hat, behält seine Angaben.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(original.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking { ProgressView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .contentMargins(.bottom, 0, for: .scrollContent)
        .alert("Aus dem Katalog löschen?", isPresented: $isConfirmingDelete) {
            Button("Löschen", role: .destructive) { Task { await delete() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Eintrag verschwindet für alle. Weine in den Kellern der Nutzer bleiben unberührt.")
        }
        .fullScreenCover(isPresented: $isCapturing) {
            CameraCaptureView { image in
                isCapturing = false
                if let image { useImage(image.jpegData(compressionQuality: 0.95)) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                    useImage(data)
                }
                pickerItem = nil
            }
        }
        .task {
            if !isDemo { imageData = await catalog.catalogImage(original.id) }
            isLoadingImage = false
        }
    }

    @ViewBuilder
    private var labelImage: some View {
        ZStack {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if isLoadingImage || isPreparingImage {
                ProgressView()
            } else {
                Label("Kein Etikett", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: imageData == nil ? 60 : 120, maxHeight: 200)
        .labelLens(imageData)
    }

    /// Löschen links, Sichern rechts – fest über der Tableiste, wie beim Prüfen.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                isConfirmingDelete = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .buttonStyle(.brand(.destructive, large: true))

            Button {
                Task { await save() }
            } label: {
                Label("Sichern", systemImage: "checkmark")
            }
            .buttonStyle(.brand(.action, large: true))
            .disabled(!hasChanges || entry.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .disabled(isWorking || isPreparingImage)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10 + tabBarClearance)
        .background(.bar)
    }

    /// Das Foto geht unverändert in den Katalog: kein Zuschnitt, keine Verkleinerung.
    /// Der Verlauf unten wird wie bei allen Katalogfotos erst auf dem Gerät gerechnet,
    /// wenn jemand den Wein übernimmt – hier bleibt das Original.
    private func useImage(_ data: Data?) {
        guard let data else { return }
        imageData = data
        imageChange = .replace(data)
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        var edited = entry
        edited.name = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.producer = edited.producer.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.source = "admin"
        if isDemo {
            onSaved(edited, original.id)
            dismiss()
            return
        }
        do {
            let saved = try await catalog.saveCatalogWine(edited, previousID: original.id, image: imageChange)
            onSaved(saved, original.id)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? CatalogStore.friendlyMessage(for: error, asAdmin: true)
        }
    }

    private func delete() async {
        isWorking = true
        defer { isWorking = false }
        if !isDemo {
            do {
                try await catalog.deleteCatalogWine(original.id)
            } catch {
                errorMessage = CatalogStore.friendlyMessage(for: error, asAdmin: true)
                return
            }
        }
        onDeleted(original.id)
        dismiss()
    }
}

#if DEBUG
extension CatalogWine {
    /// Erfundene Einträge für die Vorführung im Simulator.
    static var demoCatalog: [CatalogWine] {
        [
            CatalogWine(id: "d1", name: "Cicero", producer: "Rutishauser-DiVino SA", vintage: 2023, grape: "Pinot Noir",
                        region: "Bündnerland", country: "Schweiz", typeRaw: "red", alcoholPercent: 13, source: "admin"),
            CatalogWine(id: "d2", name: "Jeninser", producer: "", vintage: 2024, grape: "Pinot Noir",
                        region: "Jenins", country: "Schweiz", typeRaw: "red", alcoholPercent: 13, source: "nutzer"),
            CatalogWine(id: "d3", name: "Esperanza", producer: "Bodegas Esperanza", vintage: 2024, grape: "Verdejo",
                        region: "Rueda", country: "Spanien", typeRaw: "white", alcoholPercent: 13, source: "nutzer"),
            CatalogWine(id: "d4", name: "Sasso al Vento", producer: "Cantine San Marzano", vintage: 2021, grape: "Negroamaro",
                        region: "Puglia", country: "Italien", typeRaw: "red", alcoholPercent: 13.5, source: "nutzer"),
            CatalogWine(id: "d5", name: "Blanc de Noir", producer: "Perfort-Vivier", vintage: 0, grape: "",
                        region: "Vin de France", country: "Frankreich", typeRaw: "white", alcoholPercent: 12, source: "nutzer")
        ]
    }
}
#endif

#Preview {
    NavigationStack {
        CatalogManagerView(demoEntries: [])
    }
    .environment(CatalogCenter())
}
