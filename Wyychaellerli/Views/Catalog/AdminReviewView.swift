import SwiftUI

/// Admin-Bereich: offene Vorschläge prüfen, anpassen, aufnehmen oder ablehnen.
///
/// Gleiche Vorschläge (derselbe Katalogschlüssel) erscheinen als **eine** Zeile mit
/// Anzahl – sonst prüft man denselben Wein mehrmals. Ein Entscheid gilt für die ganze
/// Gruppe, und jeder Einreicher bekommt seine Mitteilung.
///
/// Sichtbar nur, wenn die eigene Kennung im Datensatz `admins` steht. Geschützt sind die
/// Daten aber durch die Rolle in der CloudKit-Konsole, nicht durch das Ausblenden.
struct AdminReviewView: View {

    @Environment(CatalogCenter.self) private var catalog
    @State private var groups: [SubmissionGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            if groups.isEmpty, !isLoading, errorMessage == nil {
                Section {
                    Text("Keine offenen Vorschläge.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                NavigationLink {
                    AdminSubmissionEditor(group: group) { decided in
                        groups.removeAll { $0.id == decided.id }
                    }
                } label: {
                    row(group)
                }
            }
        }
        .navigationTitle("Vorschläge prüfen")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ group: SubmissionGroup) -> some View {
        HStack(spacing: 12) {
            if let data = group.labelImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.title)
                Text(verbatim: group.first.producer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if group.items.count > 1 {
                Text(verbatim: "\(group.items.count)×")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let pending = try await catalog.pendingSubmissions()
            groups = SubmissionGroup.grouping(pending)
            errorMessage = nil
        } catch {
            errorMessage = CatalogStore.friendlyMessage(for: error, asAdmin: true)
        }
    }
}

/// Gleiche Vorschläge, zusammengefasst über den Katalogschlüssel.
struct SubmissionGroup: Identifiable {
    let id: String
    let items: [CatalogSubmission]

    var first: CatalogSubmission { items[0] }

    /// Der Eintrag, wie er aus den Vorschlägen hervorgeht – mit den Strichcodes **aller**
    /// Einreicher, ohne Doppel.
    var asCatalogWine: CatalogWine {
        var entry = first.asCatalogWine
        // Mehrere Vorschläge zum selben Wein ergänzen sich: Was einer leer lässt, liefert ein anderer.
        for other in items.dropFirst() { entry.fillEmptyFields(from: other.asCatalogWine) }
        entry.gtins = CatalogStore.unique(items.map(\.barcode).filter { !$0.isEmpty })
        return entry
    }

    var labelImageData: Data? { items.lazy.compactMap(\.labelImageData).first }
    var title: String {
        first.vintage > 0 ? "\(first.name) \(String(first.vintage))" : first.name
    }

    #if DEBUG
    /// Ein erfundener Vorschlag für die Vorführung im Simulator.
    static var demo: SubmissionGroup {
        let submission = CatalogSubmission(
            id: "demo", name: "Testwein", producer: "Weingut Muster", vintage: 2026,
            grape: "Pinot Noir", region: "Bündnerland", country: "Schweiz", typeRaw: "red",
            alcoholPercent: 13, catalogKey: "demo", wineUUID: "", status: .pending, createdAt: nil
        )
        return SubmissionGroup(id: "demo", items: [submission, submission])
    }
    #endif

    /// Älteste Gruppe zuerst – wer zuerst geschickt hat, wird zuerst bedient.
    static func grouping(_ submissions: [CatalogSubmission]) -> [SubmissionGroup] {
        Dictionary(grouping: submissions, by: \.catalogKey)
            .map { SubmissionGroup(id: $0.key, items: $0.value) }
            .sorted { ($0.first.createdAt ?? .distantPast) < ($1.first.createdAt ?? .distantPast) }
    }
}

// MARK: - Einzelner Vorschlag

/// Ein Vorschlag zum Prüfen: Etikett, Felder zum Korrigieren, Aufnehmen oder Ablehnen.
struct AdminSubmissionEditor: View {

    let group: SubmissionGroup
    let onDecided: (SubmissionGroup) -> Void

    @Environment(CatalogCenter.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarClearance) private var tabBarClearance

    @State private var entry: CatalogWine
    @State private var existing: CatalogWine?
    @State private var existingHasImage = false
    @State private var isWorking = false
    @State private var isConfirmingReject = false
    @State private var errorMessage: String?

    init(group: SubmissionGroup, onDecided: @escaping (SubmissionGroup) -> Void) {
        self.group = group
        self.onDecided = onDecided
        _entry = State(initialValue: group.asCatalogWine)
    }

