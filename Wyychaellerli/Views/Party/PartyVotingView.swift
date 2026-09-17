import SwiftUI

/// Schritt 3: Der Gast am Gerät vergibt seine Stimmen.
///
/// **Kein Zwischenstand.** Wer sieht, dass der Barolo schon vier Stimmen hat, stimmt
/// anders – deshalb steht hier nur, wie viele eigene Stimmen noch übrig sind.
struct PartyVotingView: View {

    @Bindable var model: PartyViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.candidates) { wine in
                        PartyWineCard(
                            wine: wine,
                            isChosen: wine.uuid.map { model.hasVoted(for: $0) } ?? false,
                            canChoose: model.remainingVotes > 0
                        ) {
                            guard let id = wine.uuid else { return }
                            withAnimation(.snappy) { model.toggleVote(for: id) }
                        }
                    }
                }
                .padding()
            }

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let guest = model.state.currentGuest {
                    Text(guest.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                // Punkte statt Zahl: auf einen Blick erfassbar, auch angeheitert.
                HStack(spacing: 5) {
                    ForEach(0..<model.state.votesPerGuest, id: \.self) { index in
                        Image(systemName: index < model.state.currentVotes.count ? "circle.fill" : "circle")
                            .font(.footnote)
                            .foregroundStyle(index < model.state.currentVotes.count ? Color.accentColor : Color.secondary.opacity(0.4))
                    }
                }
                Text(model.remainingVotes == 0
                     ? "alle vergeben"
                     : "noch \(model.remainingVotes)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Button {
                withAnimation { model.finishTurn() }
            } label: {
                Text(model.remainingVotes == 0 ? "Fertig, weitergeben" : "Fertig")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.state.currentVotes.isEmpty)

            Text("Antippen wählt, nochmals antippen nimmt zurück.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .animation(.snappy, value: model.state.currentVotes)
    }
}

/// Eine Flasche zur Wahl.
///
/// Zeigt bewusst **nicht**: eure Sterne, den Bestand oder das Regalfach. Alles davon
/// würde die Wahl beeinflussen oder geht die Gäste schlicht nichts an.
struct PartyWineCard: View {

    @ObservedObject var wine: Wine
    let isChosen: Bool
    let canChoose: Bool
    let onTap: () -> Void

    @State private var isZooming = false

    private var pages: [LabelPage] {
        var result: [LabelPage] = []
        if let image = wine.labelImage { result.append(LabelPage(title: "Vorderseite", image: image)) }
        if let image = wine.backLabelImage { result.append(LabelPage(title: "Rückseite", image: image)) }
        return result
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    thumbnail

                    VStack(alignment: .leading, spacing: 3) {
                        if !wine.producer.isEmpty {
                            Text(wine.producer)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .lineLimit(1)
                        }
                        Text(wine.name)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            if let flag = CountryFlag.emoji(for: wine.country) {
                                Text(flag).font(.caption)
                            }
                            Text(wine.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Text(wine.type.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(wine.type.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(wine.type.color)
                            .padding(.top, 2)
                    }
                    // Der Text bekommt den freien Platz zuerst, sonst teilt er ihn sich
                    // mit dem Spacer und bricht unnötig um.
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isChosen ? Color.accentColor : Color.secondary.opacity(0.35))
                }

                if !wine.foodPairings.isEmpty {
                    Label(wine.foodPairings.prefix(4).joined(separator: " · "), systemImage: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if !wine.notes.isEmpty {
                    Text(wine.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isChosen ? Color.accentColor : Color.clear, lineWidth: 2.5)
            }
            .opacity(canChoose || isChosen ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isZooming) {
            LabelZoomView(pages: pages, selection: 0)
        }
    }

    /// Das Etikett – antippbar zum Vergrössern, ohne dass dabei eine Stimme fällt.
    @ViewBuilder
    private var thumbnail: some View {
        if pages.isEmpty {
            WineTypeIcon(type: wine.type, size: 64)
        } else {
            LabelThumbnail(wine: wine, size: 64)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2.weight(.semibold))
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(3)
                }
                .onTapGesture { isZooming = true }
        }
    }
}
