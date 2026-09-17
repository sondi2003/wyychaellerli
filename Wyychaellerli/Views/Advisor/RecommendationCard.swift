import SwiftUI

/// „Details“ und „Flasche öffnen“ nebeneinander, in Berater-Karten.
///
/// „Flasche öffnen“ bucht ab – das war nicht allen klar, manche erwarteten die
/// Detailseite. Deshalb steht der Weg dorthin jetzt daneben, und der Knopf heisst
/// „Trinken“, damit die Wirkung im Wort steckt.
struct WineActionButtons: View {

    @ObservedObject var wine: Wine
    let onOpenBottle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: wine) {
                Label("Details", systemImage: "info.circle")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Button(action: onOpenBottle) {
                Label("Trinken", systemImage: "wineglass")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(wine.isOutOfStock)
            .accessibilityLabel("Eine Flasche \(wine.name) trinken")
        }
    }
}

/// Eine Empfehlung: Rang, Wein, Begründung, Serviertipp, „Details“ und „Trinken“.
struct RecommendationCard: View {

    let recommendation: PairingRecommendation
    /// Der zugehörige Wein im Keller, falls zuordenbar.
    let wine: Wine?
    let onOpenBottle: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                rankBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.wineName)
                        .font(.headline)
                    if let wine {
                        Text(wine.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        // Kein Jahrgang bekannt: dann steht dort auch nichts.
                        if recommendation.vintage > 0 {
                            Text(String(recommendation.vintage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // Der Text bekommt den freien Platz zuerst, sonst teilt er ihn sich mit
                // dem Spacer und bricht unnötig um.
                .layoutPriority(1)

                Spacer(minLength: 8)

                if let wine {
                    LabelThumbnail(wine: wine, size: 52)
                }
            }

            fitBadge

            Text(recommendation.reasoning)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !recommendation.servingTip.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(.secondary)
                    Text(recommendation.servingTip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                if let wine {
                    StockBadge(quantity: Int(wine.quantity))
                    Spacer()
                    WineActionButtons(wine: wine, onOpenBottle: onOpenBottle)
                } else {
                    Label("Nicht im Keller gefunden", systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .cardStyle()
        .overlay(alignment: .topLeading) {
            if recommendation.rank == 1 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    /// Ehrliche Einstufung wie beim Sommelier: Perfekt, passt gut, geht, Notlösung.
    private var fitBadge: some View {
        let color: Color = switch recommendation.fit {
        case .excellent:  .green
        case .good:       .accentColor
        case .acceptable: .orange
        case .poor:       .red
        }
        return Label(recommendation.fit.displayName, systemImage: recommendation.fit.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Passung: \(recommendation.fit.displayName)")
    }

    private var rankBadge: some View {
        Text("\(recommendation.rank)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(recommendation.rank == 1 ? Color.accentColor : Color.secondary, in: Circle())
            .accessibilityLabel("Rang \(recommendation.rank)")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            RecommendationCard(
                recommendation: PreviewData.sampleResponse.recommendations[0],
                wine: PreviewData.sampleWines[1]
            ) { }
            RecommendationCard(
                recommendation: PreviewData.sampleResponse.recommendations[1],
                wine: nil
            ) { }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environment(\.managedObjectContext, PreviewData.context)
}
