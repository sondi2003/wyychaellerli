import CoreData
import Foundation

/// Findet eine Flasche, die schon im Keller liegt.
///
/// Der Zweck ist nicht Aufräumen, sondern Erinnern: Wer eine Flasche nachkauft und das
/// Etikett scannt, soll erfahren, dass er den Wein schon einmal hatte – **auch dann**,
/// wenn der Eintrag längst archiviert oder auf null Flaschen abgebucht ist. Genau dort
/// weiss man es nämlich nicht mehr auswendig.
///
/// Bewusst ohne UI und ohne Core-Data-Abhängigkeit in der Kernlogik, damit sich die
/// Vergleichsregel am Mac gegen echte Fälle prüfen lässt.
enum DuplicateFinder {

    /// Ein Treffer samt Ähnlichkeit, damit die UI den besten zuerst zeigen kann.
    struct Match {
        let wine: Wine
        let similarity: Double
    }

    /// Die verglichenen Felder – als eigener Typ, damit die Regel ohne Core Data testbar ist.
    struct Candidate: Equatable {
        var name: String
        var producer: String
        var vintage: Int
        /// Strichcode (nur Ziffern) oder leer. Derselbe Code bei gleichem Jahrgang heisst
        /// dieselbe Flasche – auch wenn die Texterkennung den Namen anders gelesen hat.
        var barcode: String = ""
    }

    // MARK: Schwellen
    //
    // An echten Fällen gewählt: „La Pinède“ gegen „La Pinede“ muss treffen (Erkennungs-
    // fehler, fehlende Akzente), „Chianti Classico“ gegen „Chianti Classico Riserva“ darf
    // **nicht** treffen – das ist ein anderer Wein.

    /// Ab hier gelten zwei Namen als derselbe Wein.
    private static let nameThreshold = 0.85
    /// Ohne Jahrgang auf einer Seite wird strenger verglichen, weil ein Unterscheidungs-
    /// merkmal fehlt.
    private static let nameThresholdWithoutVintage = 0.93
    /// Zwei gleich benannte Weine verschiedener Produzenten sind nicht dieselbe Flasche.
    private static let producerThreshold = 0.6

    /// Sucht im ganzen Keller, einschliesslich Archiv und leerer Einträge.
    static func findDuplicates(
        of candidate: Candidate,
        in context: NSManagedObjectContext,
        excluding excluded: Wine? = nil
    ) -> [Match] {
        guard !normalized(candidate.name).isEmpty || !candidate.barcode.isEmpty else { return [] }
        let request = Wine.fetchRequest()
        // Absichtlich **kein** Filter auf isArchived oder quantity.
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        guard let wines = try? context.fetch(request) else { return [] }

        return wines
            .filter { $0.objectID != excluded?.objectID }
            .compactMap { wine -> Match? in
                let other = Candidate(name: wine.name, producer: wine.producer, vintage: Int(wine.vintage), barcode: wine.barcode)
                guard let score = similarity(candidate, other) else { return nil }
                return Match(wine: wine, similarity: score)
            }
            .sorted { $0.similarity > $1.similarity }
    }

    /// Ähnlichkeit zweier Kandidaten, oder `nil`, wenn es sicher nicht dieselbe Flasche ist.
    static func similarity(_ a: Candidate, _ b: Candidate) -> Double? {
        // Verschiedene Jahrgänge sind verschiedene Weine – da hilft kein noch so
        // ähnlicher Name.
        let bothVintagesKnown = a.vintage > 0 && b.vintage > 0
        if bothVintagesKnown, a.vintage != b.vintage { return nil }

        // Derselbe Strichcode und kein Widerspruch beim Jahrgang: dieselbe Flasche.
        if !a.barcode.isEmpty, a.barcode == b.barcode { return 1 }

        let nameScore = ratio(normalized(a.name), normalized(b.name))
        let required = bothVintagesKnown ? nameThreshold : nameThresholdWithoutVintage
        guard nameScore >= required else { return nil }

        // Produzent nur prüfen, wenn er auf beiden Seiten bekannt ist. Beim Scannen
        // fehlt er oft, und dann darf er den Treffer nicht verhindern.
        let left = normalized(a.producer)
        let right = normalized(b.producer)
        if !left.isEmpty, !right.isEmpty {
            guard ratio(left, right) >= producerThreshold else { return nil }
        }
        return nameScore
    }

    // MARK: Vergleich

    /// Kleinschreibung, ohne Akzente, ohne Satz- und Leerzeichen.
    /// „La Pinède“ und „la pinede“ werden damit identisch.
    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// 1,0 bei Gleichheit, 0,0 bei völliger Verschiedenheit.
    static func ratio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let distance = levenshtein(Array(a), Array(b))
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }

    /// Editierabstand, zeilenweise gerechnet – es werden nie mehr als zwei Zeilen gehalten.
    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // löschen
                    current[j - 1] + 1,     // einfügen
                    previous[j - 1] + cost  // ersetzen
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
