import Foundation

/// Der eigene Keller in Zahlen – was im Blatt „Statistik“ unter „Mein Keller“ steht.
///
/// Gezählt werden **Flaschen im Bestand**: Archivierte Weine und solche mit Bestand 0
/// bleiben draussen, sonst zeigte die Übersicht Länder und Jahrgänge, von denen nichts
/// mehr im Regal liegt. Reine Rechnung ohne Ansicht, damit sie sich prüfen lässt.
struct CellarStatistics {

    struct TypeShare: Identifiable {
        let type: WineType
        let bottles: Int
        var id: String { type.rawValue }
    }

    struct CountryShare: Identifiable {
        /// ISO-Code oder, bei unbekanntem Land, der kleingeschriebene Freitext (`Wine.countryKey`).
        let id: String
        let name: String
        let flag: String?
        let bottles: Int
    }

    struct VintageShare: Identifiable {
        let year: Int
        let bottles: Int
        var id: Int { year }
    }

    let bottles: Int
    let wineCount: Int
    /// Mittel der Wein-Mittelwerte; `nil`, solange nichts im Bestand bewertet ist.
    let averageRating: Double?

    /// In der Reihenfolge von `WineType.allCases`, Arten ohne Flasche fehlen.
    let types: [TypeShare]

    /// Letztes Jahr der Spanne oder schon darüber.
    let drinkSoon: Int
    let ready: Int
    let tooYoung: Int
    /// Flaschen ohne Trinkreife-Angabe.
    let withoutWindow: Int

    /// Nach Flaschen absteigend, bei Gleichstand nach Name. Weine ohne Land fehlen.
    let countries: [CountryShare]
    /// Aufsteigend nach Jahr. Weine ohne Jahrgang fehlen – ein Jahrgang wird nie erfunden.
    let vintages: [VintageShare]

    var isEmpty: Bool { bottles == 0 }
    /// Ob überhaupt eine Trinkreife erfasst ist; sonst wäre der Abschnitt eine Zeile „ohne Angabe“.
    var hasMaturity: Bool { drinkSoon + ready + tooYoung > 0 }

    init(wines: [Wine], locale: Locale = AppLanguage.current.locale) {
        let stock = wines.filter { !$0.isArchived && $0.quantity > 0 }
        func count(_ wines: [Wine]) -> Int { wines.reduce(0) { $0 + Int($1.quantity) } }

        bottles = count(stock)
        wineCount = stock.count

        let ratings = stock.compactMap(\.averageRating)
        averageRating = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)

        types = WineType.allCases.compactMap { type in
            let amount = count(stock.filter { $0.type == type })
            return amount > 0 ? TypeShare(type: type, bottles: amount) : nil
        }

        drinkSoon = count(stock.filter(\.needsDrinkingSoon))
        ready = count(stock.filter { $0.maturity == .ready })
        tooYoung = count(stock.filter { $0.maturity == .tooYoung })
        withoutWindow = count(stock.filter { $0.maturity == .unknown })

        countries = Dictionary(grouping: stock.filter { !$0.country.isEmpty }, by: \.countryKey)
            .map { key, group in
                let raw = group.first?.country ?? key
                return CountryShare(
                    id: key,
                    name: CountryFlag.displayName(for: raw, locale: locale) ?? raw,
                    flag: CountryFlag.emoji(for: raw),
                    bottles: count(group)
                )
            }
            .sorted { $0.bottles == $1.bottles ? $0.name < $1.name : $0.bottles > $1.bottles }

        vintages = Dictionary(grouping: stock.filter(\.hasVintage), by: { Int($0.vintage) })
            .map { VintageShare(year: $0.key, bottles: count($0.value)) }
            .sorted { $0.year < $1.year }
    }
}
