import Foundation

/// Die Liste aller Katalogweine auf dem Gerät – nur Text, **nie Bilder**.
///
/// Damit läuft die Suche beim Tippen ohne Netz und ohne Wartezeit. Gesucht wird auf dem
/// Gerät, weil CloudKit nur ganze Wörter und Wortanfänge kennt und jede Abfrage eine halbe
/// bis ganze Sekunde dauert. Ohne UI und ohne CloudKit, damit die Regel testbar ist.
struct CatalogDirectory: Sendable {

    /// Ein Eintrag samt vorberechneten Suchwörtern (klein, ohne Akzente).
    private struct Row: Sendable {
        let entry: CatalogWine
        let words: [String]
        let vintageText: String
        let name: String
    }

    private let rows: [Row]
    private let byKey: [String: CatalogWine]

    var count: Int { rows.count }
    var isEmpty: Bool { rows.isEmpty }
    var entries: [CatalogWine] { rows.map(\.entry) }

    static let empty = CatalogDirectory(entries: [])

    init(entries: [CatalogWine]) {
        byKey = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = entries.map { entry in
            Row(
                entry: entry,
                words: Self.words(of: entry.producer + " " + entry.name),
                vintageText: entry.vintage > 0 ? String(entry.vintage) : "",
                name: Self.fold(entry.name)
            )
        }
    }

    /// Der Eintrag zu Produzent, Name und Jahrgang, über denselben Schlüssel wie der Katalog.
    /// Nur der genaue Treffer – ein abweichend geschriebener Name findet nichts.
    func entry(producer: String, name: String, vintage: Int) -> CatalogWine? {
        byKey[CatalogKey.make(producer: producer, name: name, vintage: vintage)]
    }

    // MARK: Vorschläge

    /// Ein Wein mit seinen Jahrgängen: „Con Brio“ 2018, 2019, 2020 ist **ein** Vorschlag.
    struct Suggestion: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let producer: String
        let origin: String
        /// Die Einträge dieses Weins, neuester Jahrgang zuerst – der zum eingegebenen
        /// Jahrgang passende ganz vorn.
        let entries: [CatalogWine]
    }

    /// Mindestlänge der Eingabe, bevor etwas vorgeschlagen wird.
    static let minimumQueryLength = 2

    /// Die passendsten Weine zu einer Eingabe.
    ///
    /// Jedes Wort muss in Produzent oder Name vorkommen: als Wortanfang („Bri“ trifft „Brio“),
    /// im Wort („rio“) oder mit einem Tippfehler („Con Brioo“, „Cicreo“). Treffer ohne
    /// Tippfehler gehen immer vor: Gibt es welche, erscheinen die unscharfen gar nicht.
    func suggestions(for query: String, vintage: Int = 0, limit: Int = 5) -> [Suggestion] {
        let queryWords = Self.words(of: query)
        guard !queryWords.isEmpty, Self.fold(query).count >= Self.minimumQueryLength else { return [] }

        var scored: [(row: Row, score: Double, exact: Bool)] = []
        for row in rows {
            var total = 0.0
            var exact = true
            var matchesAll = true
            for word in queryWords {
                guard let hit = Self.match(word, in: row) else { matchesAll = false; break }
                total += hit.score
                if hit.fuzzy { exact = false }
            }
            guard matchesAll else { continue }
            // Ganzer Name beginnt mit der Eingabe: das ist, was der Nutzer meint.
            if row.name.hasPrefix(Self.fold(query).trimmingCharacters(in: .whitespaces)) { total += 2 }
            scored.append((row, total, exact))
        }
        // Treffer ohne Tippfehler verdrängen die unscharfen.
        if scored.contains(where: \.exact) { scored.removeAll { !$0.exact } }

        // Einträge desselben Weins zusammenfassen.
        var order: [String] = []
        var groups: [String: (rows: [Row], score: Double)] = [:]
        for item in scored.sorted(by: { $0.score > $1.score }) {
            let key = item.row.name + "|" + Self.fold(item.row.entry.producer)
            if groups[key] == nil {
                order.append(key)
                groups[key] = ([item.row], item.score)
            } else {
                groups[key]?.rows.append(item.row)
            }
        }
        return order.prefix(limit).compactMap { key -> Suggestion? in
            guard let group = groups[key] else { return nil }
            let sorted = group.rows.map(\.entry).sorted {
                if vintage > 0, ($0.vintage == vintage) != ($1.vintage == vintage) { return $0.vintage == vintage }
                return $0.vintage > $1.vintage
            }
            guard let first = sorted.first else { return nil }
            let origin = [first.region, first.country].filter { !$0.isEmpty }.joined(separator: ", ")
            return Suggestion(id: key, name: first.name, producer: first.producer, origin: origin, entries: sorted)
        }
    }

    // MARK: Abgleich eines Wortes

    private static func match(_ word: String, in row: Row) -> (score: Double, fuzzy: Bool)? {
        // Zahlen sind ein Jahrgang oder eine Zahl im Namen („Nr. 7“).
        if word.allSatisfy(\.isNumber) {
            if !row.vintageText.isEmpty, row.vintageText.hasPrefix(word), word.count >= 2 { return (2, false) }
            return row.words.contains(word) ? (3, false) : nil
        }
        var best: (score: Double, fuzzy: Bool)?
        func offer(_ score: Double, fuzzy: Bool) {
            if best == nil || score > best!.score { best = (score, fuzzy) }
        }
        for candidate in row.words {
            if candidate == word { offer(4, fuzzy: false); continue }
            if word.count >= 2, candidate.hasPrefix(word) { offer(3, fuzzy: false); continue }
            if word.count >= 3, candidate.contains(word) { offer(1.5, fuzzy: false); continue }
            // Tippfehler: erst ab vier Buchstaben, sonst trifft fast alles fast alles.
            if word.count >= 4, candidate.count >= 3 {
                let head = String(candidate.prefix(word.count))
                if distance(word, head) <= 1 { offer(1.2, fuzzy: true) }
                else if distance(word, candidate) <= (word.count >= 8 ? 2 : 1) { offer(1.0, fuzzy: true) }
            }
        }
        return best
    }

    // MARK: Hilfen

    /// Klein, ohne Akzente; ß wird „ss“, wie im Schlüssel des Katalogs.
    static func fold(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .replacingOccurrences(of: "ß", with: "ss")
    }

    static func words(of value: String) -> [String] {
        fold(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Editierabstand mit Vertauschung benachbarter Zeichen („Cicreo“ → „Cicero“ = 1).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var rows = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { rows[i][0] = i }
        for j in 0...b.count { rows[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }
        return rows[a.count][b.count]
    }
}

// MARK: - Ablage auf dem Gerät

/// Die Liste liegt in „Application Support“, nicht in den Caches: iOS räumt Caches bei
/// Platzmangel nach Belieben, die Liste soll aber immer vollständig sein. Aus dem Backup
/// ist sie ausgenommen – sie lässt sich jederzeit neu laden. Bilder liegen hier nie.
enum CatalogDirectoryStorage {

    static var fileURL: URL {
        let base = URL.applicationSupportDirectory
        return base.appendingPathComponent("CatalogDirectory.json")
    }

    static func load(from url: URL = fileURL) -> [CatalogWine] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        // Eine unlesbare Datei (älteres Format) gilt als leer und wird neu geladen.
        return (try? JSONDecoder().decode([CatalogWine].self, from: data)) ?? []
    }

    static func save(_ entries: [CatalogWine], to url: URL = fileURL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }
}
