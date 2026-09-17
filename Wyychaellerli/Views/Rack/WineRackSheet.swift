import CoreData
import SwiftUI

/// Das Regal für **einen** Wein: entweder eine Flasche entnehmen oder eine einräumen.
///
/// Dieselbe Darstellung für beides, weil es dieselbe Frage ist – welches Fach? Nur die
/// bedienbaren Fächer unterscheiden sich: beim Entnehmen die eigenen, beim Einräumen
/// die freien. Alle übrigen bleiben sichtbar, damit man sich im Regal zurechtfindet,
/// sind aber nicht antippbar.
struct WineRackSheet: View {

    enum Mode {
        case take
        case place

        var title: String {
            switch self {
            case .take:  return "Flasche entnehmen"
            case .place: return "Flasche einräumen"
            }
        }

        var hint: String {
            switch self {
            case .take:  return "Tippe auf das Fach, aus dem du die Flasche nimmst. Der Bestand geht um eins runter und das Fach wird frei."
            case .place: return "Wisch über die freien Fächer oder tippe sie an. Mehr als du Flaschen hast, lässt sich nicht auswählen."
            }
        }
    }

    @ObservedObject var wine: Wine
    let mode: Mode

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var racks: FetchedResults<Rack>

    @State private var pendingSlot: Slot?
    /// Beim Einräumen ausgewählte Fächer, höchstens so viele wie Flaschen ohne Platz.
    @State private var selection: Set<Position> = []

    /// Beim Einräumen frei wählbar, beim Entnehmen das Regal der gezeigten Flaschen.
    @State private var selectedRackID: UUID?

    private var cellarRacks: [Rack] { Rack.inCurrentCellar(from: Array(racks), in: context) }

    /// Regale, die zur Auswahl stehen: beim Entnehmen nur die, in denen der Wein liegt.
    private var availableRacks: [Rack] {
        guard mode == .take else { return cellarRacks }
        let withBottles = cellarRacks.filter { entry in wine.placedSlots.contains { $0.rack == entry } }
        return withBottles.isEmpty ? cellarRacks : withBottles
    }

    private var rack: Rack? {
        guard let selectedRackID, let match = availableRacks.first(where: { $0.uuid == selectedRackID }) else {
            return availableRacks.first
        }
        return match
    }

    /// Wie viele Fächer noch gewählt werden dürfen.
    private var remaining: Int { max(0, wine.unplacedCount - selection.count) }

