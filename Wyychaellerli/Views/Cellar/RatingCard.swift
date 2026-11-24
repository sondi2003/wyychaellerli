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
    @Environment(\.openSettings) private var openSettings

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
                // Beschriftet statt nur ein Symbol: Der kleine Stern war leicht zu übersehen.
                Button(action: onRate) {
                    Label(ownRating == nil ? "Bewerten" : "Ändern",
                          systemImage: ownRating == nil ? "star" : "pencil")
                }
                .buttonStyle(.brandOutline)
                .accessibilityLabel(ownRating == nil ? "Jetzt bewerten" : "Meine Bewertung ändern")
            }

            if wine.ratingList.isEmpty {
                Text("Noch nicht bewertet")
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
                // Grau mit Verweis statt oranger Schrift: Orange auf Weiss war kaum lesbar,
                // und der Weg in die Einstellungen stand nur als Satz da.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.secondary)
                    Text("Ohne Namen sieht niemand, von wem die Bewertung stammt.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Namen eintragen") { openSettings() }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                .font(.footnote)
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
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
        case .yes:     return Brand.success
        case .maybe:   return Brand.warning
        case .no:      return Brand.danger
        case .unrated: return .secondary
        }
    }
}
