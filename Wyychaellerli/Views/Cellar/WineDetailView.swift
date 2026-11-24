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
    /// Die Kachel „Etikett“ im Kopf öffnet das Formular gleich mit dem Scanner.
    @State private var isAddingLabel = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                stockCard
                WineRackCard(wine: wine)
                RatingCard(wine: wine) { isRating = true }
                // Was man vor dem Öffnen wissen will, steht oben: wozu er passt. Der
                // gemeinsame Katalog ist Beiwerk und steht am Schluss.
                if !wine.foodPairings.isEmpty {
                    pairingCard
                }
                factsCard
                if !wine.notes.isEmpty {
                    notesCard
                }
                WineOriginMapView(wine: wine)
                CatalogStatusCard(wine: wine)
                archiveButtons
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
        .sheet(isPresented: $isAddingLabel) {
            WineFormView(mode: .edit(wine), startWithScanner: true)
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
        if let image = wine.labelImage { pages.append(LabelPage(title: tr("Vorderseite"), image: image)) }
        if let image = wine.backLabelImage { pages.append(LabelPage(title: tr("Rückseite"), image: image)) }
        return pages
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mit Foto die grosse Bühne. Ohne Foto wäre sie eine leere Fläche über dem
            // Namen – dann steht links eine kleine Kachel, die zum Fotografieren einlädt.
            if !labelPages.isEmpty {
                labelStage
            }

            HStack(alignment: .top, spacing: 14) {
                if labelPages.isEmpty {
                    labelInvite
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !wine.producer.isEmpty {
                        Text(wine.producer)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text(wine.nameWithVintage)
                        .font(.title2.weight(.bold))
                    originRow
                    if !wine.grape.isEmpty {
                        Text(wine.grape)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                ratingBadge
            }

            HStack(spacing: 8) {
                Text(wine.type.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(wine.type.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(wine.type.color)
                maturityRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Platzhalter ohne Foto: gestrichelte Kachel im Hochformat eines Etiketts.
    private var labelInvite: some View {
        Button {
            isAddingLabel = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "camera")
                    .font(.title3.weight(.semibold))
                Text("Etikett")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Brand.accent)
            .frame(width: 84, height: 104)
            .background(Brand.blush, in: RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous)
                    .strokeBorder(Brand.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Etikett fotografieren")
    }

    /// Etikett auf zartem Grund, wie die Flasche auf der Bühne der Vorlage.
    @ViewBuilder
    private var labelStage: some View {
        Group {
            if labelPages.count > 1 {
                // Der Tipp nur, wenn es eine Rückseite gibt – sonst gäbe es nichts zu wischen.
                // (Die Variante mit optionalem Tipp gibt es erst ab iOS 26.)
                LabelPager(pages: labelPages, wineName: wine.name)
                    .popoverTip(backLabelTip, arrowEdge: .top)
            } else {
                LabelPager(pages: labelPages, wineName: wine.name)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Brand.blush, in: RoundedRectangle(cornerRadius: Brand.Radius.large, style: .continuous))
    }

    /// Flagge und „Region, Land“ in einer Zeile. Ohne bekannte Flagge steht nur der Text.
    @ViewBuilder
    private var originRow: some View {
        let place = [wine.region, wine.country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if !place.isEmpty {
            HStack(spacing: 6) {
                if let flag = CountryFlag.emoji(for: wine.country) {
                    Text(verbatim: flag)
                }
                Text(verbatim: place)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Herkunft \(place)")
        }
    }

    /// Gemeinsamer Mittelwert gross, darunter die Sterne – nur wenn bewertet wurde.
    @ViewBuilder
    private var ratingBadge: some View {
        if let average = wine.averageRating {
            VStack(spacing: 4) {
                Text(average.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                StarRatingView(value: .constant(average), isEditable: false, size: 13)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }

    /// Trinkreife samt Spanne. Nennt ausdrücklich, ob die Angabe vom Etikett stammt
    /// oder geschätzt ist – sonst liest sich eine Schätzung wie eine Tatsache.
    @ViewBuilder
    private var maturityRow: some View {
        if !wine.drinkWindowText.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label(wine.maturity.title, systemImage: wine.maturity.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(maturityColor)
                Text(wine.drinkWindowFromLabel
                     ? "Trinkreife \(wine.drinkWindowText) laut Etikett"
                     : "Trinkreife \(wine.drinkWindowText), geschätzt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var maturityColor: Color {
        switch wine.maturity {
        case .drinkSoon: return Brand.warning
        case .pastPeak:  return Brand.danger
        case .ready:     return Brand.success
        default:         return .secondary
        }
    }

    // MARK: Bestand

    /// Zahl und zwei leise Knöpfe zum Korrigieren, darunter die eine Hauptaktion in Grün.
    private var stockCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(wine.quantity)")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(verbatim: bottleWord(Int(wine.quantity)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                stepButton("minus", label: "Eine Flasche trinken", action: consume)
                    .disabled(wine.isOutOfStock)
                stepButton("plus", label: "Eine Flasche hinzufügen") { wine.addBottle() }
            }
            .animation(.snappy, value: wine.quantity)

            Button(action: consume) {
                Label("Eine Flasche trinken", systemImage: "wineglass")
            }
            .buttonStyle(.brand(.action, large: true))
            .disabled(wine.isOutOfStock)

            if wine.isOutOfStock {
                CalloutBox(kind: .warning, text: tr("Keine Flasche mehr übrig. Du kannst den Wein archivieren oder löschen."))
            }
        }
        .cardStyle()
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Brand.accent)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Solange Flaschen ohne Platz da sind, bleibt der schnelle Weg schnell.
    /// Erst wenn alles verortet ist, muss klar sein, welches Fach frei wird.
    private func consume() {
        if wine.placedCount > 0, wine.unplacedCount == 0 {
            isTakingFromRack = true
        } else {
            wine.consumeBottle()
            consumeCount += 1
        }
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
        if !wine.producer.isEmpty { result.append(Fact(label: tr("Produzent"), value: wine.producer)) }
        if wine.vintage > 0 { result.append(Fact(label: tr("Jahrgang"), value: String(wine.vintage))) }
        result.append(Fact(label: tr("Weinart"), value: wine.type.displayName))
        if !wine.grape.isEmpty { result.append(Fact(label: tr("Rebsorte"), value: wine.grape)) }
        if !wine.region.isEmpty { result.append(Fact(label: tr("Region"), value: wine.region)) }
        if !wine.country.isEmpty {
            let flag = CountryFlag.emoji(for: wine.country).map { "\($0) " } ?? ""
            result.append(Fact(label: tr("Land"), value: flag + wine.country))
        }
        if wine.hasAlcohol, let strength = wine.strength {
            result.append(Fact(label: tr("Alkohol"), value: "\(wine.alcoholText) · \(strength.title)"))
        }
        if !wine.drinkWindowText.isEmpty {
            result.append(Fact(label: tr("Trinkreife"), value: wine.drinkWindowText + " (" + (wine.drinkWindowFromLabel ? tr("Etikett") : tr("geschätzt")) + ")"))
        }
        if !wine.barcode.isEmpty {
            result.append(Fact(label: tr("Strichcode"), value: wine.barcode))
        }
        if let date = wine.createdAt {
            result.append(Fact(label: tr("Erfasst"), value: date.appShortDate))
        }
        return result
    }

    // MARK: Speiseempfehlung vom Etikett

    /// Nur sichtbar, wenn auf dem Etikett tatsächlich etwas dazu steht.
    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Passt zu", systemImage: "fork.knife")
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

    /// Nebeneinander und ohne Karte: Archivieren ruhig umrandet, Löschen rot umrandet –
    /// zwei gleich aussehende Knöpfe untereinander luden zum Verwechseln ein.
    private var archiveButtons: some View {
        HStack(spacing: 10) {
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
            .buttonStyle(.brandOutline)

            Button {
                isConfirmingDelete = true
            } label: {
                Label("Löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brand(.destructive))
        }
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack {
        WineDetailView(wine: PreviewData.sampleWines[0])
    }
    .environment(\.managedObjectContext, PreviewData.context)
    .environment(CatalogCenter())
}
