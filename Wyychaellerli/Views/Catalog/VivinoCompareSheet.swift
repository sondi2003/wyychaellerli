import SwiftUI

/// Vivino-Abgleich für den Admin: Treffer wählen, Gegenüberstellung ansehen, Felder
/// übernehmen. Übernommen wird **nur ins Formular** – gespeichert wird erst mit „Aufnehmen“.
struct VivinoCompareSheet: View {

    @Binding var entry: CatalogWine
    /// Das gewählte Vivino-Foto; `AdminSubmissionEditor` speichert es beim Aufnehmen.
    @Binding var photo: Data?
    /// Das Foto des Vorschlags, zum Vergleichen.
    var currentPhoto: Data?
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case failed(String)
        case results([RankedVivinoCandidate])
    }

    @State private var phase = Phase.loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Suche bei Vivino …")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Kein Abgleich möglich", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(verbatim: message)
                    } actions: {
                        Button("Nochmals versuchen") { Task { await load() } }
                            .buttonStyle(.brand(.outline))
                    }
                case .results(let list) where list.isEmpty:
                    ContentUnavailableView {
                        Label("Kein passender Treffer", systemImage: "magnifyingglass")
                    } description: {
                        Text("Vivino kennt diesen Wein nicht unter diesem Namen. Prüfe Name und Produzent oder suche im Browser.")
                        + Text(verbatim: "\n\n" + tr("Gesucht wurde nach:") + " " + VivinoRanker.searchTerms(for: entry).map { "„\($0)“" }.joined(separator: ", "))
                    } actions: {
                        if let url = AdminSubmissionEditor.vivinoSearchURL(for: entry) {
                            Link("Im Browser suchen", destination: url)
                        }
                    }
                case .results(let list):
                    resultList(list)
                }
            }
            .appTitle(tr("Vivino-Abgleich"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .navigationDestination(for: VivinoCandidate.self) { candidate in
                VivinoComparisonView(candidate: candidate, entry: $entry, photo: $photo, currentPhoto: currentPhoto)
            }
        }
        .presentationDetents([.large])
        .task { await load() }
    }

    private func resultList(_ list: [RankedVivinoCandidate]) -> some View {
        List {
            Section {
                ForEach(list) { item in
                    NavigationLink(value: item.candidate) {
                        row(item)
                    }
                }
            } header: {
                Text("Treffer bei Vivino")
            } footer: {
                Text("Der beste Treffer steht oben. Nichts wird übernommen, bevor du es in der Gegenüberstellung wählst.")
            }
        }
    }

    private func row(_ item: RankedVivinoCandidate) -> some View {
        let c = item.candidate
        return VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: c.title)
            let origin = [c.region, c.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !origin.isEmpty {
                Text(verbatim: origin)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let rating = c.rating, c.ratingsCount > 0 {
                Label {
                    Text(verbatim: "\(rating.formatted(.number.precision(.fractionLength(1)))) · \(c.ratingsCount)")
                } icon: {
                    Image(systemName: "star.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        phase = .loading
        do {
            phase = .results(try await VivinoLookup.find(for: entry))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

extension VivinoCandidate: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(vid) }
}

/// Links der Vorschlag, rechts Vivino; pro abweichende Zeile ein „Übernehmen“.
private struct VivinoComparisonView: View {

    let candidate: VivinoCandidate
    @Binding var entry: CatalogWine
    @Binding var photo: Data?
    var currentPhoto: Data?
    @State private var isLoadingPhoto = false
    @State private var photoFailed = false
    @State private var preview: Data?

    private var rows: [VivinoComparisonRow] {
        VivinoComparison.rows(entry: entry, candidate: candidate)
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    comparisonRow(row)
                }
            } header: {
                Text(verbatim: candidate.title)
            } footer: {
                Text("Übernommen wird ins Formular. Gespeichert wird erst mit „Aufnehmen“.")
            }

            if !candidate.imageURL.isEmpty {
                photoSection
            }

            Section {
                Button {
                    entry = VivinoComparison.apply(candidate, to: entry, states: [.fillable])
                } label: {
                    Text("Leere Felder füllen")
                }
                .buttonStyle(.brand(.outline, large: true))
                .disabled(!rows.contains { $0.state == .fillable })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                Button {
                    entry = VivinoComparison.apply(candidate, to: entry, states: [.fillable, .different])
                } label: {
                    Text("Alle Abweichungen übernehmen")
                }
                .buttonStyle(.brand(.outline, large: true))
                .disabled(!rows.contains { $0.state == .fillable || $0.state == .different })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Überschreibt auch Angaben, die du schon hast. Name, Produzent und Jahrgang bestimmen den Schlüssel des Eintrags.")
            }
        }
        .appTitle(tr("Gegenüberstellung"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Foto des Vorschlags links, Vivino rechts; „Verwenden“ merkt das Vivino-Foto vor.
    private var photoSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                photoColumn(title: tr("Vorschlag"), data: currentPhoto)
                photoColumn(title: tr("Vivino"), data: preview)
            }
            if photo != nil, photo == preview {
                Label("Wird beim Aufnehmen im Katalog gespeichert.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Button("Nicht verwenden", role: .destructive) { photo = nil }
            } else {
                Button {
                    photo = preview
                } label: {
                    Text("Vivino-Foto verwenden")
                }
                .disabled(preview == nil)
            }
            if photoFailed {
                Text("Das Foto konnte nicht geladen werden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Foto")
        } footer: {
            Text("Das Vivino-Foto kommt in den Katalog, auch wenn dort oder im Vorschlag schon eines ist. Dein Foto im Keller bleibt unberührt.")
        }
        .task(id: candidate.id) {
            isLoadingPhoto = true
            preview = await VivinoLookup.image(for: candidate)
            photoFailed = preview == nil
            isLoadingPhoto = false
        }
    }

    private func photoColumn(title: String, data: Data?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Group {
                    if isLoadingPhoto && title == tr("Vivino") { ProgressView() } else { Text(verbatim: "–").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonRow(_ row: VivinoComparisonRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: row.field.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                stateBadge(row.state)
            }
            HStack(alignment: .top, spacing: 12) {
                column(title: tr("Vorschlag"), value: row.current)
                column(title: tr("Vivino"), value: row.vivino)
            }
            if row.state == .different || row.state == .fillable {
                Button {
                    var updated = entry
                    row.field.apply(candidate, to: &updated)
                    entry = updated
                } label: {
                    Text("Übernehmen")
                }
                .buttonStyle(.brand(.outline))
            }
        }
        .padding(.vertical, 4)
    }

    private func column(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value.isEmpty ? "–" : value)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stateBadge(_ state: VivinoComparisonRow.State) -> some View {
        switch state {
        case .same:
            Label("gleich", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.green)
        case .different:
            Label("abweichend", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .fillable:
            Label("fehlt im Vorschlag", systemImage: "plus.circle")
                .font(.caption)
                .foregroundStyle(Brand.accent)
        case .vivinoEmpty:
            Text("keine Angabe bei Vivino")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Adresse des Webhooks und Zugangsschlüssel (nur Admin).
struct VivinoSettingsView: View {

    @State private var url = VivinoLookupSettings.urlString
    @State private var token = VivinoLookupSettings.token
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                TextField("https://…/webhook/vivino-suche", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Zugangsschlüssel", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Webhook in n8n")
            } footer: {
                Text("Die Produktionsadresse des Ablaufs „Webhook Vivino-Suche“ (https) und der Wert der Header-Auth-Zugangsdaten mit dem Namen „X-Admin-Token“. Der Schlüssel liegt in der Keychain dieses Geräts.")
            }
            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Label("Verbindung testen", systemImage: "bolt.horizontal")
                        if isTesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting || !VivinoLookupSettings.isConfigured)
                if let testResult {
                    Text(verbatim: testResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Die Eingaben werden sofort gespeichert. Der Test sucht einmal nach „Donatsch“.")
            }
            if VivinoLookupSettings.endpoint == nil, !url.isEmpty {
                Section {
                    Label("Die Adresse muss mit https:// beginnen.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .appTitle(tr("Vivino-Abgleich"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: url) { _, value in VivinoLookupSettings.urlString = value }
        .onChange(of: token) { _, value in VivinoLookupSettings.token = value }
    }

    private func test() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let list = try await VivinoLookup.search(term: "Donatsch")
            testResult = tr("Verbindung steht (Testsuche: \(list.count) Treffer).")
        } catch {
            testResult = error.localizedDescription
        }
    }
}

#Preview {
    VivinoCompareSheet(entry: .constant(CatalogWine(
        id: "x", name: "Unique Pinot Noir", producer: "Donatsch", vintage: 2021, grape: "", region: "",
        country: "", typeRaw: "red", alcoholPercent: 0, source: "nutzer")), photo: .constant(nil))
}
