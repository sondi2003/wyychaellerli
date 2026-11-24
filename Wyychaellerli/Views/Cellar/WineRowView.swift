import SwiftUI

/// Eine Zeile in der Kellerliste: Name, darunter Herkunft (Flagge, Jahrgang, Region),
/// darunter Rebsorte und Alkoholgehalt – rechts der Bestand.
///
/// Drei Textzeilen statt fünf: So passen etwa doppelt so viele Weine auf den Bildschirm.
/// Fehlt eine Angabe, entfällt sie; fehlt eine ganze Zeile, rückt der Rest nach.
/// Abgebucht wird mit einem Wisch nach rechts (`CellarView`), nicht mehr mit einem
/// Minus-Knopf in jeder Zeile – sechs rote Knöpfe untereinander waren lauter als die Namen.
///
/// `@ObservedObject`, nicht `let`: Wird die Flasche anderswo abgebucht (Berater,
/// Detailseite, anderes Gerät), muss die Zeile den neuen Bestand von selbst zeigen.
struct WineRowView: View {

    @ObservedObject var wine: Wine

    /// Jahrgang und Region. Die Flagge sagt das Land bereits; ohne Flagge (unbekanntes
    /// Land) tritt der Landesname an ihre Stelle, damit die Angabe nicht verschwindet.
    private var originText: String {
        var parts: [String] = []
        if CountryFlag.emoji(for: wine.country) == nil, !wine.country.isEmpty { parts.append(wine.country) }
        if wine.hasVintage { parts.append(wine.vintageText) }
        if !wine.region.isEmpty { parts.append(wine.region) }
        return parts.joined(separator: " · ")
    }

    /// Rebsorte und Alkoholgehalt. Ohne Angabe steht nichts da, statt eine Null zu behaupten.
    private var detailText: String {
        var parts: [String] = []
        if !wine.grape.isEmpty { parts.append(wine.grape) }
        if wine.strength != nil { parts.append(wine.alcoholText) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            LabelThumbnail(wine: wine, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                // Zwei Zeilen für den Namen: Umbrechen statt abschneiden ist der einzige
                // Weg, bei dem der ganze Name lesbar bleibt; nur lange Namen kosten Höhe.
                Text(wine.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                let flag = CountryFlag.emoji(for: wine.country)
                if flag != nil || !originText.isEmpty {
                    HStack(spacing: 5) {
                        if let flag {
                            Text(flag)
                                .accessibilityLabel(wine.country)
                        }
                        Text(originText)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                }

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Nur die beiden Zustände, die zum Handeln auffordern. „Trinkreif“
                // und „zu jung“ stünden bei fast jeder Flasche – nur Rauschen.
                // Schrift in Textfarbe auf getöntem Grund: Orange auf Weiss wäre zu schwach.
                if wine.needsDrinkingSoon {
                    let tone: Color = wine.maturity == .pastPeak ? Brand.danger : Brand.warning
                    // `HStack` statt `Label`: Das Label liess zwischen Symbol und Text eine Lücke
                    // von fast einer Symbolbreite.
                    HStack(spacing: 4) {
                        Image(systemName: wine.maturity.symbolName)
                            .foregroundStyle(tone)
                        Text(wine.maturity.title)
                    }
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tone.opacity(0.16), in: Capsule())
                    .padding(.top, 2)
                }
            }
            // Ohne Vorrang teilt sich der Textblock den freien Platz gleichmässig mit
            // dem Spacer darunter – dann bricht die Herkunft mitten im Wort ab, während
            // rechts daneben Leerraum steht. Der Text bekommt den Platz zuerst.
            .layoutPriority(1)

            Spacer(minLength: 8)

            StockBadge(quantity: Int(wine.quantity))
        }
        .padding(.vertical, 4)
        .opacity(wine.isOutOfStock && !wine.isArchived ? 0.6 : 1)
        .contentTransition(.numericText())
        .animation(.snappy, value: wine.quantity)
    }
}

#Preview {
    List {
        WineRowView(wine: PreviewData.sampleWines[0])
        WineRowView(wine: PreviewData.sampleWines[3])
    }
    .environment(\.managedObjectContext, PreviewData.context)
}
