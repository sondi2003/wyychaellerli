import CoreData
import SwiftUI

/// Was an welchem Abend gewonnen hat.
///
/// Die Einträge sind Kopien: Name und Etikett stehen darin, nicht als Verweis auf den
/// Wein. Die Flasche von Silvester ist längst leer – die Erinnerung bleibt trotzdem.
struct PartyHistoryView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Eintrag, dessen Löschen noch bestätigt werden muss.
    @State private var winToDelete: PartyWin?
    @State private var isConfirmingDeleteAll = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
        animation: .default
    )
    private var fetched: FetchedResults<PartyWin>

    /// Nur die Ergebnisse **dieses** Kellers.
    ///
    /// Auf dem Gerät der eingeladenen Person liegen ein leerer eigener und der geteilte
    /// Keller nebeneinander – ungefiltert stünden dort zwei Historien durcheinander.
    private var wins: [PartyWin] {
        guard let cellar = Cellar.current(in: context) else { return Array(fetched) }
        return fetched.filter { $0.cellar == cellar }
    }

    var body: some View {
        NavigationStack {
            Group {
                if wins.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Party", systemImage: "party.popper")
                    } description: {
                        Text("Wenn deine Gäste abgestimmt haben, steht die Siegerflasche hier – mit Anlass, Datum und Stimmen. Die Historie gehört zum Keller und ist auf allen Geräten gleich.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(wins) { win in
                                row(win)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            winToDelete = win
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    }
                            }
                        } footer: {
                            Text("Zum Löschen nach links wischen. Die Historie gehört zum Keller – was du hier entfernst, verschwindet auch auf den anderen Geräten.")
                        }

                        Section {
                            Button(role: .destructive) {
                                isConfirmingDeleteAll = true
                            } label: {
                                Label("Alle Einträge löschen", systemImage: "trash")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Party-Historie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                if !wins.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
            }
            .confirmationDialog(
                "Eintrag löschen?",
                isPresented: Binding(
                    get: { winToDelete != nil },
                    set: { if !$0 { winToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: winToDelete
            ) { win in
                Button("Löschen", role: .destructive) { delete(win) }
                Button("Abbrechen", role: .cancel) { winToDelete = nil }
            } message: { win in
                Text("„\(win.displayTitle) – \(win.wineName)“ wird entfernt, auch auf den anderen Geräten.")
            }
            .confirmationDialog(
                "Alle Einträge löschen?",
                isPresented: $isConfirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Alle \(wins.count) löschen", role: .destructive) { deleteAll() }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Die ganze Party-Historie wird entfernt – auf allen Geräten. Der Bestand im Keller bleibt unberührt.")
            }
        }
    }

    private func row(_ win: PartyWin) -> some View {
        HStack(spacing: 12) {
            if let image = win.labelImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 44, height: 55)
                    .overlay { Image(systemName: "trophy").foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(win.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let date = win.date {
                        Text(date.appShortDate)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(win.wineName)
                    .font(.subheadline)
                    .lineLimit(1)
                if !win.wineSubtitle.isEmpty {
                    Text(win.wineSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(verbatim: [win.resultText, tr("\(win.guestCount) Gäste"), tr("\(win.candidateCount) zur Wahl")].joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func delete(_ win: PartyWin) {
        context.delete(win)
        context.saveChanges()
        winToDelete = nil
    }

    /// Nur die Einträge **dieses** Kellers – auf dem Gerät des Gasts liegen daneben
    /// womöglich die des eigenen, leeren Kellers.
    private func deleteAll() {
        for win in wins {
            context.delete(win)
        }
        context.saveChanges()
    }
}
