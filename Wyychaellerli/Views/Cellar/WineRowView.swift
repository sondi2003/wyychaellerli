import SwiftUI

/// Eine Zeile in der Kellerliste: Icon, Name, Jahrgang/Region, Bestand und Minus-Button.
///
/// `@ObservedObject`, nicht `let`: Wird die Flasche anderswo abgebucht (Berater,
/// Detailseite, anderes Gerät), muss die Zeile den neuen Bestand von selbst zeigen.
struct WineRowView: View {

    @ObservedObject var wine: Wine
    let onConsume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LabelThumbnail(wine: wine, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(wine.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    // Die Flagge steht vor der Herkunft, weil sie dazugehört.
                    // Sie ersetzt den Landesnamen im Text, statt ihn zu wiederholen.
                    if let flag = CountryFlag.emoji(for: wine.country) {
                        Text(flag)
                            .accessibilityLabel(wine.country)
                        Text(wine.subtitleWithoutCountry)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(wine.subtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.subheadline)

                // Eigene Zeile für die kleinen Abzeichen. Der Alkoholgehalt stand vorher
                // hinter der Herkunft und hat sie auf zwei Buchstaben zusammengedrückt;
                // hier hat beides Platz, und die Trinkreife teilt sich die Zeile.
                if wine.strength != nil || wine.needsDrinkingSoon {
                    HStack(spacing: 10) {
                        // Auf einen Blick, ob die Flasche schwer ist – Tacho plus Zahl.
                        // Ohne Angabe steht hier nichts, statt eine Null zu behaupten.
                        if let strength = wine.strength {
                            Label(wine.alcoholText, systemImage: strength.symbolName)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .accessibilityLabel("\(strength.title), \(wine.alcoholText) Alkohol")
                        }
                        // Nur die beiden Zustände, die zum Handeln auffordern. „Trinkreif“
                        // und „zu jung“ stünden bei fast jeder Flasche – nur Rauschen.
                        if wine.needsDrinkingSoon {
                            Label(wine.maturity.title, systemImage: wine.maturity.symbolName)
                                .foregroundStyle(wine.maturity == .pastPeak ? .red : .orange)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .padding(.top, 1)
                }
            }
            // Ohne Vorrang teilt sich der Textblock den freien Platz gleichmässig mit
            // dem Spacer darunter – dann bricht die Herkunft mitten im Wort ab, während
            // rechts daneben Leerraum steht. Der Text bekommt den Platz zuerst.
            .layoutPriority(1)

            Spacer(minLength: 8)

            StockBadge(quantity: Int(wine.quantity))

            if !wine.isArchived {
                Button(action: onConsume) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(wine.isOutOfStock ? Color.secondary.opacity(0.4) : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(wine.isOutOfStock)
                .accessibilityLabel("Eine Flasche \(wine.name) trinken")
            }
        }
        .padding(.vertical, 4)
        .opacity(wine.isOutOfStock && !wine.isArchived ? 0.6 : 1)
        .contentTransition(.numericText())
        .animation(.snappy, value: wine.quantity)
    }
}

#Preview {
    List {
        WineRowView(wine: PreviewData.sampleWines[0]) { }
        WineRowView(wine: PreviewData.sampleWines[3]) { }
    }
    .environment(\.managedObjectContext, PreviewData.context)
}
