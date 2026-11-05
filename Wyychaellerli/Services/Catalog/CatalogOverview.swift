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
        split(big[...], in: area, into: &tiles)
        return tiles
    }

    /// Teilt entlang der längeren Seite dort, wo die Summe der ersten Hälfte am nächsten bei
    /// der halben Gesamtsumme liegt. Jede Kachel bekommt damit genau ihren Anteil.
    private static func split(
        _ items: ArraySlice<CatalogOverview.Country>,
        in rect: CGRect,
        into tiles: inout [Tile]
    ) {
        if items.count == 1, let only = items.first {
            tiles.append(Tile(content: .country(only), rect: rect))
            return
        }
        let total = Double(items.reduce(0) { $0 + $1.count })
        var best = items.startIndex + 1
        var bestGap = Double.infinity
        var running = 0.0
        for index in items.startIndex..<(items.endIndex - 1) {
            running += Double(items[index].count)
            let gap = abs(running - total / 2)
            if gap < bestGap { bestGap = gap; best = index + 1 }
        }
        let first = items[items.startIndex..<best]
        let second = items[best...]
        let share = CGFloat(Double(first.reduce(0) { $0 + $1.count }) / total)
        if rect.width >= rect.height {
            let cut = rect.width * share
            split(first, in: CGRect(x: rect.minX, y: rect.minY, width: cut, height: rect.height), into: &tiles)
            split(second, in: CGRect(x: rect.minX + cut, y: rect.minY, width: rect.width - cut, height: rect.height), into: &tiles)
        } else {
            let cut = rect.height * share
            split(first, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: cut), into: &tiles)
            split(second, in: CGRect(x: rect.minX, y: rect.minY + cut, width: rect.width, height: rect.height - cut), into: &tiles)
        }
    }
}
