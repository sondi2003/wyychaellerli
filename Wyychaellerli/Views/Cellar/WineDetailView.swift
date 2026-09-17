import SwiftUI
import CoreData
import TipKit

/// Detailansicht eines Weins mit Bestandsverwaltung, Notizen, Archiv und Löschen.
struct WineDetailView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wine: Wine

    private let backLabelTip = BackLabelTip()

    @State private var isEditing = false
    @State private var isSharing = false
    @State private var isConfirmingDelete = false
    @State private var consumeCount = 0
    @State private var isRating = false
    /// Alle Flaschen liegen im Regal – dann muss beim Abbuchen das Fach gewählt werden.
    @State private var isTakingFromRack = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                stockCard
                WineRackCard(wine: wine)
                RatingCard(wine: wine) { isRating = true }
                factsCard
                if !wine.foodPairings.isEmpty {
                    pairingCard
                }
                WineOriginMapView(wine: wine)
                if !wine.notes.isEmpty {
                    notesCard
                }
                archiveCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(wine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSharing = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Wein empfehlen")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            WineFormView(mode: .edit(wine))
        }
        .sheet(isPresented: $isSharing) {
            WineShareSheet(wine: wine)
        }
        .sheet(isPresented: $isRating) {
            RatingSheet(wine: wine)
        }
        .sheet(isPresented: $isTakingFromRack) {
            WineRackSheet(wine: wine, mode: .take)
        }
        .confirmationDialog("Wein löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(wine)
                context.saveChanges()
                dismiss()
            }
        } message: {
            Text("„\(wine.nameWithVintage)“ wird dauerhaft entfernt.")
        }
        .sensoryFeedback(.decrease, trigger: consumeCount)
    }

    // MARK: Kopf

    /// Vorhandene Etikettseiten in fester Reihenfolge.
    private var labelPages: [LabelPage] {
        var pages: [LabelPage] = []
        if let image = wine.labelImage { pages.append(LabelPage(title: "Vorderseite", image: image)) }
        if let image = wine.backLabelImage { pages.append(LabelPage(title: "Rückseite", image: image)) }
        return pages
    }

    private var header: some View {
        VStack(spacing: 12) {
            if labelPages.isEmpty {
                WineTypeIcon(type: wine.type, size: 84)
            } else {
                // Der Tipp nur, wenn es eine Rückseite gibt – sonst gäbe es nichts zu wischen.
                // (Die Variante mit optionalem Tipp gibt es erst ab iOS 26.)
                if labelPages.count > 1 {
                    LabelPager(pages: labelPages, wineName: wine.name)
                        .padding(.bottom, 8)
                        .popoverTip(backLabelTip, arrowEdge: .top)
                } else {
                    LabelPager(pages: labelPages, wineName: wine.name)
                        .padding(.bottom, 8)
                }
            }
            if !wine.producer.isEmpty {
                Text(wine.producer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            Text(wine.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(wine.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(wine.type.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(wine.type.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(wine.type.color)
                // Herkunftsland als zweite Kapsel: Flagge plus Name, damit die Flagge
                // nicht geraten werden muss.
                if let flag = CountryFlag.emoji(for: wine.country) {
                    Text("\(flag) \(wine.country.trimmingCharacters(in: .whitespaces))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Herkunft \(wine.country)")
                }
            }
            maturityRow
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// Trinkreife samt Spanne. Nennt ausdrücklich, ob die Angabe vom Etikett stammt
    /// oder geschätzt ist – sonst liest sich eine Schätzung wie eine Tatsache.
    @ViewBuilder
    private var maturityRow: some View {
        if !wine.drinkWindowText.isEmpty {
            VStack(spacing: 2) {
                Label(wine.maturity.title, systemImage: wine.maturity.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(maturityColor)
                Text(wine.drinkWindowFromLabel
                     ? "Trinkreife \(wine.drinkWindowText) laut Etikett"
                     : "Trinkreife \(wine.drinkWindowText), geschätzt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private var maturityColor: Color {
        switch wine.maturity {
        case .drinkSoon: return .orange
        case .pastPeak:  return .red
        case .ready:     return .green
        default:         return .secondary
        }
    }

    // MARK: Bestand

    private var stockCard: some View {
        VStack(spacing: 16) {
            Text("Bestand")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 28) {
                Button {
                    // Solange Flaschen ohne Platz da sind, bleibt der schnelle Weg schnell.
                    // Erst wenn alles verortet ist, muss klar sein, welches Fach frei wird.
                    if wine.placedCount > 0, wine.unplacedCount == 0 {
                        isTakingFromRack = true
                    } else {
                        wine.consumeBottle()
                        consumeCount += 1
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(wine.isOutOfStock)
                .accessibilityLabel("Eine Flasche trinken")

                VStack(spacing: 2) {
                    Text("\(wine.quantity)")
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(wine.quantity == 1 ? "Flasche" : "Flaschen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 90)

                Button {
                    wine.addBottle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel("Eine Flasche hinzufügen")
            }
            .animation(.snappy, value: wine.quantity)

            if wine.isOutOfStock {
                CalloutBox(kind: .warning, text: "Keine Flasche mehr übrig. Du kannst den Wein archivieren oder löschen.")
            }
        }
        .cardStyle()
    }

    // MARK: Angaben

    /// Alles, was über den Wein erfasst ist, als Liste – der Kopf zeigt davon nur eine
    /// Kurzzeile, und die verschluckt Land oder Rebsorte, sobald es eng wird.
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
                            .gridColumnAlignment(.leading)
                        Text(fact.value)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private struct Fact {
        let label: String
        let value: String
    }

    /// Nur, was tatsächlich erfasst ist – leere Zeilen wären nur Rauschen.
    private var facts: [Fact] {
        var result: [Fact] = []
        if !wine.producer.isEmpty { result.append(Fact(label: "Produzent", value: wine.producer)) }
        if wine.vintage > 0 { result.append(Fact(label: "Jahrgang", value: String(wine.vintage))) }
        result.append(Fact(label: "Weinart", value: wine.type.displayName))
        if !wine.grape.isEmpty { result.append(Fact(label: "Rebsorte", value: wine.grape)) }
        if !wine.region.isEmpty { result.append(Fact(label: "Region", value: wine.region)) }
        if !wine.country.isEmpty {
            let flag = CountryFlag.emoji(for: wine.country).map { "\($0) " } ?? ""
            result.append(Fact(label: "Land", value: flag + wine.country))
        }
        if wine.hasAlcohol, let strength = wine.strength {
            result.append(Fact(label: "Alkohol", value: "\(wine.alcoholText) · \(strength.title)"))
        }
        if !wine.drinkWindowText.isEmpty {
            result.append(Fact(label: "Trinkreife", value: wine.drinkWindowText + (wine.drinkWindowFromLabel ? " (Etikett)" : " (geschätzt)")))
        }
        if let date = wine.createdAt {
            result.append(Fact(label: "Erfasst", value: date.formatted(date: .abbreviated, time: .omitted)))
        }
        return result
    }

    // MARK: Speiseempfehlung vom Etikett

    /// Nur sichtbar, wenn auf dem Etikett tatsächlich etwas dazu steht.
    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Passt laut Etikett zu", systemImage: "fork.knife")
                .font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(wine.foodPairings, id: \.self) { pairing in
                    Text(pairing)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(wine.type.color.opacity(0.12), in: Capsule())
                        .foregroundStyle(wine.type.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Notizen

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notizen")
                .font(.headline)
            Text(wine.notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    // MARK: Archiv / Löschen

    private var archiveCard: some View {
        VStack(spacing: 12) {
            Button {
                wine.isArchived.toggle()
                wine.managedObjectContext?.saveChanges()
            } label: {
                Label(
                    wine.isArchived ? "Zurück in den Keller" : "Archivieren",
                    systemImage: wine.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }
}

#Preview {
    NavigationStack {
        WineDetailView(wine: PreviewData.sampleWines[0])
    }
    .environment(\.managedObjectContext, PreviewData.context)
}
