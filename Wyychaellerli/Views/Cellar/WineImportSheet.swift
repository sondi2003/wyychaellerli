import CoreData
import SwiftUI

/// Ein empfohlener Wein ist angekommen – übernehmen oder verwerfen.
///
/// Bevor etwas im Keller landet, sieht man, was kommt. Und die App prüft, ob die
/// Flasche schon da ist: Sonst stünde sie nach einer Empfehlung zweimal in der Liste.
struct WineImportSheet: View {

    let share: WineShare

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var duplicate: Wine?
    @State private var didImport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let duplicate {
                        duplicateCard(duplicate)
                    }
                    factsCard
                    if !share.comment.isEmpty {
                        commentCard
                    }
                    actions
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Empfehlung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
            }
            .onAppear {
                duplicate = DuplicateFinder.findDuplicates(of: share.duplicateCandidate, in: context).first?.wine
            }
        }
    }

    // MARK: Kopf

    private var header: some View {
        VStack(spacing: 12) {
            if let image = share.labelImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            } else {
                WineTypeIcon(type: share.wineType, size: 84)
            }

            Text(share.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if !share.subtitle.isEmpty {
                Text(share.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(share.wineType.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(share.wineType.color.opacity(0.15), in: Capsule())
                .foregroundStyle(share.wineType.color)

            if !share.senderName.isEmpty {
                Text("Empfohlen von \(share.senderName)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Karten

    private func duplicateCard(_ wine: Wine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Den hast du schon", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("„\(wine.nameWithVintage)“ liegt bereits in deinem Keller\(wine.isArchived ? " (im Archiv)" : ", Bestand \(wine.quantity)"). Übernimmst du ihn trotzdem, steht er zweimal in der Liste.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hinweis", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
            Text(share.comment)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var factsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Angaben")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(facts, id: \.label) { fact in
                    GridRow {
                        Text(fact.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(fact.value)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !share.notes.isEmpty {
                Divider()
                Text(share.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private struct Fact {
        let label: String
        let value: String
    }

    private var facts: [Fact] {
        var result: [Fact] = []
        if !share.producer.isEmpty { result.append(Fact(label: "Produzent", value: share.producer)) }
        if share.hasVintage { result.append(Fact(label: "Jahrgang", value: String(share.vintage))) }
        result.append(Fact(label: "Weinart", value: share.wineType.displayName))
        if !share.grape.isEmpty { result.append(Fact(label: "Rebsorte", value: share.grape)) }
        if let strength = Wine.Strength.from(percent: share.alcoholPercent) {
            let percent = share.alcoholPercent.formatted(.number.precision(.fractionLength(0...1)))
            result.append(Fact(label: "Alkohol", value: "\(percent) % · \(strength.title)"))
        }
        if !share.region.isEmpty { result.append(Fact(label: "Region", value: share.region)) }
        if !share.country.isEmpty {
            let flag = CountryFlag.emoji(for: share.country).map { "\($0) " } ?? ""
            result.append(Fact(label: "Land", value: flag + share.country))
        }
        if share.drinkFrom > 0, share.drinkTo >= share.drinkFrom {
            result.append(Fact(label: "Trinkreife", value: "\(share.drinkFrom)–\(share.drinkTo)"))
        }
        if !share.foodPairings.isEmpty {
            result.append(Fact(label: "Passt zu", value: share.foodPairings.joined(separator: ", ")))
        }
        return result
    }

    // MARK: Übernehmen

    @ViewBuilder
    private var actions: some View {
        if didImport {
            Label("In deinen Keller übernommen", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Button {
                share.importing(into: context)
                didImport = true
            } label: {
                Label(duplicate == nil ? "In meinen Keller übernehmen" : "Trotzdem übernehmen",
                      systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Text("Wird mit Bestand 1 angelegt. Etikett, Notizen und Trinkreife kommen mit.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
