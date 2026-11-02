import Foundation

/// Wählt aus einem grossen Keller die Flaschen aus, die für ein Gericht überhaupt in Frage
/// kommen – damit sie ins kleine Modell auf dem Gerät passen.
///
/// Das Modell hat rund 4000 Token für Anweisung, Inventar und Antwort. Eine Flasche
/// kostet als JSON etwa 100 bis 150 Token; für ein Dutzend ist Platz, für dreihundert nicht.
/// Die Vorauswahl ist bewusst **grosszügig und einfach**: Sie wirft nur weg, was klar nicht
/// passt, und behält von jeder Weinart die besten. Lieber eine Flasche zu viel als die
/// richtige verloren. Die eigentliche Wahl trifft das Modell.
///
/// Reine Regeln ohne KI und ohne Core Data, damit sie sich testen lassen.
enum InventoryShortlist {

    /// So viele Flaschen gehen höchstens ans kleine Modell.
    static let onDeviceLimit = 12

    static func select(
        from inventory: [WineInventoryItem],
        dish: String,
        limit: Int = onDeviceLimit,
        year: Int = Calendar.current.component(.year, from: .now)
    ) -> [WineInventoryItem] {
        guard inventory.count > limit else { return inventory }

        let ranked = inventory
            .map { (item: $0, score: score($0, dish: dish, year: year)) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return ($0.item.name, $0.item.vintage) < ($1.item.name, $1.item.vintage)
            }

        // Von jeder Weinart mindestens die zwei Besten, dann nach Punkten auffüllen.
        var chosen: [WineInventoryItem] = []
        var perType: [String: Int] = [:]
        for entry in ranked where perType[entry.item.type, default: 0] < 2 && chosen.count < limit {
            chosen.append(entry.item)
            perType[entry.item.type, default: 0] += 1
        }
        for entry in ranked where chosen.count < limit && !chosen.contains(entry.item) {
            chosen.append(entry.item)
        }
        return chosen
    }

    // MARK: Punkte

    static func score(_ item: WineInventoryItem, dish: String, year: Int) -> Int {
        var points = 0
        points += typeAffinity(item.type, dish: dish)

        // Trinkreife: Was dran ist, nach vorn; was noch zu jung oder vorbei ist, nach hinten.
        if let window = drinkYears(item.drinkWindow) {
            if year > window.upperBound { points -= 2 }
            else if year < window.lowerBound { points -= 2 }
            else if year == window.upperBound { points += 2 }
            else { points += 1 }
        }

        // Die Etikett-Empfehlung des Winzers nennt das Gericht.
        let dishWords = words(dish)
        if item.labelPairings.contains(where: { pairing in
            words(pairing).contains { word in dishWords.contains { $0.hasPrefix(word) || word.hasPrefix($0) } }
        }) {
            points += 3
        }

        // Gute Bewertung leicht nach vorn. Schlechte werden nie ausgeschlossen.
        if let stars = Double(item.rating.prefix(3).replacingOccurrences(of: ",", with: ".")), stars >= 4 {
            points += 1
        }
        return points
    }

    /// Grobe, vorsichtige Zuordnung Gericht → Weinart. Wo nichts eindeutig ist: neutral.
    static func typeAffinity(_ type: String, dish: String) -> Int {
        let lowered = dish.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { lowered.contains($0) } }

        let red = has(["rind", "steak", "lamm", "wild", "hirsch", "reh", "braten", "ragout", "bolognese",
                       "entrecôte", "entrecote", "bœuf", "boeuf", "beef", "lamb", "burger", "grill"])
        let light = has(["fisch", "lachs", "forelle", "egli", "meeresfrüchte", "muschel", "crevetten", "garnele",
                         "poisson", "salat", "spargel", "sushi", "austern", "poulet", "huhn", "fish", "shrimp"])
        let cheese = has(["käse", "raclette", "fondue", "kaese", "fromage", "cheese"])
        let sweet = has(["dessert", "torte", "kuchen", "schokolade", "mousse", "tiramisu", "glace", "gâteau", "chocolat"])
        let spicy = has(["curry", "scharf", "chili", "thai", "indisch", "wok"])

        switch type {
        case "Rotwein":
            if red { return 3 }
            if light || sweet || spicy { return -1 }
            return 0
        case "Weisswein":
            if light || cheese || spicy { return 3 }
            if red { return -1 }
            return 0
        case "Schaumwein":
            if sweet || light || spicy || has(["apéro", "apero", "aperitif"]) { return 3 }
            return 0
        case "Rosé":
            if light || spicy || has(["apéro", "apero", "salat", "grill"]) { return 2 }
            return 0
        default:
            return 0
        }
    }

    // MARK: Hilfen

    /// „2022–2028“ → 2022...2028.
    private static func drinkYears(_ text: String) -> ClosedRange<Int>? {
        let parts = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { return nil }
        return parts[0]...parts[1]
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 }
    }
}
