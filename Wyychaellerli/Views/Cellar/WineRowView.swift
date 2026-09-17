import SwiftUI

/// Eine Zeile in der Kellerliste, von oben nach unten: Name, Flagge mit Jahrgang,
/// Region, Rebsorte, Alkoholgehalt – daneben Bestand und Minus-Knopf.
///
/// Jede Angabe hat ihre eigene Etage, weil sie sich sonst gegenseitig abschneiden.
/// Fehlt eine, entfällt ihre Zeile ganz.
///
/// `@ObservedObject`, nicht `let`: Wird die Flasche anderswo abgebucht (Berater,
/// Detailseite, anderes Gerät), muss die Zeile den neuen Bestand von selbst zeigen.
struct WineRowView: View {

    @ObservedObject var wine: Wine
    let onConsume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LabelThumbnail(wine: wine, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(wine.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                // Herkunft und Jahrgang. Die Flagge sagt das Land bereits – der Name
                // stünde nur doppelt daneben. Ohne Flagge (unbekanntes Land) tritt der
                // Landesname an ihre Stelle, damit die Angabe nicht verschwindet.
                if !wine.country.isEmpty || wine.hasVintage {
                    HStack(spacing: 5) {
                        if let flag = CountryFlag.emoji(for: wine.country) {
                            Text(flag)
                                .accessibilityLabel(wine.country)
                            Text(wine.vintageText)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text([wine.country, wine.vintageText].filter { !$0.isEmpty }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.subheadline)
                }

                if !wine.region.isEmpty {
                    Text(wine.region)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Die Rebsorte auf eigener Zeile: Sie ist das, wonach man sucht, und
                // neben dem Alkoholgehalt wurde sie regelmässig abgeschnitten.
                if !wine.grape.isEmpty {
                    Text(wine.grape)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Zuunterst die kleinen Abzeichen. Der Alkoholgehalt stand früher hinter
                // der Herkunft und hat sie auf zwei Buchstaben zusammengedrückt; hier hat
                // er Platz, und die Trinkreife teilt sich die Zeile mit ihm.
                if wine.strength != nil || wine.needsDrinkingSoon {
                    HStack(spacing: 10) {
                        // Auf einen Blick, ob die Flasche schwer ist – Tacho plus Zahl.
                        // Ohne Angabe steht hier nichts, statt eine Null zu behaupten.
                        if let strength = wine.strength {
                            Label(wine.alcoholText, systemImage: strength.symbolName)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize()
                                .accessibilityLabel("\(strength.title), \(wine.alcoholText) Alkohol")
                        }
                        // Nur die beiden Zustände, die zum Handeln auffordern. „Trinkreif“
                        // und „zu jung“ stünden bei fast jeder Flasche – nur Rauschen.
                        if wine.needsDrinkingSoon {
                            Label(wine.maturity.title, systemImage: wine.maturity.symbolName)
                                .foregroundStyle(wine.maturity == .pastPeak ? .red : .orange)
                        }
                        Spacer(minLength: 0)
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
