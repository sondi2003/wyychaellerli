import CoreData
import SwiftUI

/// Alle bewerteten Weine, die besten zuerst.
///
/// Der eigentliche Zweck steht im Laden: „Welchen haben wir gemocht, welchen kaufen wir
/// wieder?“ Deshalb sind **archivierte und leere** Flaschen ausdrücklich dabei – gerade
/// die sind ja schon getrunken und damit die interessanten. Eine reine Bestandsliste
/// würde diese Frage nie beantworten.
struct RatingsOverviewView: View {

    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    )
    private var wines: FetchedResults<Wine>

    /// Nur Weine mit mindestens einer Bewertung, absteigend nach Mittelwert.
    private var rated: [Wine] {
        wines
            .filter { $0.averageRating != nil }
            .sorted {
                let left = $0.averageRating ?? 0
                let right = $1.averageRating ?? 0
                return left == right ? $0.name < $1.name : left > right
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rated.isEmpty {
                    ContentUnavailableView(
                        "Noch nichts bewertet",
                        systemImage: "star",
                        description: Text("Bewerte einen Wein auf seiner Detailseite. Hier siehst du dann, was euch geschmeckt hat und was ihr wieder kaufen solltet.")
                    )
                } else {
                    List {
                        ForEach(groups, id: \.verdict.title) { group in
                            Section(group.verdict.title) {
                                ForEach(group.wines) { wine in
                                    NavigationLink {
                                        WineDetailView(wine: wine)
                                    } label: {
                                        row(wine)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bewertungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    /// Gruppiert nach Kaufhinweis, damit die Liste die Frage direkt beantwortet.
    private var groups: [(verdict: Wine.BuyAgain, wines: [Wine])] {
        let order: [Wine.BuyAgain] = [.yes, .maybe, .no]
        return order.compactMap { verdict in
            let matching = rated.filter { $0.buyAgain.title == verdict.title }
            return matching.isEmpty ? nil : (verdict, matching)
        }
    }

    private func row(_ wine: Wine) -> some View {
        HStack(spacing: 12) {
            LabelThumbnail(wine: wine, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(wine.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(wine.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StarRatingView(value: .constant(wine.averageRating ?? 0), isEditable: false, size: 12)
                    Text(namesLine(wine))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // Der Text bekommt den freien Platz zuerst, sonst teilt er ihn sich mit
            // dem Spacer und bricht ab, obwohl rechts noch Luft wäre.
            .layoutPriority(1)
            Spacer(minLength: 4)
            if wine.isArchived || wine.isOutOfStock {
                Text(wine.isArchived ? "Archiv" : "leer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    /// „Richard 4½ · Ines 3“ – zeigt zugleich, wer noch nicht bewertet hat.
    private func namesLine(_ wine: Wine) -> String {
        wine.ratingList
            .map { "\($0.displayName) \($0.stars.formatted(.number.precision(.fractionLength(0...1))))" }
            .joined(separator: " · ")
    }
}
