import CoreGraphics
import Foundation
import Testing
@testable import Wyychaellerli

/// Katalog in Zahlen: Zählung nach Land und Anordnung der Kacheln.
@Suite("Katalog-Übersicht")
struct CatalogOverviewTests {

    private let de = Locale(identifier: "de")

    private func wines(_ counts: [(String, Int)]) -> [CatalogWine] {
        counts.flatMap { country, count in
            (0..<count).map { index in
                CatalogWine(id: "\(country)-\(index)", name: "Wein \(index)", producer: "", vintage: 2020, grape: "",
                            region: "", country: country, typeRaw: "red", alcoholPercent: 0, source: "")
            }
        }
    }

    /// Die Länder aus dem Katalog vom 5.11.2026.
    private var richards: [(String, Int)] {
        [("Chile", 193), ("Italien", 110), ("Argentinien", 97), ("USA", 96), ("Neuseeland", 96),
         ("Frankreich", 8), ("Schweiz", 8), ("Deutschland", 4), ("Portugal", 3), ("Spanien", 3),
         ("Südafrika", 2), ("Nordmazedonien", 1)]
    }

    @Test("Zählt Weine und Länder, grösstes zuerst")
    func counts() {
        let overview = CatalogOverview(entries: wines(richards), locale: de)
        #expect(overview.total == 621)
        #expect(overview.countries.count == 12)
        #expect(overview.countries.first?.name == "Chile")
        #expect(overview.countries.map(\.count) == overview.countries.map(\.count).sorted(by: >))
    }

    @Test("Schweiz, Suisse und Switzerland sind ein Land")
    func mergesSpellings() {
        let overview = CatalogOverview(entries: wines([("Schweiz", 2), ("Suisse", 3), ("Switzerland", 1)]), locale: de)
        #expect(overview.countries.count == 1)
        #expect(overview.countries[0].count == 6)
    }

    @Test("Weine ohne Land zählen zur Gesamtzahl, erscheinen aber in keiner Kachel")
    func missingCountry() {
        let overview = CatalogOverview(entries: wines([("", 5), ("Italien", 3)]), locale: de)
        #expect(overview.total == 8)
        #expect(overview.countries.count == 1)
    }

    @Test("USA heissen USA, nicht „Vereinigte Staaten“")
    func usName() {
        #expect(CountryFlag.displayName(for: "United States", locale: de) == "USA")
        #expect(CountryFlag.displayName(for: "USA", locale: Locale(identifier: "en")) == "USA")
        #expect(CountryFlag.displayName(for: "USA", locale: Locale(identifier: "sr-Latn")) == "SAD")
    }

    @Test("Unter 200 Weinen bleibt die Karte weg")
    func threshold() {
        #expect(!CatalogOverview(entries: wines([("Italien", 199)]), locale: de).isWorthShowing)
        #expect(CatalogOverview(entries: wines([("Italien", 200)]), locale: de).isWorthShowing)
    }

    // MARK: Anordnung

    private let size = CGSize(width: 300, height: 270)

    @Test("Fünf grosse Länder bekommen Kacheln, sieben kleine einen Streifen")
    func tileSplit() {
        let overview = CatalogOverview(entries: wines(richards), locale: de)
        let tiles = CatalogMosaic.tiles(for: overview.countries, in: size)
        #expect(tiles.count == 6)
        let strips = tiles.compactMap { tile -> [CatalogOverview.Country]? in
            if case .others(let rest) = tile.content { return rest }
            return nil
        }
        #expect(strips.count == 1)
        #expect(strips[0].count == 7)
    }

