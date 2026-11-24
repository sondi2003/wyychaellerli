import Foundation

/// Der Katalog in Zahlen: wie viele Weine, aus welchen Ländern.
///
/// Rechnet nur aus der Liste, die ohnehin auf dem Gerät liegt (`CatalogDirectory`) – kein
/// neues Feld, keine Abfrage. Die Länder kommen aus den Daten und nicht aus einer Liste im
/// Code: Kommt ein Land dazu, erscheint es von selbst. Gezeigt wird nur, was der Katalog
/// enthält; **wer die Weine geliefert hat, steht nirgends** (Quelle und Ersteller sind hier
/// bewusst nicht einmal gelesen).
struct CatalogOverview: Equatable, Sendable {

    struct Country: Identifiable, Equatable, Hashable, Sendable {
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

    /// Die Weine eines Landes, alphabetisch. Gleicher Schlüssel wie bei der Gruppierung unten,
    /// „Schweiz“ und „Suisse“ landen also in derselben Liste wie in der Kachel.
    static func wines(inCountry id: String, from entries: [CatalogWine]) -> [CatalogWine] {
        entries
            .filter { !$0.country.isEmpty && (CountryFlag.regionCode(for: $0.country) ?? $0.country) == id }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.vintage > $1.vintage : order == .orderedAscending
            }
    }

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
