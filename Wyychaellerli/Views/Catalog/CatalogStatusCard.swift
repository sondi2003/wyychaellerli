import SwiftUI

/// Karte auf der Detailseite: Steht der Wein im gemeinsamen Katalog? Wenn nicht, lässt er
/// sich hier zur Prüfung senden.
///
/// Erscheint erst, wenn der Abgleich eine Antwort hat. Ohne Netz oder ohne eingerichteten
/// Katalog bleibt sie weg – eine Karte „unbekannt“ hilft niemandem.
struct CatalogStatusCard: View {

    @ObservedObject var wine: Wine
    @Environment(CatalogCenter.self) private var catalog

    private enum CardState: Equatable {
        case checking
        case inCatalog
        case missing
        case submitted(SubmissionStatus)
    }

    @State private var state: CardState = .checking
    @State private var isConfirming = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if state != .checking {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Gemeinsamer Katalog", systemImage: "books.vertical")
                        .font(.headline)
                    statusRow
                    if state == .missing {
                        Button {
                            isConfirming = true
                        } label: {
                            if isSending {
                                ProgressView()
                            } else {
                                Label("Zur Prüfung senden", systemImage: "paperplane")
                            }
                        }
                        .buttonStyle(.brandOutline)
                        .disabled(isSending)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            } else {
                // `.task` braucht einen Knoten, an einer leeren Gruppe liefe sie nie.
                Color.clear.frame(height: 0)
            }
        }
        .task(id: wine.objectID) { await check() }
        .alert("Zur Prüfung senden?", isPresented: $isConfirming) {
            Button("Senden") { Task { await send() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(SubmissionConsent.text)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .inCatalog:
            Label("Steht im Katalog", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .missing:
            Text("Noch nicht im Katalog. Schick ihn zur Prüfung, dann profitieren alle davon, die ihn später erfassen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .submitted(let status):
            Label(status.title, systemImage: status.symbolName)
                .foregroundStyle(status == .rejected ? Color.secondary : Brand.accent)
        case .checking:
            EmptyView()
        }
    }

    private func check() async {
        if let status = catalog.submissionStatus(for: wine) {
            state = .submitted(status)
            return
        }
        // Bei einem Fehler meldet der Abgleich `nil`; ohne Katalog bleibt die Karte dann
        // auf „fehlt“ – Senden scheitert in dem Fall mit einer verständlichen Meldung.
        state = await catalog.lookup(wine) != nil ? .inCatalog : .missing
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await catalog.submit(wine)
            state = .submitted(.pending)
        } catch {
            errorMessage = CatalogStore.friendlyMessage(for: error)
        }
    }
}

/// Was beim Vorschlagen das Gerät verlässt – an jeder Stelle gleich formuliert.
enum SubmissionConsent {
    static var text: String {
        tr("Name, Produzent, Jahrgang, Rebsorte, Region, Land, Weinart, Alkohol und das Foto der Vorderseite gehen zur Prüfung an den Betreiber der App. Notizen, Bewertungen, Bestand und Regal bleiben privat.")
    }
}

#Preview {
    CatalogStatusCard(wine: PreviewData.sampleWines[0])
        .padding()
        .environment(CatalogCenter())
        .environment(\.managedObjectContext, PreviewData.context)
}