    var body: some View {
        NavigationStack {
            Group {
                if let rack {
                    content(rack)
                } else {
                    ContentUnavailableView(
                        "Noch kein Regal",
                        systemImage: "square.grid.3x3",
                        description: Text("Lege zuerst ein Regal an, dann kannst du Flaschen darin verorten.")
                    )
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Beim Entnehmen dorthin springen, wo die Flasche wirklich liegt.
                if mode == .take, selectedRackID == nil {
                    selectedRackID = wine.placedSlots.first?.rack?.uuid
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if mode == .place {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selection.count == 1 ? "Einräumen" : "\(selection.count) einräumen") {
                            placeSelection()
                        }
                        .fontWeight(.semibold)
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                pendingSlot.map { "Fach \($0.displayLabel)" } ?? "",
                isPresented: Binding(
                    get: { pendingSlot != nil },
                    set: { if !$0 { pendingSlot = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingSlot
            ) { slot in
                Button("Flasche entnehmen") { take(slot) }
                Button("Abbrechen", role: .cancel) { }
            } message: { _ in
                Text("Der Bestand von „\(wine.name)“ geht um eins runter.")
            }
        }
    }

    private func content(_ rack: Rack) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(mode.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Bei mehreren Regalen zuerst das Regal wählen, dann die Fächer.
                if availableRacks.count > 1 {
                    Picker("Regal", selection: Binding(
                        get: { rack.uuid },
                        set: { newValue in
                            selectedRackID = newValue
                            // Eine angefangene Auswahl gehört zum alten Regal.
                            selection.removeAll()
                        }
                    )) {
                        ForEach(availableRacks) { entry in
                            Text(entry.name).tag(entry.uuid)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                grid(rack)

                if mode == .take, !wine.placedSlots.isEmpty {
                    // Über alle Regale hinweg, damit man auch die Flaschen anderswo sieht.
                    Text(wine.placedSlots.count == 1
                         ? "Diese Flasche liegt in Fach \(wine.placedSlots[0].displayLabel)."
                         : "Fächer: \(wine.placedSlots.map(\.displayLabel).joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if mode == .place {
                    if rack.freeCount == 0 {
                        Label("Das Regal ist voll.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Text(selectionStatus)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selection.isEmpty ? .secondary : Color.accentColor)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Das Raster. Beim Einräumen passt es sich der Breite an, damit das Wischen nicht
    /// mit dem seitlichen Scrollen kollidiert; nur bei sehr breiten Regalen wird gescrollt
    /// und dann ausschliesslich getippt.
    @ViewBuilder
    private func grid(_ rack: Rack) -> some View {
        if mode == .place {
            GeometryReader { proxy in
                let fitted = fittedTile(for: rack, width: proxy.size.width)
                // Passt das ganze Regal auf die Breite, wird nicht gescrollt und das
                // Wischen ist möglich. Die Schwelle ist bewusst tief: Über eine ganze
                // Reihe zu wischen ist wertvoller als grosszügige Felder.
                if fitted >= 22 {
                    RackGridView(
                        rows: rack.rowCount,
                        columns: rack.columnCount,
                        occupancy: rack.occupancy(),
                        highlighted: highlighted(in: rack),
                        selected: selection,
                        tile: fitted,
                        spacing: fitSpacing,
                        onTap: { toggle($0, in: rack) },
                        onDragOver: { select($0, in: rack) }
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        RackGridView(
                            rows: rack.rowCount,
                            columns: rack.columnCount,
                            occupancy: rack.occupancy(),
                            highlighted: highlighted(in: rack),
                            selected: selection,
                            tile: 34,
                            onTap: { toggle($0, in: rack) }
                        )
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(height: gridHeight(for: rack))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                RackGridView(
                    rows: rack.rowCount,
                    columns: rack.columnCount,
                    occupancy: rack.occupancy(),
                    highlighted: highlighted(in: rack),
                    tile: rack.columnCount > 10 ? 40 : 50,
                    // Benannt, weil ein namenloser Schluss-Block sonst auf
                    // `onDragOver` fällt – dann feuert schon das Wischen darüber.
                    onTap: { position in tapped(position, in: rack) }
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }

    /// Engerer Abstand, damit ein breites Regal ohne Scrollen auf den Bildschirm passt.
    private var fitSpacing: CGFloat { 4 }

    private func fittedTile(for rack: Rack, width: CGFloat) -> CGFloat {
        let available = width - fitSpacing * CGFloat(rack.columnCount - 1) - 4
        return min(50, available / CGFloat(rack.columnCount))
    }

    private func gridHeight(for rack: Rack) -> CGFloat {
        let tile: CGFloat = 50
        return CGFloat(rack.rowCount) * tile + CGFloat(max(0, rack.rowCount - 1)) * 6 + 16
    }

    private var selectionStatus: String {
        if selection.isEmpty {
            return wine.unplacedCount == 1
                ? "1 Flasche ohne Platz"
                : "\(wine.unplacedCount) Flaschen ohne Platz"
        }
        if remaining == 0 { return "\(selection.count) ausgewählt – mehr Flaschen hast du nicht" }
        return "\(selection.count) ausgewählt, noch \(remaining) möglich"
    }

    // MARK: Bedienung

    private func highlighted(in rack: Rack) -> Set<Position> {
        switch mode {
        case .take:
            return Set(wine.placedSlots.map(\.position))
        case .place:
            let taken = Set(rack.placedSlots.map(\.position))
            var free: Set<Position> = []
            for row in 0..<rack.rowCount {
                for column in 0..<rack.columnCount {
                    let position = Position(row: row, column: column)
                    if !taken.contains(position) { free.insert(position) }
                }
            }
            return free
        }
    }

    private func tapped(_ position: Position, in rack: Rack) {
        // Nur die eigenen Fächer reagieren.
        guard let slot = rack.occupancy()[position], slot.wine == wine else { return }
        pendingSlot = slot
    }

    /// Tippen schaltet ein Fach an und aus.
    private func toggle(_ position: Position, in rack: Rack) {
        if selection.contains(position) {
            selection.remove(position)
        } else {
            select(position, in: rack)
        }
    }

    /// Wischen wählt nur aus, nie ab – sonst löscht man beim Zurückwischen versehentlich.
    private func select(_ position: Position, in rack: Rack) {
        guard rack.occupancy()[position] == nil else { return }
        guard !selection.contains(position) else { return }
        guard remaining > 0 else { return }
        selection.insert(position)
    }

    private func placeSelection() {
        guard let rack else { return }
        // Von oben links nach unten rechts, damit die Reihenfolge nachvollziehbar bleibt.
        for position in selection.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            Slot.place(wine, at: position, in: rack, context: context)
        }
        dismiss()
    }

    private func take(_ slot: Slot) {
        wine.consumeBottle(from: slot)
        pendingSlot = nil
        dismiss()
    }
}