    var body: some View {
        Form {
            if let data = group.labelImageData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if group.items.count > 1 || existing != nil {
                Section {
                    if group.items.count > 1 {
                        Label(tr("\(group.items.count) Personen haben diesen Wein vorgeschlagen."), systemImage: "person.2")
                    }
                    if existing != nil {
                        if let added = supplement {
                            // Eine Ergänzung: Vorhandenes bleibt, es kommt nur Neues dazu.
                            Label(tr("Ergänzt den bestehenden Eintrag um: \(added.joined(separator: ", ")). Aufnehmen fügt das hinzu und ändert sonst nichts."), systemImage: "plus.circle")
                        } else {
                            Label("Steht schon im Katalog – Aufnehmen überschreibt den Eintrag mit diesen Angaben.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            CatalogFormFields(entry: $entry)

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking { ProgressView() }
        }
        // Die Knöpfe stehen fest unten statt am Ende des Formulars: Auf einem kleinen
        // iPhone lagen sie sonst unter der Tableiste und waren nur mit Mühe zu erreichen.
        .safeAreaInset(edge: .bottom, spacing: 0) { decisionBar }
        // Die Knopfleiste hält schon Abstand zur Tableiste, das Formular braucht keinen mehr.
        .contentMargins(.bottom, 0, for: .scrollContent)
        // Eine Rückfrage in der Mitte, nicht als Sprechblase am Knopf – die schwebte
        // irgendwo über dem Formular.
        .alert("Vorschlag ablehnen?", isPresented: $isConfirmingReject) {
            Button("Ablehnen", role: .destructive) { Task { await reject() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Wer den Wein vorgeschlagen hat, bekommt eine Mitteilung, dass er nicht aufgenommen wurde.")
        }
        .task {
            existing = await catalog.existingEntry(for: group.id)
            if existing != nil {
                existingHasImage = await catalog.catalogImage(group.id) != nil
            }
        }
    }

    /// Was dieser Vorschlag dem bestehenden Eintrag hinzufügt – `nil`, wenn er etwas
    /// Vorhandenes ändert oder nichts Neues bringt.
    private var supplement: [String]? {
        guard let existing, var added = entry.additions(over: existing) else { return nil }
        if group.labelImageData != nil, !existingHasImage { added.append(tr("Foto")) }
        return added.isEmpty ? nil : added
    }

    /// Gleiche Angaben wie der bestehende Eintrag, nur ein Strichcode kommt dazu? Dann ist
    /// es eine Ergänzung (siehe `SubmissionDraft.init(adding:to:wineUUID:)`), kein Überschreiben.
    static func differsOnlyByBarcode(_ entry: CatalogWine, from existing: CatalogWine) -> Bool {
        var other = existing
        other.gtins = entry.gtins
        other.source = entry.source
        other.sourceID = entry.sourceID
        other.adminEdited = entry.adminEdited
        return other == entry && !entry.gtins.allSatisfy(existing.gtins.contains)
    }

    /// Ablehnen links, Aufnehmen rechts – wie Abbrechen und Bestätigen in iOS üblich.
    private var decisionBar: some View {
        HStack(spacing: 12) {
            Button {
                isConfirmingReject = true
            } label: {
                Label("Ablehnen", systemImage: "xmark")
            }
            .buttonStyle(.brand(.destructive, large: true))

            Button {
                Task { await accept() }
            } label: {
                Label("Aufnehmen", systemImage: "checkmark.seal")
            }
            .buttonStyle(.brand(.action, large: true))
        }
        .disabled(isWorking || entry.name.trimmingCharacters(in: .whitespaces).isEmpty)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10 + tabBarClearance)
        .background(.bar)
    }

    private func accept() async {
        isWorking = true
        defer { isWorking = false }
        var final = entry
        final.name = final.name.trimmingCharacters(in: .whitespacesAndNewlines)
        final.producer = final.producer.trimmingCharacters(in: .whitespacesAndNewlines)
        // Der Schlüssel folgt den korrigierten Angaben, damit ein späterer Scan desselben
        // Weins genau diesen Eintrag findet.
        final.id = CatalogKey.make(producer: final.producer, name: final.name, vintage: final.vintage)
        final.source = final == group.asCatalogWine ? "nutzer" : "admin"
        if let existing, supplement != nil {
            // Eine Ergänzung bleibt am Eintrag: Ein neu ausgefüllter Produzent würde sonst
            // den Schlüssel ändern und einen zweiten Eintrag anlegen.
            final.id = existing.id
            final.source = existing.source
            final.sourceID = existing.sourceID
        }
        do {
            try await catalog.accept(group.items, as: final)
            onDecided(group)
            dismiss()
        } catch {
            errorMessage = CatalogStore.friendlyMessage(for: error, asAdmin: true)
        }
    }

    private func reject() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await catalog.reject(group.items)
            onDecided(group)
            dismiss()
        } catch {
            errorMessage = CatalogStore.friendlyMessage(for: error, asAdmin: true)
        }
    }
}

#Preview {
    NavigationStack {
        AdminReviewView()
    }
    .environment(CatalogCenter())
}
