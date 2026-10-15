import CoreData
import SwiftUI

/// Bewertungsbogen für **eine** Person.
///
/// Bewusst kurz: Sterne sind Pflicht, alles andere freiwillig. Die Gründe zum Antippen
/// stehen in Alltagssprache, weil hier niemand ein Fachurteil abgeben will.
struct RatingSheet: View {

    @ObservedObject var wine: Wine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(CurrentRater.self) private var rater

    @State private var stars: Double = 0
    @State private var selectedTags: Set<String> = []
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        StarRatingView(value: $stars, size: 34)
                        Text(stars > 0
                             ? "\(stars.formatted(.number.precision(.fractionLength(0...1)))) von 5"
                             : "Tippe auf die Sterne")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                } header: {
                    Text("Wie war er?")
                } footer: {
                    Text("Halbe Sterne sind möglich. Deine Bewertung zählt getrennt von der deiner Mitbewertenden.")
                }

                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(RatingTag.positives) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Was war gut?")
                } footer: {
                    Text("Freiwillig, mehrere möglich. Hilft später beim Vergleich und beim Wein-Berater.")
                }

                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(RatingTag.negatives) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Was hat gestört?")
                }

                Section("Notiz") {
                    TextField("Optional, z. B. „zu Lamm sehr gut“", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if existingRating != nil {
                    Section {
                        Button(role: .destructive) {
                            removeRating()
                        } label: {
                            Label("Bewertung entfernen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(wine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                        .disabled(stars <= 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Bausteine

    private func tagChip(_ tag: RatingTag) -> some View {
        let isSelected = selectedTags.contains(tag.rawValue)
        let tint: Color = tag.isPositive ? .green : .orange
        return Button {
            if isSelected {
                selectedTags.remove(tag.rawValue)
            } else {
                selectedTags.insert(tag.rawValue)
            }
        } label: {
            Text(verbatim: tag.title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? tint.opacity(0.2) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isSelected ? tint : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Daten

    private var existingRating: Rating? {
        wine.rating(by: rater.identifier)
    }

    private func load() {
        guard let rating = existingRating else { return }
        stars = rating.stars
        selectedTags = Set(rating.tags)
        note = rating.note
    }

    private func save() {
        let rating = existingRating ?? Rating.create(
            in: context,
            wine: wine,
            raterID: rater.identifier,
            raterName: rater.name
        )
        rating.stars = stars
        rating.tags = Array(selectedTags).sorted()
        rating.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Der Name kann sich geändert haben, seit zuletzt bewertet wurde.
        rating.raterName = rater.name
        rating.updatedAt = .now
        context.saveChanges()
        dismiss()
    }

    private func removeRating() {
        guard let rating = existingRating else { return }
        context.delete(rating)
        context.saveChanges()
        dismiss()
    }
}
