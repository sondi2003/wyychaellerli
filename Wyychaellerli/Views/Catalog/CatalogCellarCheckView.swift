import CoreData
import SwiftUI

/// Gleicht den ganzen Keller mit dem Katalog ab und lässt auswählen, was zur Prüfung geht.
///
/// Für Weine, die vor dem Katalog erfasst wurden – oder bevor „Neue Weine vorschlagen“
/// eingeschaltet war. Nichts geht ungefragt weg: Der Nutzer sieht die Liste und wählt.
struct CatalogCellarCheckView: View {

    @Environment(CatalogCenter.self) private var catalog
    @Environment(\.managedObjectContext) private var context
    @Environment(\.tabBarClearance) private var tabBarClearance

    @State private var result: CatalogCenter.CellarCheck?
    @State private var checked = 0
    @State private var total = 0
    @State private var selection = Set<NSManagedObjectID>()
    @State private var isSending = false
    @State private var sentCount = 0
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let result {
                Section {
                    summaryRow(tr("Schon im Katalog"), result.inCatalog, symbol: "checkmark.seal.fill")
                    summaryRow(tr("Bereits vorgeschlagen"), result.alreadySubmitted, symbol: "paperplane")
                    summaryRow(tr("Fehlen im Katalog"), result.missing.count, symbol: "questionmark.circle")
                }

                if total == 0 {
                    Section {
                        Text("Dein Keller ist noch leer.")
                            .foregroundStyle(.secondary)
                    }
                } else if result.missing.isEmpty {
                    Section {
                        Text("Alles da – jeder Wein aus deinem Keller steht im Katalog oder wartet auf Prüfung.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(result.missing, id: \.objectID) { wine in
                            selectableRow(wine)
                        }
                    } header: {
                        Text("Zur Prüfung senden")
                    } footer: {
                        Text(SubmissionConsent.text)
                    }
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(total > 0 ? tr("Prüfe \(checked) von \(total) …") : tr("Lade den Keller …"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .appTitle(tr("Keller abgleichen"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let result, !result.missing.isEmpty {
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text(tr("\(selection.count) Weine senden"))
                    }
                }
                .buttonStyle(.brand(.filled, large: true))
                .disabled(selection.isEmpty || isSending)
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 16 + tabBarClearance)
                .background(.bar)
            }
        }
        .contentMargins(.bottom, result?.missing.isEmpty == false ? 0 : tabBarClearance, for: .scrollContent)
        .task { await runCheck() }
    }

    private func summaryRow(_ title: String, _ count: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(verbatim: "\(count)")
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func selectableRow(_ wine: Wine) -> some View {
        let isSelected = selection.contains(wine.objectID)
        return Button {
            if isSelected {
                selection.remove(wine.objectID)
            } else {
                selection.insert(wine.objectID)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Brand.accent : Color.secondary)
                LabelThumbnail(wine: wine, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wine.nameWithVintage)
                        .foregroundStyle(.primary)
                    Text(wine.producer.isEmpty ? wine.subtitle : wine.producer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func runCheck() async {
        guard result == nil else { return }
        let request = Wine.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let wines = ((try? context.fetch(request)) ?? []).filter { !$0.name.isEmpty }
        total = wines.count
        let check = await catalog.checkCellar(wines) { checked = $0 }
        selection = Set(check.missing.map(\.objectID))
        result = check
    }

    private func send() async {
        guard var current = result else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        for wine in current.missing where selection.contains(wine.objectID) {
            do {
                try await catalog.submit(wine)
                sentCount += 1
                current.missing.removeAll { $0.objectID == wine.objectID }
                current.alreadySubmitted += 1
                selection.remove(wine.objectID)
            } catch {
                // Beim ersten Fehler aufhören: Fehlt das iCloud-Konto, scheitern auch alle übrigen.
                errorMessage = CatalogStore.friendlyMessage(for: error)
                break
            }
        }
        result = current
    }
}

#Preview {
    NavigationStack {
        CatalogCellarCheckView()
    }
    .environment(CatalogCenter())
    .environment(\.managedObjectContext, PreviewData.context)
}
