import CoreGraphics
import Foundation

/// Der Katalog in Zahlen: wie viele Weine, aus welchen Ländern.
///
/// Rechnet nur aus der Liste, die ohnehin auf dem Gerät liegt (`CatalogDirectory`) – kein
/// neues Feld, keine Abfrage. Die Länder kommen aus den Daten und nicht aus einer Liste im
/// Code: Kommt ein Land dazu, erscheint es von selbst. Gezeigt wird nur, was der Katalog
/// enthält; **wer die Weine geliefert hat, steht nirgends** (Quelle und Ersteller sind hier
/// bewusst nicht einmal gelesen).
struct CatalogOverview: Equatable, Sendable {

    struct Country: Identifiable, Equatable, Sendable {
        /// ISO-Code, sonst der Name, wie er steht – „Schweiz“ und „Suisse“ sind ein Land.
        let id: String
        let name: String
        let flag: String?
        let count: Int
    }

    /// Alle Weine, auch die ohne Landesangabe.
    let total: Int
    /// Absteigend nach Weinzahl.
    let countries: [Country]

    /// Darunter wirkt die Karte dünn („12 Weine aus 3 Ländern“). Dann bleibt sie weg.
    static let minimumForDisplay = 200

    var isWorthShowing: Bool { total >= Self.minimumForDisplay }

    init(entries: [CatalogWine], locale: Locale) {
        total = entries.count
        let withCountry = entries.map(\.country).filter { !$0.isEmpty }
        let groups = Dictionary(grouping: withCountry) { CountryFlag.regionCode(for: $0) ?? $0 }
        countries = groups
            .map { key, names in
                let raw = names[0]
                return Country(
                    id: key,
                    name: CountryFlag.displayName(for: raw, locale: locale) ?? raw,
                    flag: CountryFlag.emoji(for: raw),
                    count: names.count
                )
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }
}

/// Anordnung der Kacheln: Die Fläche folgt der Weinzahl.
///
/// Die grossen Länder bekommen je eine Kachel, alle übrigen fassen sich in einem Streifen
/// unten zusammen. Wie viele Kacheln es sind, ergibt sich aus den Daten: Ein Land braucht
/// mindestens 3 % aller Weine, höchstens sechs. Ohne Rest entfällt der Streifen.
enum CatalogMosaic {

    struct Tile: Identifiable, Equatable {
        enum Content: Equatable {
            case country(CatalogOverview.Country)
            case others([CatalogOverview.Country])
        }
        let content: Content
        let rect: CGRect

        var id: String {
            switch content {
            case .country(let country): return country.id
            case .others: return "others"
            }
        }
    }

    static let maxTiles = 6
    static let minimumShare = 0.03

    static func tiles(
        for countries: [CatalogOverview.Country],
        in size: CGSize,
        stripHeight: CGFloat = 56
    ) -> [Tile] {
        guard !countries.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let total = Double(countries.reduce(0) { $0 + $1.count })
        var big: [CatalogOverview.Country] = []
        for (index, country) in countries.enumerated() {
            guard index < maxTiles, index == 0 || Double(country.count) / total >= minimumShare else { break }
            big.append(country)
        }
        let rest = Array(countries.dropFirst(big.count))

        var tiles: [Tile] = []
        var area = CGRect(origin: .zero, size: size)
        if !rest.isEmpty {
            let strip = min(stripHeight, size.height / 3)
            tiles.append(Tile(
                content: .others(rest),
                rect: CGRect(x: 0, y: size.height - strip, width: size.width, height: strip)
            ))
            area.size.height -= strip
        }
        tiles += rows(of: big, in: area)
        return tiles
    }

    /// Ordnet die Länder in **Zeilen** an: Jede Zeile spannt die ganze Breite, ihre Höhe folgt
    /// der Summe ihrer Länder, die Breite je Land seinem Anteil an der Zeile. So laufen alle
    /// Kanten durch – eine Zeile endet nie versetzt zu einer anderen. Der frühere Ansatz
    /// (abwechselnd waagrecht und senkrecht halbieren) lieferte Kacheln, deren Kanten links
    /// und rechts um ein paar Punkte versetzt lagen; das sah wüst aus.
    ///
    /// Die Länder bleiben in Lesereihenfolge (grösstes zuerst, links oben). Wo die Zeilen
    /// brechen, entscheidet die Form: Es gewinnt die Aufteilung, deren unförmigste Kachel am
    /// nächsten an einem Quadrat liegt; bei Gleichstand die mit weniger Zeilen.
    static func rows(of countries: [CatalogOverview.Country], in area: CGRect) -> [Tile] {
        guard !countries.isEmpty else { return [] }
        let total = Double(countries.reduce(0) { $0 + $1.count })

        func layout(_ breaks: [Int]) -> [Tile] {
            var tiles: [Tile] = []
            var y = area.minY
            var start = 0
            for end in breaks + [countries.count] {
                let row = countries[start..<end]
                let rowSum = Double(row.reduce(0) { $0 + $1.count })
                let height = area.height * CGFloat(rowSum / total)
                var x = area.minX
                for country in row {
                    let width = area.width * CGFloat(Double(country.count) / rowSum)
                    tiles.append(Tile(content: .country(country), rect: CGRect(x: x, y: y, width: width, height: height)))
                    x += width
                }
                y += height
                start = end
            }
            return tiles
        }

        func worstAspect(_ tiles: [Tile]) -> CGFloat {
            tiles.map { max($0.rect.width / $0.rect.height, $0.rect.height / $0.rect.width) }.max() ?? .infinity
        }

        // Alle Möglichkeiten, die Reihe in aufeinanderfolgende Zeilen zu schneiden (bei höchstens
        // sechs Ländern 32): Bit i gesetzt = nach dem i-ten Land beginnt eine neue Zeile.
        let gaps = countries.count - 1
        var best: [Tile] = layout([])
        var bestScore = worstAspect(best)
        var bestRows = 1
        for mask in 1..<(1 << max(gaps, 0)) {
            let breaks = (0..<gaps).filter { mask & (1 << $0) != 0 }.map { $0 + 1 }
            let tiles = layout(breaks)
            let score = worstAspect(tiles)
            let count = breaks.count + 1
            if score < bestScore - 0.001 || (abs(score - bestScore) <= 0.001 && count < bestRows) {
                best = tiles; bestScore = score; bestRows = count
            }
        }
        return best
    }
}
