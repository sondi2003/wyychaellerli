import SwiftUI
import CoreData

/// Sheet zum Anlegen oder Bearbeiten eines Weins – manuell oder per Etikett-Scan.
struct WineFormView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogCenter.self) private var catalog
    @State private var viewModel: WineFormViewModel
    @State private var isShowingScanner: Bool
    @FocusState private var focusedField: Field?

    private enum Field { case name, producer, grape, region, country, notes }

    /// Vom leeren Feld aus wären es 25 Tipper bis zu einem üblichen Wert – der erste
    /// Tipp landet deshalb gleich bei 12,5 %, mitten im Bereich, in dem Wein liegt.
    private var alcoholBinding: Binding<Double> {
        Binding(
            get: { viewModel.alcoholPercent },
            set: { newValue in
                if viewModel.alcoholPercent == 0, newValue > 0 {
                    viewModel.alcoholPercent = 12.5
                } else {
                    viewModel.alcoholPercent = newValue
                }
            }
        )
    }

    /// Mit fertigem Scan geöffnet (Mittelknopf der Leiste) – dann gleich auf Doppel prüfen.
    private let startsWithScan: Bool
    /// Im Formular wurde ein Etikett gescannt – dann gilt der Abgleich über CloudKit.
    @State private var didScanHere = false
    /// „Ohne Foto erfassen“: kein Scan-Knopf, das widerspräche der Wahl.
    private let isManualEntry: Bool

    /// - Parameter startWithScanner: öffnet sofort den Etikett-Scanner (Plus-Menü „Etikett scannen“).
    /// - Parameter scanResult: ein Scan, der schon vor dem Formular stattfand.
    init(mode: WineFormViewModel.Mode, startWithScanner: Bool = false, scanResult: LabelScanResult? = nil) {
        let model = WineFormViewModel(mode: mode)
        if let scanResult { model.apply(scanResult) }
        _viewModel = State(initialValue: model)
        _isShowingScanner = State(initialValue: startWithScanner)
        startsWithScan = scanResult != nil
        if case .add = mode, scanResult == nil, !startWithScanner {
            isManualEntry = true
        } else {
            isManualEntry = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let existing = viewModel.visibleDuplicate {
                    duplicateSection(existing)
                }
                if let candidate = viewModel.catalogCandidate {
                    candidateSection(candidate)
                }
                if showsPhotoSection {
                    Section {
                        if !isManualEntry {
                            Button {
                                isShowingScanner = true
                            } label: {
                                Label("Etikett scannen", systemImage: "text.viewfinder")
                            }
                        }
                        labelPhotoRow(
                            title: tr("Vorderseite"),
                            data: viewModel.labelImageData,
                            remove: { viewModel.labelImageData = nil }
                        )
                        labelPhotoRow(
                            title: tr("Rückseite"),
                            data: viewModel.backLabelImageData,
                            remove: { viewModel.backLabelImageData = nil }
                        )
                        if let source = viewModel.lastScanSource {
                            Label {
                                Text("Felder aus Etikett übernommen – Zuordnung via \(source.displayName). Bitte kurz prüfen.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        if let data = viewModel.catalogImageData, let image = UIImage(data: data) {
                            let isUsed = viewModel.labelImageData == data
                            HStack(spacing: 12) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .labelLens(data, title: tr("Foto aus dem Katalog"), compact: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Foto aus dem Katalog")
                                        .font(.subheadline.weight(.medium))
                                    Text(isUsed ? "Wird als Vorderseite verwendet." : "Vielleicht besser als dein Foto.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .layoutPriority(1)
                                Spacer()
                                Button(isUsed ? (viewModel.hasOwnImageToRestore ? "Mein Foto" : "Entfernen") : "Verwenden") {
                                    viewModel.toggleCatalogImage()
                                }
                                .buttonStyle(.brandOutline)
                                .fixedSize()
                            }
                        }
                        if viewModel.catalogMatch != nil {
                            Label {
                                Text("Im gemeinsamen Katalog gefunden – fehlende Angaben ergänzt.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "books.vertical.fill")
                                    .foregroundStyle(Brand.accent)
                            }
                        }
                    }
                }

                Section("Wein") {
                    TextField("Name / Cuvée", text: $viewModel.name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .producer }
                    suggestionRows

                    TextField("Produzent / Weingut", text: $viewModel.producer)
                        .focused($focusedField, equals: .producer)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .grape }

                    Picker("Jahrgang", selection: $viewModel.vintage) {
                        // „Ohne Jahrgang“ muss wählbar sein: Manche Etiketten nennen
                        // keinen, und geraten wird hier nichts.
                        ForEach(WineFormViewModel.vintageChoices, id: \.self) { year in
                            Text(year == 0 ? tr("Ohne Jahrgang") : String(year)).tag(year)
                        }
                    }
                }

                Section {
                    TextField("Rebsorte(n)", text: $viewModel.grape)
                        .focused($focusedField, equals: .grape)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .region }

                    TextField("Region / Appellation", text: $viewModel.region)
                        .focused($focusedField, equals: .region)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .country }

                    TextField("Land", text: $viewModel.country)
                        .focused($focusedField, equals: .country)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Herkunft")
                } footer: {
                    Text("Das Land macht die Karte auf der Detailseite eindeutig.")
                }

                Section {
                    Picker("Typ", selection: $viewModel.type) {
                        ForEach(WineType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: viewModel.type) { _, _ in viewModel.typeNeedsReview = false }
                } header: {
                    Text("Typ")
                } footer: {
                    if viewModel.typeNeedsReview {
                        Label("Die Weinart wurde nicht erkannt – bitte wählen.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    // Halbe Schritte: Etiketten nennen 12,5 oder 13,5 – ganze Prozente
                    // wären zu grob, Zehntel zu fummelig.
                    Stepper(value: alcoholBinding, in: 0...20, step: 0.5) {
                        HStack {
                            Text("Alkohol")
                            Spacer()
                            if viewModel.alcoholPercent > 0 {
                                Text("\(viewModel.alcoholPercent.formatted(.number.precision(.fractionLength(0...1)))) %")
                                    .font(.body.monospacedDigit().weight(.semibold))
                                    .contentTransition(.numericText())
                            } else {
                                Text("keine Angabe")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .animation(.snappy, value: viewModel.alcoholPercent)
                    if let strength = Wine.Strength.from(percent: viewModel.alcoholPercent) {
                        Label("\(strength.title) – \(strength.range)", systemImage: strength.symbolName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // Der Weg zurück zu „keine Angabe“ wären sonst zwei Dutzend Tipper.
                    if viewModel.alcoholPercent > 0 {
                        Button("Keine Angabe") { viewModel.alcoholPercent = 0 }
                            .font(.footnote)
                    }
                } header: {
                    Text("Alkoholgehalt")
                } footer: {
                    Text("Wird beim Scannen vom Etikett übernommen. Auf 0 stellen heisst „keine Angabe“ – dann wird nichts angezeigt.")
                }

                Section {
                    TextField("Ziffern unter dem Strichcode", text: $viewModel.barcode)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                } header: {
                    Text("Strichcode")
                } footer: {
                    if viewModel.barcodeIsInvalid {
                        Label("Kein gültiger Strichcode: 13 oder 8 Ziffern, und die letzte muss stimmen. So wird er nicht gespeichert.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Wird beim Scannen von der Rückseite gelesen und hilft, den Wein im gemeinsamen Katalog wiederzufinden.")
                    }
                }

                Section("Bestand") {
                    Stepper(value: $viewModel.quantity, in: 0...999) {
                        HStack {
                            Text("Flaschen")
                            Spacer()
                            Text("\(viewModel.quantity)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText())
                        }
                    }
                    .animation(.snappy, value: viewModel.quantity)
                }

                Section {
                    Picker("Ab", selection: $viewModel.drinkFrom) {
                        Text("keine Angabe").tag(0)
                        ForEach(WineFormViewModel.drinkYearRange, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("Bis", selection: $viewModel.drinkTo) {
                        Text("keine Angabe").tag(0)
                        ForEach(WineFormViewModel.drinkYearRange, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } header: {
                    Text("Trinkreife")
                } footer: {
                    if viewModel.drinkFrom > 0 && viewModel.drinkTo > 0 && viewModel.drinkTo < viewModel.drinkFrom {
                        Text("„Bis“ liegt vor „Ab“ – die Angabe wird nicht verwendet.")
                            .foregroundStyle(.red)
                    } else if viewModel.drinkWindowFromLabel {
                        Text("Diese Spanne stand auf dem Etikett.")
                    } else if viewModel.drinkFrom > 0 || viewModel.drinkTo > 0 {
                        Text("Geschätzt aus Rebsorte, Region und Jahrgang. Du kannst sie jederzeit anpassen.")
                    } else {
                        Text("Wann der Wein am besten getrunken wird. Der Berater bevorzugt Flaschen, die dran sind.")
                    }
                }

                Section {
                    TextField("z. B. Gegrilltes Fleisch, Hartkäse", text: $viewModel.foodPairings, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Passt laut Etikett zu")
                } footer: {
                    Text("Kommagetrennt. Wird beim Scannen automatisch übernommen und ins Deutsche übersetzt.")
                }

                Section("Notizen") {
                    TextField("Terroir, Ausbau, „Geschenk von Anna“, „bis 2030 trinken“ …", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle(viewModel.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if let created = viewModel.save(in: context) {
                            // Läuft weiter, auch wenn das Formular schon zu ist.
                            let choice = viewModel.catalogChoice
                            Task { await catalog.submitIfNew(created, choice: choice) }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                LabelScanView { result in
                    viewModel.apply(result)
                    didScanHere = true
                    // Direkt nach dem Scan prüfen – das ist der Moment, in dem man es
                    // wissen will, nicht erst beim Sichern.
                    viewModel.checkForDuplicates(in: context)
                }
            }
            .onChange(of: viewModel.name) { _, _ in viewModel.checkForDuplicates(in: context) }
            .onChange(of: viewModel.producer) { _, _ in viewModel.checkForDuplicates(in: context) }
            .onChange(of: viewModel.vintage) { _, _ in viewModel.checkForDuplicates(in: context) }
            // Beim Tippen schlägt die Liste auf dem Gerät vor (sofort, ohne Netz) …
            .onChange(of: viewModel.name) { _, _ in updateSuggestions() }
            .onChange(of: viewModel.vintage) { _, _ in updateSuggestions() }
            .onChange(of: catalog.directory.count) { _, _ in updateSuggestions() }
            // … der Abgleich über CloudKit gilt nur dem Scan und dem Strichcode.
            .task(id: catalogQuery) {
                guard usesServerLookup else {
                    if viewModel.catalogCandidate != nil { viewModel.offerCatalogEntry(nil) }
                    return
                }
                guard viewModel.trimmedName.count >= 3 || !viewModel.validBarcode.isEmpty else {
                    viewModel.offerCatalogEntry(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await consultCatalog()
            }
            .task {
                await catalog.refreshDirectory()
                updateSuggestions()
            }
            .onAppear {
                if startsWithScan {
                    viewModel.checkForDuplicates(in: context)
                } else if case .add = viewModel.mode, !isShowingScanner {
                    focusedField = .name
                }
            }
        }
    }

    /// Bei „Ohne Foto erfassen“ erscheint der Abschnitt erst, wenn es etwas darin gibt.
    private var showsPhotoSection: Bool {
        !isManualEntry || viewModel.labelImageData != nil || viewModel.backLabelImageData != nil
            || viewModel.catalogImageData != nil || viewModel.catalogMatch != nil
    }

    /// Ändert sich eine dieser Angaben, wird der Katalog neu gefragt.
    private var catalogQuery: String {
        [viewModel.name, viewModel.producer, String(viewModel.vintage), viewModel.barcode, String(didScanHere)]
            .joined(separator: "|")
    }

    /// Der Abgleich über CloudKit ist für Scan und Strichcode da. Beim reinen Tippen
    /// übernimmt ihn die Liste auf dem Gerät.
    private var usesServerLookup: Bool {
        startsWithScan || didScanHere || !viewModel.validBarcode.isEmpty
    }

    private func updateSuggestions() {
        guard case .add = viewModel.mode else { return }
        viewModel.releaseSuggestionIfNameChanged()
        viewModel.updateSuggestions(catalog.suggestions(for: viewModel.name, vintage: viewModel.vintage))
    }

    /// Fragt den gemeinsamen Katalog – nach dem Scan und beim Strichcode. Ohne Netz oder ohne
    /// Treffer passiert einfach nichts. Ein Treffer wird **angeboten**, nicht übernommen.
    /// Das Foto kommt erst, wenn der Treffer bestätigt ist.
    private func consultCatalog() async {
        guard case .add = viewModel.mode, viewModel.catalogMatch == nil else { return }
        let entry = await catalog.lookup(
            name: viewModel.name,
            producer: viewModel.producer,
            vintage: viewModel.vintage,
            barcode: viewModel.validBarcode
        )
        guard !Task.isCancelled else { return }
        viewModel.offerCatalogEntry(entry)
        if let entry, viewModel.catalogMatch?.id == entry.id { await loadCatalogImage(for: entry) }
    }

    /// Holt das eine Katalogfoto des bestätigten Weins – nur im Speicher. Dauerhaft liegt es
    /// erst am Wein, wenn der Nutzer es verwendet und den Wein sichert.
    private func loadCatalogImage(for entry: CatalogWine) async {
        let data = await catalog.catalogImage(entry.id)
        guard viewModel.catalogMatch?.id == entry.id else { return }
        viewModel.catalogImageData = data
        viewModel.adoptCatalogImageIfFree()
    }

    private func choose(_ entry: CatalogWine) {
        viewModel.selectSuggestion(entry)
        Task { await loadCatalogImage(for: entry) }
    }

    /// Vorschläge aus dem Katalog, direkt unter dem Namensfeld.
    @ViewBuilder
    private var suggestionRows: some View {
        ForEach(viewModel.suggestions) { suggestion in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.footnote)
                        .foregroundStyle(Brand.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.name).font(.subheadline.weight(.semibold))
                        let detail = [suggestion.producer, suggestion.origin].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestion.entries) { entry in
                            PillChip(
                                title: entry.vintage > 0 ? String(entry.vintage) : tr("Ohne Jahrgang"),
                                isSelected: false
                            ) { choose(entry) }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        if !viewModel.suggestions.isEmpty {
            Text("Aus dem gemeinsamen Katalog – tippe auf den Jahrgang, um den Wein zu übernehmen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Die Frage „Ist das dein Wein?“ mit dem Treffer aus dem Katalog.
    @ViewBuilder
    private func candidateSection(_ entry: CatalogWine) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.vintage > 0 ? "\(entry.name) \(String(entry.vintage))" : entry.name)
                    .font(.body.weight(.semibold))
                if !entry.producer.isEmpty {
                    Text(entry.producer).foregroundStyle(.secondary)
                }
                let origin = [entry.grape, entry.region, entry.country].filter { !$0.isEmpty }.joined(separator: " · ")
                if !origin.isEmpty {
                    Text(origin).font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button("Das ist mein Wein") {
                    viewModel.confirmCatalogCandidate()
                    Task { await loadCatalogImage(for: entry) }
                }
                    .buttonStyle(.brandFilled)
                Button("Anderer Wein") { viewModel.declineCatalogCandidate() }
                    .buttonStyle(.brandOutline)
            }
        } header: {
            Text("Im gemeinsamen Katalog gefunden")
        } footer: {
            Text("Bei „Das ist mein Wein“ werden fehlende Angaben ergänzt. Deine eigenen bleiben.")
        }
    }

    /// Hinweis auf eine Flasche, die es schon gibt.
    ///
    /// Steht ganz oben und nicht erst beim Sichern: Nach dem Scan ist der Moment, in dem
    /// die Frage „hatte ich den schon?“ aufkommt. Archivierte und leere Einträge zählen
    /// ausdrücklich mit – dort weiss man es nämlich nicht mehr auswendig.
    @ViewBuilder
    private func duplicateSection(_ existing: Wine) -> some View {
        Section {
            HStack(spacing: 12) {
                LabelThumbnail(wine: existing, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(existing.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(existing.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(stateText(existing))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(existing.isArchived ? .orange : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            Button {
                viewModel.addToExisting(existing, in: context)
                dismiss()
            } label: {
                Label(
                    existing.isArchived ? "Aus dem Archiv holen und aufstocken" : "Bestand erhöhen",
                    systemImage: existing.isArchived ? "tray.and.arrow.up" : "plus.circle"
                )
            }

            Button("Trotzdem neu anlegen") {
                viewModel.ignoresDuplicates = true
            }
            .foregroundStyle(.secondary)
        } header: {
            Label("Diesen Wein hast du schon", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        } footer: {
            Text(existing.isArchived
                 ? "Der Eintrag liegt im Archiv. „Aufstocken“ holt ihn zurück und zählt deine Flaschen dazu."
                 : "„Bestand erhöhen“ zählt deine Flaschen zum bestehenden Eintrag, statt einen zweiten anzulegen.")
        }
    }

    private func stateText(_ wine: Wine) -> String {
        if wine.isArchived { return tr("Im Archiv") }
        if wine.isOutOfStock { return tr("Keine Flasche mehr im Keller") }
        return tr("\(Int(wine.quantity)) Flaschen im Keller")
    }

    /// Eine Zeile pro Etikettseite – nur sichtbar, wenn ein Foto vorliegt.
    @ViewBuilder
    private func labelPhotoRow(title: String, data: Data?, remove: @escaping () -> Void) -> some View {
        if let data, let image = UIImage(data: data) {
            HStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .labelLens(data, title: title, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text("Wird mit dem Wein gespeichert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Foto \(title) entfernen")
            }
        }
    }
}

#Preview("Neu") {
    WineFormView(mode: .add)
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
        .environment(CatalogCenter())
}

#Preview("Bearbeiten") {
    WineFormView(mode: .edit(PreviewData.sampleWines[0]))
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
        .environment(CatalogCenter())
}
