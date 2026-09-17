import CoreData
import SwiftUI

/// Wählt aus, welche Flasche in ein freies Fach kommt.
///
/// Gezeigt werden nur Weine, von denen noch eine Flasche ohne Platz übrig ist. Mehr
/// Plätze als Flaschen darf es nicht geben, sonst zeigt das Regal etwas an, das gar
/// nicht im Keller liegt.
struct SlotFillerView: View {

    let rack: Rack
    let position: Position

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Flasche übrig", systemImage: "tray")
                    } description: {
                        Text("Von allen Weinen im Keller hat bereits jede Flasche einen Platz. Lege zuerst einen Wein an oder erhöhe einen Bestand.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(filtered) { wine in
                                Button {
                                    place(wine)
                                } label: {
                                    CandidateRow(wine: wine)
                                }
                                .buttonStyle(.plain)
                            }
                        } footer: {
                            Text("Die Zahl rechts sagt, wie viele Flaschen dieses Weins noch keinen Platz haben.")
                        }
                    }
                    .searchable(text: $searchText, prompt: "Name, Rebsorte, Region")
                }
            }
            .navigationTitle("Fach \(position.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    // MARK: Daten

    private var candidates: [Wine] {
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "isArchived == NO AND quantity > 0")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return ((try? context.fetch(request)) ?? []).filter { $0.canPlaceAnotherBottle }
    }

    private var filtered: [Wine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.lowercased().contains(query)
                || $0.producer.lowercased().contains(query)
                || $0.grape.lowercased().contains(query)
                || $0.region.lowercased().contains(query)
        }
    }

    private func place(_ wine: Wine) {
        Slot.place(wine, at: position, in: rack, context: context)
        dismiss()
    }
}

/// Wie in der Regalansicht: eigene Ansicht mit `@ObservedObject`, damit die Zahl der
/// noch nicht eingeräumten Flaschen mitläuft.
private struct CandidateRow: View {

    @ObservedObject var wine: Wine

    var body: some View {
        HStack(spacing: 12) {
            LabelThumbnail(wine: wine, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(wine.name)
                    .font(.body.weight(.medium))
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
        }
        .contentShape(Rectangle())
    }
}
