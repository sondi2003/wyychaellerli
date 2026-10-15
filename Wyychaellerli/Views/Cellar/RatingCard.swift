import SwiftUI

/// Bewertungen zu einem Wein, kompakt: eine Kopfzeile mit Mittelwert und dem Knopf
/// zum Bewerten, darunter je Person eine Zeile mit Sternen, dann das gemeinsame Urteil.
///
/// Gründe und Notizen sind eingeklappt – sie sind das Detail, nicht der Überblick.
/// Die Einzelbewertungen stehen trotzdem neben dem Mittelwert: Ein Durchschnitt allein
/// verwischt, ob sich beide einig waren oder einer begeistert und einer enttäuscht war.
struct RatingCard: View {

    @ObservedObject var wine: Wine
    @Environment(CurrentRater.self) private var rater

    /// Wird getippt, um den eigenen Bogen zu öffnen.
    let onRate: () -> Void

    @State private var showsDetails = false

    /// Die eigene Bewertung, sofern schon Sterne vergeben wurden.
    private var ownRating: Rating? {
        guard let rating = wine.rating(by: rater.identifier), rating.stars > 0 else { return nil }
        return rating
    }

    /// Gründe oder Notizen, die sich aufklappen lassen.
    private var hasDetails: Bool {
        wine.ratingList.contains { !$0.tags.isEmpty || !$0.note.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Bewertung")
                    .font(.headline)
                Spacer()
                if let average = wine.averageRating {
                    Text("\(average.formatted(.number.precision(.fractionLength(0...1)))) von 5")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                // Der eine kleine Knopf: Stern zum Bewerten, Stift zum Ändern.
                Button(action: onRate) {
                    Image(systemName: ownRating == nil ? "star.circle.fill" : "pencil.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(ownRating == nil ? "Jetzt bewerten" : "Meine Bewertung ändern")
            }

            if wine.ratingList.isEmpty {
                Text("Noch nicht bewertet – tippe auf den Stern.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wine.ratingList) { rating in
                    HStack(spacing: 8) {
                        Text(rating.displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        StarRatingView(value: .constant(rating.stars), isEditable: false, size: 14)
                    }
                }
                buyAgainRow
                if hasDetails {
                    DisclosureGroup(isExpanded: $showsDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(wine.ratingList) { rating in
                                detail(rating)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Gründe und Notizen")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                }
            }

            if rater.name.isEmpty {
                Label("Trage in den Einstellungen deinen Namen ein, damit man sieht, von wem die Bewertung stammt.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func detail(_ rating: Rating) -> some View {
        if !rating.tags.isEmpty || !rating.note.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(rating.displayName)
                    .font(.caption.weight(.semibold))
                if !rating.tags.isEmpty {
                    Text(rating.tags.map(RatingTag.title(forStored:)).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !rating.note.isEmpty {
                    Text(rating.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
    }

    @ViewBuilder
    private var buyAgainRow: some View {
        let verdict = wine.buyAgain
        HStack(spacing: 6) {
            Label(verdict.title, systemImage: verdict.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: verdict))
            // Bei nur einer Bewertung ist das noch kein gemeinsames Urteil – das muss dastehen.
            if wine.ratingList.count == 1 {
                Text("· vorläufig, erst eine Person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func color(for verdict: Wine.BuyAgain) -> Color {
        switch verdict {
        case .yes:     return .green
        case .maybe:   return .orange
        case .no:      return .red
        case .unrated: return .secondary
        }
    }
}
