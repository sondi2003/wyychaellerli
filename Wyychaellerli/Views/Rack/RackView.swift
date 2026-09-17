import CoreData
import SwiftUI
import TipKit

/// Das Regal: ansehen, einräumen, Fach räumen.
///
/// Der Einstieg beim Einräumen ist bewusst das **Fach**, nicht der Wein. So läuft es
/// auch in echt: Man steht vor dem Regal, hat eine Flasche in der Hand und sucht ein
/// freies Fach. Der umgekehrte Weg – vom Wein aus einräumen – kommt auf der Detailseite.
struct RackView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var racks: FetchedResults<Rack>

    private let rackTip = RackSwipeTip()

    @State private var isEditingRack = false
    /// Freies Fach, für das gerade ein Wein gewählt wird.
    @State private var fillingPosition: Position?
    /// Belegtes Fach, das gerade angetippt wurde.
    @State private var selectedSlot: Slot?
    /// Wein aus der Liste „Noch nicht im Regal“, dessen Flaschen gerade verortet werden.
    @State private var placingWine: Wine?
    @State private var mergeResult: String?
    /// Welches Regal gerade gezeigt wird. `nil` = das erste.
    @State private var selectedRackID: UUID?
    @State private var isAddingRack = false

    /// Alle Regale dieses Kellers, ältestes zuerst.
    private var cellarRacks: [Rack] { Rack.inCurrentCellar(from: Array(racks), in: context) }

    /// Das gezeigte Regal – das gewählte, sonst das erste.
    private var rack: Rack? {
        guard let selectedRackID, let match = cellarRacks.first(where: { $0.uuid == selectedRackID }) else {
            return cellarRacks.first
        }
        return match
    }

    private var canAddRack: Bool { cellarRacks.count < Rack.maximumCount }

    var body: some View {
        NavigationStack {
            Group {
                if let rack {
                    content(rack)
                } else {
                    ContentUnavailableView {
                        Label("Noch kein Regal", systemImage: "square.grid.3x3")
                    } description: {
                        // Hinweis auf den Abgleich: Wer hier vorschnell anlegt, hat gleich
                        // zwei Regale, sobald das erste über iCloud eintrifft.
                        Text("Lege dein Regal an, dann kannst du deine Flaschen darin einräumen und später wiederfinden.\n\nHast du auf einem anderen Gerät schon eines eingerichtet, warte kurz – es kommt über iCloud von selbst.")
                    } actions: {
                        Button("Regal anlegen") { createRack() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(rack?.name ?? "Regal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                // Der Umschalter sitzt im Titel, damit der Bildschirm fürs Raster frei bleibt.
                if cellarRacks.count > 1 || canAddRack, !cellarRacks.isEmpty {
                    ToolbarItem(placement: .principal) {
                        rackMenu
                    }
                }
                if rack != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Bearbeiten") { isEditingRack = true }
                    }
                }
            }
            .sheet(isPresented: $isEditingRack) {
                if let rack {
                    RackEditorView(rack: rack, canDelete: cellarRacks.count > 1) {
                        // Nach dem Löschen aufs erste verbleibende Regal wechseln.
                        selectedRackID = nil
                    }
                }
            }
            .sheet(isPresented: $isAddingRack) {
                NewRackView { name, rows, columns in
                    let created = Rack.create(
                        in: context,
                        cellar: Cellar.active(in: context),
                        name: name, rows: rows, columns: columns
                    )
                    selectedRackID = created?.uuid
                }
            }
            .sheet(item: $fillingPosition) { position in
                if let rack { SlotFillerView(rack: rack, position: position) }
            }
            .sheet(item: $placingWine) { wine in
                WineRackSheet(wine: wine, mode: .place)
            }
            .confirmationDialog(
                selectedSlot?.wine?.name ?? "",
                isPresented: Binding(
                    get: { selectedSlot != nil },
                    set: { if !$0 { selectedSlot = nil } }
                ),
                titleVisibility: .visible,
                presenting: selectedSlot
            ) { slot in
                Button("Fach räumen") { clear(slot) }
                Button("Abbrechen", role: .cancel) { }
            } message: { slot in
                Text("Fach \(slot.displayLabel). „Fach räumen“ nimmt die Flasche nur aus dem Regal, der Bestand bleibt gleich.")
            }
        }
    }

    // MARK: Umschalter

    /// Regale wechseln und neue anlegen – bis zu `Rack.maximumCount`.
    private var rackMenu: some View {
        Menu {
            Picker("Regal", selection: Binding(
                get: { rack?.uuid },
                set: { selectedRackID = $0 }
            )) {
                ForEach(cellarRacks) { entry in
                    Text("\(entry.name) · \(entry.usedCount)/\(entry.capacity)")
                        .tag(entry.uuid)
                }
            }
            if canAddRack {
                Divider()
                Button {
                    isAddingRack = true
                } label: {
                    Label("Neues Regal", systemImage: "plus")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(rack?.name ?? "Regal")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Regal wählen, aktuell \(rack?.name ?? "keines")")
    }

    // MARK: Inhalt

    private func content(_ rack: Rack) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(summary(rack))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    RackGridView(
                        rows: rack.rowCount,
                        columns: rack.columnCount,
                        occupancy: rack.occupancy(),
                        tile: tileSize(for: rack)
                    ) { position in
                        tapped(position, in: rack)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }

                if duplicateCount > 0 {
                    duplicateCard
                }

                if unplacedWines.isEmpty {
                    Label("Alle Flaschen sind eingeräumt.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    unplacedSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var unplacedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TipView(rackTip)
                .padding(.bottom, 4)
            Text("Noch nicht im Regal")
                .font(.headline)
            Text("Tippe auf einen Wein und wähle dann so viele Fächer, wie er Flaschen hat – nebeneinander oder verteilt. Oder tippe auf ein freies Fach für eine einzelne Flasche.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(unplacedWines) { wine in
                Button {
                    rackTip.invalidate(reason: .actionPerformed)
                    placingWine = wine
                } label: {
                    UnplacedWineRow(wine: wine)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// **Gleichnamige** Regale – entstanden, wenn zwei Geräte gleichzeitig eines anlegen.
    ///
    /// Seit es mehrere Regale geben darf, ist „zwei Regale“ für sich kein Fehler mehr.
    /// Nur wenn zwei denselben Namen tragen, ist es die versehentliche Doppelanlage.
    private var duplicateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gleichnamige Regale gefunden", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Es gibt \(duplicateCount == 1 ? "zwei Regale" : "mehrere Regale") mit demselben Namen. Das passiert, wenn auf zwei Geräten gleichzeitig eines angelegt wurde, bevor das erste über iCloud ankam. Willst du wirklich zwei getrennte Regale, gib ihnen unter „Bearbeiten“ verschiedene Namen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                merge()
            } label: {
                Label("Regale zusammenführen", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            if let mergeResult {
                Text(mergeResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Daten

    /// Wie viele Namen doppelt vergeben sind.
    private var duplicateCount: Int {
        guard let cellar = Cellar.current(in: context) else { return 0 }
        return Rack.duplicatesByName(in: context, for: cellar).count
    }

    private func merge() {
        guard let cellar = Cellar.current(in: context) else { return }
        let result = Rack.mergeDuplicates(in: context, for: cellar)
        mergeResult = result.released == 0
            ? "\(result.moved) Fächer übernommen."
            : "\(result.moved) Fächer übernommen, \(result.released) Flaschen aus dem Regal genommen, weil das Fach schon belegt war. Der Bestand ist unverändert."
    }

    /// Weine mit Bestand, von denen noch nicht jede Flasche einen Platz hat.
    private var unplacedWines: [Wine] {
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "isArchived == NO AND quantity > 0")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return ((try? context.fetch(request)) ?? []).filter { $0.canPlaceAnotherBottle }
    }

    private func summary(_ rack: Rack) -> String {
        let used = rack.usedCount
        let capacity = rack.capacity
        let free = rack.freeCount
        return "\(used) von \(capacity) Fächern belegt · \(free) frei"
    }

    /// Kleinere Fächer, sobald das Regal breit wird, damit möglichst viel aufs Bild passt.
    private func tileSize(for rack: Rack) -> CGFloat {
        switch rack.columnCount {
        case ...6:  return 52
        case 7...10: return 44
        case 11...14: return 38
        default: return 32
        }
    }

    private func tapped(_ position: Position, in rack: Rack) {
        if let slot = rack.occupancy()[position] {
            selectedSlot = slot
        } else {
            fillingPosition = position
        }
    }

    private func createRack() {
        Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
    }

    /// Nimmt die Flasche aus dem Fach, ohne den Bestand zu ändern.
    private func clear(_ slot: Slot) {
        context.delete(slot)
        context.saveChanges()
        selectedSlot = nil
    }
}

// MARK: - Zeile eines noch nicht eingeräumten Weins

/// Eigene kleine Ansicht mit `@ObservedObject`.
///
/// Ohne die Beobachtung bleibt die Zahl der freien Flaschen stehen, sobald man eine
/// einräumt: Es ändert sich nur eine **Beziehung** des Weins, und SwiftUI hätte keinen
/// Anlass, die Zeile neu zu zeichnen.
private struct UnplacedWineRow: View {

    @ObservedObject var wine: Wine

    var body: some View {
        HStack(spacing: 10) {
            LabelThumbnail(wine: wine, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(wine.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(wine.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Der Text bekommt den freien Platz zuerst, sonst teilt er ihn sich mit
            // dem Spacer und bricht ab, obwohl rechts noch Luft wäre.
            .layoutPriority(1)
            Spacer(minLength: 4)
            Text("\(wine.unplacedCount)×")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet das Regal, um die Flaschen einzuräumen.")
    }
}

// MARK: - Position als Sheet-Auslöser

extension Position: Identifiable {
    var id: String { "\(row)-\(column)" }
}
