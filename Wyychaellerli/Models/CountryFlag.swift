import Foundation

/// Landesflagge als Emoji aus dem Ländernamen, wie er am Wein steht.
///
/// Der Name ist freier Text: Der Scanner schreibt Deutsch („Frankreich“), die KI soll
/// es auch, aber im Formular tippt man vielleicht „France“ oder „Italy“. Deshalb wird
/// nicht gegen eine eigene Liste geprüft, sondern gegen die Ländernamen, die iOS selbst
/// in den gängigen Weinsprachen kennt. Ein paar Kurzformen kommen von Hand dazu.
enum CountryFlag {

    /// Die Flagge zum Land, oder `nil`, wenn der Name keinem Land zuzuordnen ist.
    static func emoji(for country: String) -> String? {
        guard let code = regionCode(for: country) else { return nil }
        return flag(regionCode: code)
    }

    /// ISO-Ländercode zum Namen, etwa „FR“ für „Frankreich“.
    static func regionCode(for country: String) -> String? {
        let key = normalized(country)
        guard !key.isEmpty else { return nil }
        if let code = aliases[key] { return code }
        return table[key]
    }

    /// Zwei Regional-Indicator-Zeichen ergeben die Flagge – so funktionieren alle Flaggen-Emoji.
    private static func flag(regionCode: String) -> String {
        regionCode.uppercased().unicodeScalars.compactMap { scalar -> Character? in
            guard let value = UnicodeScalar(0x1F1E6 + scalar.value - UnicodeScalar("A").value) else { return nil }
            return Character(value)
        }
        .map(String.init)
        .joined()
    }

    // MARK: Nachschlagen

    /// Sprachen, in denen ein Ländername auf einem Etikett oder im Formular stehen kann.
    private static let languages = ["de", "en", "fr", "it", "es", "pt", "sr-Latn"]

    /// Einmal aufgebaut: jeder Ländername in jeder Sprache → Code. Rund 1500 Einträge.
    private static let table: [String: String] = {
        var result: [String: String] = [:]
        let locales = languages.map { Locale(identifier: $0) }
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            for locale in locales {
                guard let name = locale.localizedString(forRegionCode: region.identifier) else { continue }
                result[normalized(name)] = region.identifier
            }
        }
        return result
    }()

    /// Was iOS nicht kennt oder anders nennt.
    private static let aliases: [String: String] = [
        "usa": "US", "u.s.a.": "US", "u.s.a": "US", "vereinigte staaten": "US", "amerika": "US",
        "kalifornien": "US", "california": "US", "napa": "US", "napa valley": "US",
        "uk": "GB", "england": "GB", "grossbritannien": "GB", "great britain": "GB",
        "sudafrika": "ZA", "suedafrika": "ZA",
        "osterreich": "AT", "oesterreich": "AT",
        "hellas": "GR",
        "moldawien": "MD",
        "tschechien": "CZ",
        "elsass": "FR", "bordeaux": "FR", "burgund": "FR", "champagne": "FR",
        "toskana": "IT", "piemont": "IT", "sizilien": "IT",
        "rioja": "ES",
        "wallis": "CH", "waadt": "CH", "tessin": "CH",
    ]

    /// Kleinbuchstaben, ohne Akzente, ohne Beiwerk – damit „Frankreich “ und „frankreich“ gleich sind.
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ß", with: "ss")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }
}