    @Test("Die Kacheln füllen die Fläche ohne Lücke und ohne Überlappung")
    func coversArea() {
        let overview = CatalogOverview(entries: wines(richards), locale: de)
        let tiles = CatalogMosaic.tiles(for: overview.countries, in: size)
        let covered = tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }
        #expect(abs(covered - size.width * size.height) < 0.5)
        for (index, a) in tiles.enumerated() {
            for b in tiles[(index + 1)...] {
                let overlap = a.rect.insetBy(dx: 0.01, dy: 0.01).intersection(b.rect.insetBy(dx: 0.01, dy: 0.01))
                #expect(overlap.isNull || overlap.isEmpty)
            }
        }
    }

    @Test("Kacheln stehen in Zeilen mit durchgehenden Kanten, grösstes Land zuerst")
    func rowsAlignEdges() {
        // Die echten Zahlen vom 7.11.2026: Der frühere Ansatz (abwechselnd halbieren) legte die
        // Kanten links und rechts versetzt – „wüst“.
        let real = [("Chile", 285), ("Italien", 205), ("Südafrika", 194), ("Argentinien", 192),
                    ("Deutschland", 100), ("Schweiz", 99), ("Spanien", 80), ("Portugal", 70), ("USA", 60),
                    ("Neuseeland", 50), ("Österreich", 40), ("Frankreich", 30), ("Nordmazedonien", 4)]
        let overview = CatalogOverview(entries: wines(real), locale: de)
        let tiles = CatalogMosaic.tiles(for: overview.countries, in: CGSize(width: 360, height: 270))
        let countryTiles = tiles.filter { if case .country = $0.content { return true } else { return false } }
        // Jede Zeile beginnt links und hört rechts auf; Kacheln einer Zeile teilen Oberkante und Höhe.
        let rowsByTop = Dictionary(grouping: countryTiles, by: { Int(($0.rect.minY * 10).rounded()) })
        for (_, row) in rowsByTop {
            #expect(Set(row.map { Int(($0.rect.height * 10).rounded()) }).count == 1)
            #expect(abs((row.map(\.rect.minX).min() ?? 1) - 0) < 0.01)
            #expect(abs((row.map(\.rect.maxX).max() ?? 0) - 360) < 0.01)
        }
        // Lesereihenfolge: oben vor unten, links vor rechts; die Weinzahl nimmt dabei nie zu.
        let counts = countryTiles
            .sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
            .compactMap { tile -> Int? in if case .country(let c) = tile.content { return c.count } else { return nil } }
        #expect(counts == counts.sorted(by: >))
        // Keine Kachel ist ein Schlauch.
        for tile in countryTiles {
            #expect(max(tile.rect.width / tile.rect.height, tile.rect.height / tile.rect.width) < 3)
        }
    }

    @Test("Die Fläche folgt der Weinzahl")
    func areaIsProportional() {
        let overview = CatalogOverview(entries: wines(richards), locale: de)
        let tiles = CatalogMosaic.tiles(for: overview.countries, in: size)
        let areas = tiles.compactMap { tile -> (Int, CGFloat)? in
            if case .country(let country) = tile.content { return (country.count, tile.rect.width * tile.rect.height) }
            return nil
        }
        let ratios = areas.map { CGFloat($0.0) / $0.1 }
        let spread = (ratios.max() ?? 0) / (ratios.min() ?? 1)
        #expect(spread < 1.02)
    }

    @Test("Viele Länder ergeben nie mehr als sechs Kacheln und den Streifen")
    func capped() {
        let many = (0..<40).map { ("Land\($0)", 100 - $0) }
        let overview = CatalogOverview(entries: wines(many), locale: de)
        let tiles = CatalogMosaic.tiles(for: overview.countries, in: size)
        #expect(tiles.count <= CatalogMosaic.maxTiles + 1)
    }

    @Test("Ein einziges Land füllt alles, ohne Streifen")
    func single() {
        let overview = CatalogOverview(entries: wines([("Italien", 300)]), locale: de)
        let tiles = CatalogMosaic.tiles(for: overview.countries, in: size)
        #expect(tiles.count == 1)
        #expect(tiles[0].rect == CGRect(origin: .zero, size: size))
    }

    @Test("Leerer Katalog ergibt keine Kacheln")
    func empty() {
        #expect(CatalogMosaic.tiles(for: [], in: size).isEmpty)
    }
}
