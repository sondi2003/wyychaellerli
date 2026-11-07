import Foundation

/// Suche und Filter im Admin-Bereich „Katalog verwalten“.
///
/// Gesucht wird auf dem Gerät über den ganzen geladenen Katalog: So trifft „cice“ den
/// „Cicero“, und fehlende Akzente stören nicht. Eine Suche in CloudKit kennt nur ganze
/// Wörter. Ohne UI, damit die Regel testbar ist.
struct CatalogFilter: Equatable {
    var text = ""
    var type: WineType?
    var country: String?
    var source: String?
    /// Jahrgang; 0 = Einträge ohne Jahrgang.
    var vintage: Int?
    /// Nur Einträge, bei denen etwas fehlt (Produzent, Jahrgang, Rebsorte, Region, Land).
    var onlyIncomplete = false

    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || type != nil || country != nil
            || vintage != nil || source != nil || onlyIncomplete
    }

    func apply(to entries: [CatalogWine]) -> [CatalogWine] {
        let words = Self.fold(text)
            .split(separator: " ")
            .map(String.init)
        return entries
            .filter { entry in
                if let type, entry.typeRaw != type.rawValue { return false }
                if let country, entry.country != country { return false }
                if let vintage, entry.vintage != vintage { return false }
                if let source, entry.source != source { return false }
                if onlyIncomplete, !Self.isIncomplete(entry) { return false }
                guard !words.isEmpty else { return true }
                // Jedes Wort muss irgendwo vorkommen – „pinot 2023“ grenzt doppelt ein.
                let haystack = Self.fold([
                    entry.name, entry.producer, entry.grape, entry.region, entry.country,
                    entry.vintage > 0 ? String(entry.vintage) : ""
                ].joined(separator: " ") + " " + entry.gtins.joined(separator: " "))
                return words.allSatisfy(haystack.contains)
            }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.vintage > $1.vintage : order == .orderedAscending
            }
    }

    static func isIncomplete(_ entry: CatalogWine) -> Bool {
        entry.producer.isEmpty || entry.vintage == 0 || entry.grape.isEmpty
            || entry.region.isEmpty || entry.country.isEmpty
    }

    /// Länder, wie sie im Katalog stehen – für das Auswahlmenü.
    static func countries(in entries: [CatalogWine]) -> [String] {
        Array(Set(entries.map(\.country).filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Länder mit der Zahl ihrer Weine, alphabetisch – für das Auswahlmenü.
    static func countryCounts(in entries: [CatalogWine]) -> [(country: String, count: Int)] {
        let counts = Dictionary(grouping: entries.map(\.country).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts
            .map { (country: $0.key, count: $0.value) }
            .sorted { $0.country.localizedCaseInsensitiveCompare($1.country) == .orderedAscending }
    }

    /// Jahrgänge mit der Zahl ihrer Weine, neueste zuerst; 0 (ohne Jahrgang) steht zuletzt.
    static func vintageCounts(in entries: [CatalogWine]) -> [(vintage: Int, count: Int)] {
        let counts = Dictionary(grouping: entries.map(\.vintage), by: { $0 }).mapValues(\.count)
        return counts
            .map { (vintage: $0.key, count: $0.value) }
            .sorted { ($0.vintage > 0 ? $0.vintage : -1) > ($1.vintage > 0 ? $1.vintage : -1) }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
    }
}
