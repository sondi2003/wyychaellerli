import SwiftUI

/// „Der Katalog in Zahlen“: grosse Zahl oben, darunter ein Mosaik aus Länderkacheln, deren
/// Fläche der Weinzahl folgt. Nur Anzeige – sie sagt nichts darüber, woher die Weine stammen.
struct CatalogMosaicCard: View {

    let overview: CatalogOverview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Abgestufte Weinrottöne: grösste Kachel am dunkelsten. Fest, nicht an den Hell- und
    /// Dunkelmodus gebunden, weil jede Kachel ihre eigene Fläche mit eigener Schrift ist.
    private static let ramp: [Color] = [
        Color(red: 0.49, green: 0.10, blue: 0.20), Color(red: 0.56, green: 0.17, blue: 0.26),
        Color(red: 0.63, green: 0.23, blue: 0.32), Color(red: 0.70, green: 0.29, blue: 0.38),
        Color(red: 0.76, green: 0.37, blue: 0.45), Color(red: 0.81, green: 0.46, blue: 0.52)
    ]
    /// Der Streifen „weitere Länder“ trägt ein tiefes Weinrot wie die Kacheln, mit weisser
    /// Schrift (Kontrast über 12 : 1). Früher ein heller Rosaton: Er stach aus dem Mosaik heraus.
    private static let othersBackground = Color(red: 0.38, green: 0.07, blue: 0.15)
    private static let darkText = Color(red: 0.30, green: 0.04, blue: 0.10)
    /// Rang eines Landes unter den Länderkacheln (0 = grösstes); der Streifen zählt nicht mit,
    /// sonst bekäme das grösste Land schon den zweiten Ton der Reihe.
    private static func rank(ofTileAt index: Int, in tiles: [CatalogMosaic.Tile]) -> Int {
        tiles[..<index].filter { if case .country = $0.content { return true } else { return false } }.count
    }

    /// Halber Abstand zwischen zwei Kacheln.
    private static let gutter: CGFloat = 3

    var body: some View {
        VStack(spacing: 10) {
            hero
            GeometryReader { proxy in
                let tiles = CatalogMosaic.tiles(for: overview.countries, in: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                        // Gleichmässiger Abstand: Jede Kachel wird ringsum eingerückt, zwei
                        // Nachbarn lassen also 2 × `gutter` zwischen sich, der Rand `gutter`.
                        let inner = tile.rect.insetBy(dx: Self.gutter, dy: Self.gutter)
                        tileView(tile, rank: Self.rank(ofTileAt: index, in: tiles), size: inner.size)
                            .frame(width: inner.width, height: inner.height)
                            .offset(x: inner.minX, y: inner.minY)
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.94)
                            .animation(
                                reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.15).delay(Double(index) * 0.05),
                                value: appeared
                            )
                    }
                }
                // Wächst der Katalog, gleiten die Kacheln an ihren neuen Platz.
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: tiles)
            }
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Der Katalog in Zahlen")
                .font(.footnote)
                .foregroundStyle(Brand.rose)
            Text("\(overview.total) Weine")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .default, value: overview.total)
            Text("aus \(overview.countries.count) Ländern")
                .font(.subheadline)
                .foregroundStyle(Brand.rose)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Kacheln

    @ViewBuilder
    private func tileView(_ tile: CatalogMosaic.Tile, rank: Int, size: CGSize) -> some View {
        switch tile.content {
        case .country(let country):
            let isLight = rank >= 5  // gemessen: ab Rang 5 hat Dunkelrot mehr Kontrast als Weiss
            let shortSide = min(size.width, size.height)
            VStack(alignment: .leading, spacing: 0) {
                if let flag = country.flag {
                    Text(verbatim: flag)
                        .font(.system(size: max(20, min(40, shortSide * 0.34))))
                }
                Spacer(minLength: 4)
                // Auf einer sehr kleinen Kachel bleibt nur die Zahl, der Name würde abgeschnitten.
                if shortSide >= 64 {
                    Text(verbatim: country.name)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(verbatim: "\(country.count)")
                    .font(.headline)
            }
            .foregroundStyle(isLight ? Self.darkText : .white)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Self.ramp[min(rank, Self.ramp.count - 1)], in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(country.name), \(tr("\(country.count) Weine"))"))

        case .others(let rest):
            let count = rest.reduce(0) { $0 + $1.count }
            HStack(spacing: 10) {
                Text(verbatim: rest.compactMap(\.flag).joined(separator: " "))
                    .font(.system(size: 18))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(0)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    if rest.count == 1, let only = rest.first {
                        Text(verbatim: only.name).font(.caption)
                    } else {
                        Text("weitere \(rest.count) Länder").font(.caption)
                    }
                    Text(verbatim: "\(count)").font(.headline)
                }
                .fixedSize()
                .layoutPriority(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Fester Grund, nicht an den Hell- und Dunkelmodus gebunden: Schrift und Fläche sind
            // zusammen entworfen (`Brand.blush` dunkelt im Dunkelmodus ab).
            .background(Self.othersBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: rest.count == 1
                ? "\(rest[0].name), \(tr("\(count) Weine"))"
                : "\(tr("weitere \(rest.count) Länder")), \(tr("\(count) Weine"))"))
        }
    }
}

#Preview {
    let entries: [(String, Int)] = [
        ("Chile", 193), ("Italien", 110), ("Argentinien", 97), ("USA", 96), ("Neuseeland", 96),
        ("Frankreich", 8), ("Schweiz", 8), ("Deutschland", 4), ("Portugal", 3), ("Spanien", 3),
        ("Südafrika", 2), ("Nordmazedonien", 1)
    ]
    let wines = entries.flatMap { country, count in
        (0..<count).map { index in
            CatalogWine(id: "\(country)\(index)", name: "Wein \(index)", producer: "", vintage: 2020, grape: "",
                        region: "", country: country, typeRaw: "red", alcoholPercent: 0, source: "")
        }
    }
    return CatalogMosaicCard(overview: CatalogOverview(entries: wines, locale: Locale(identifier: "de")))
        .padding()
}
