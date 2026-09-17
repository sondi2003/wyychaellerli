import SwiftUI

/// Gleichstand an der Spitze: Das Los entscheidet, sichtbar für alle am Tisch.
///
/// Die gleichauf liegenden Flaschen leuchten der Reihe nach auf, immer langsamer –
/// wie ein Glücksrad, das ausläuft. Wer zusieht, glaubt dem Ergebnis eher, als wenn
/// nur eine Zahl erschiene.
struct PartyDrawView: View {

    @Bindable var model: PartyViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leaders: [Wine] {
        model.state.leaders().compactMap { model.wine(for: $0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Gleichstand")
                    .font(.title2.weight(.bold))
                Text("\(leaders.count) Flaschen liegen vorn. Das Los entscheidet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(leaders) { wine in
                        let isLit = model.drawHighlight == wine.uuid
                        HStack(spacing: 14) {
                            LabelThumbnail(wine: wine, size: 54)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wine.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(wine.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            // Der Text bekommt den freien Platz zuerst, sonst teilt er
                            // ihn sich mit dem Spacer und bricht zu früh ab.
                            .layoutPriority(1)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isLit ? Color.accentColor.opacity(0.22) : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isLit ? Color.accentColor : Color.clear, lineWidth: 3)
                        }
                        .scaleEffect(isLit && !reduceMotion ? 1.03 : 1)
                        .animation(.easeOut(duration: 0.12), value: isLit)
                    }
                }
                .padding(.horizontal)
            }

            Button {
                Task { await model.runDraw() }
            } label: {
                Label(model.isDrawing ? "Wird ausgelost …" : "Losen", systemImage: "dice.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isDrawing)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}

/// Das Podest: Sieger gross in der Mitte, zweiter und dritter Platz daneben.
struct PartyPodiumView: View {

    @Bindable var model: PartyViewModel
    let onFinish: () -> Void

    /// Löst den Konfettiregen aus, sobald das Podest erscheint.
    @State private var celebrate = false

    private var places: [(wine: Wine, votes: Int)] { model.podium() }

    var body: some View {
        content
            .overlay {
                if celebrate {
                    ConfettiView()
                }
            }
            .onAppear {
                celebrate = true
            }
            .sensoryFeedback(.success, trigger: celebrate)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let winner = model.winner {
                    winnerCard(winner)
                }

                if places.count > 1 {
                    podium
                }

                summary

                Button(action: onFinish) {
                    Label("Party beenden", systemImage: "lock.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Text("Das Ergebnis wird in der Historie gesichert. Danach kannst du die Flasche wie gewohnt öffnen – die App zeigt dir das Regalfach.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .padding(.top, 20)
        }
    }

    // MARK: Sieger

    private func winnerCard(_ wine: Wine) -> some View {
        VStack(spacing: 14) {
            Text("🏆")
                .font(.system(size: 52))

            Text("Die Siegerflasche")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let image = wine.labelImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
            } else {
                WineTypeIcon(type: wine.type, size: 96)
            }

            VStack(spacing: 4) {
                if !wine.producer.isEmpty {
                    Text(wine.producer)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Text(wine.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(wine.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let votes = places.first?.votes {
                Text(model.state.wasDrawn
                     ? "\(votes) \(votes == 1 ? "Stimme" : "Stimmen") – per Los entschieden"
                     : "\(votes) von \(model.state.totalVotes) Stimmen")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            // Jetzt muss jemand die Flasche holen – hier gehört das Fach hin, nicht
            // während der Abstimmung.
            if !wine.storageSummary.isEmpty {
                Label("Liegt in \(wine.storageSummary)", systemImage: "square.grid.3x3")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: Plätze 2 und 3

    private var podium: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if places.count > 1 { step(places[1], place: 2, height: 84) }
            if places.count > 2 { step(places[2], place: 3, height: 64) }
        }
        .padding(.horizontal)
    }

    private func step(_ entry: (wine: Wine, votes: Int), place: Int, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            LabelThumbnail(wine: entry.wine, size: 46)
            Text(entry.wine.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(entry.votes) \(entry.votes == 1 ? "Stimme" : "Stimmen")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                Text("\(place)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Zusammenfassung

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("So wurde gestimmt")
                .font(.headline)
            // Nur Summen, nie wer für was – das hält den Frieden am Tisch.
            ForEach(Array(model.state.ranking().enumerated()), id: \.offset) { _, entry in
                if let wine = model.wine(for: entry.id) {
                    HStack {
                        Text(wine.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        Text("\(entry.votes)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(entry.votes > 0 ? .primary : .tertiary)
                            .fixedSize()
                    }
                }
            }
            Divider()
            Text("\(model.state.guests.filter(\.hasVoted).count) von \(model.state.guests.count) Anwesenden haben gestimmt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
