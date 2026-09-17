import CoreData
import SwiftUI

/// Zeigt auf der Detailseite, wo die Flaschen dieses Weins liegen.
///
/// Der eigentliche Zweck der ganzen Regalfunktion: vor dem Regal stehen und wissen,
/// wohin greifen. Deshalb pulsieren die eigenen Fächer, und ein Tipp darauf entnimmt
/// die Flasche gleich – ohne Umweg über eine zweite Ansicht.
struct WineRackCard: View {

    @ObservedObject var wine: Wine

    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var racks: FetchedResults<Rack>

    @State private var pendingSlot: Slot?
    @State private var isPlacing = false

    private var cellarRacks: [Rack] { Rack.inCurrentCellar(from: Array(racks), in: context) }

    /// Nur die Fächer in **diesem** Regal.
    ///
    /// Jedes Raster darf nur die eigenen Positionen hervorheben – sonst leuchtete im
    /// Küchenregal ein Fach auf, das im Keller steht.
    private func ownSlots(in rack: Rack) -> [Slot] {
        wine.placedSlots.filter { $0.rack == rack }
    }

    /// Regale, in denen dieser Wein tatsächlich liegt – in der Reihenfolge der Regale.
    private var racksWithBottles: [Rack] {
        cellarRacks.filter { !ownSlots(in: $0).isEmpty }
    }

    /// Ob der Regalname dazugeschrieben werden muss.
    private var showsRackNames: Bool { cellarRacks.count > 1 }

    var body: some View {
        if !cellarRacks.isEmpty, wine.placedCount > 0 || wine.canPlaceAnotherBottle {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Im Regal")
                        .font(.headline)
                    Spacer()
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Ein Raster je Regal, in dem der Wein liegt. Bei mehreren Regalen steht
                // der Name darüber – „B3“ allein schickt einen sonst an den falschen Ort.
                ForEach(racksWithBottles) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        if showsRackNames {
                            Text(entry.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            RackGridView(
                                rows: entry.rowCount,
                                columns: entry.columnCount,
                                occupancy: entry.occupancy(),
                                highlighted: Set(ownSlots(in: entry).map(\.position)),
                                tile: entry.columnCount > 10 ? 30 : 38,
                                // Benannt, weil ein namenloser Schluss-Block sonst auf
                                // `onDragOver` fällt – dann feuert schon das Wischen darüber.
                                onTap: { position in
                                    guard let slot = entry.occupancy()[position], slot.wine == wine else { return }
                                    pendingSlot = slot
                                }
                            )
                            .padding(.vertical, 6)
                        }
                        Text(positionsLine(in: entry))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if wine.canPlaceAnotherBottle {
                    Button {
                        isPlacing = true
                    } label: {
                        Label(
                            wine.unplacedCount == 1 ? "Flasche einräumen" : "\(wine.unplacedCount) Flaschen einräumen",
                            systemImage: "plus.square.on.square"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .cardStyle()
            .sheet(isPresented: $isPlacing) {
                WineRackSheet(wine: wine, mode: .place)
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
                Button("Flasche entnehmen") {
                    wine.consumeBottle(from: slot)
                    pendingSlot = nil
                }
                Button("Abbrechen", role: .cancel) { }
            } message: { _ in
                Text("Der Bestand geht um eins runter und das Fach wird frei.")
            }
        }
    }

    private var status: String {
        if wine.placedCount == 0 { return "noch nicht verortet" }
        if wine.unplacedCount == 0 { return "alle verortet" }
        return "\(wine.placedCount) von \(wine.quantity) verortet"
    }

    private func positionsLine(in rack: Rack) -> String {
        // Der Regalname steht schon in der Überschrift – hier genügt das Fach.
        let labels = ownSlots(in: rack).map(\.position.label)
        if labels.count == 1 { return "Fach \(labels[0]). Tippen entnimmt die Flasche." }
        return "Fächer \(labels.joined(separator: ", ")). Tippen entnimmt die Flasche."
    }
}
