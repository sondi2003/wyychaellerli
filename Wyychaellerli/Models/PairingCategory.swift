import Foundation

/// Grobe Speisegruppen für den Filter „Passt zu“ in der Kellerliste.
///
/// Die Speiseempfehlungen am Wein sind freier Text („Gegrilltes Fleisch, Lamm, Hartkäse“).
/// Zum Filtern werden sie hier einer oder mehreren Gruppen zugeordnet – nach Stichwörtern,
/// nicht nach Bedeutung: „Lamm“ gehört zu Fleisch, „Lasagne“ zu Pasta. Was kein Stichwort
/// trifft, bleibt ohne Gruppe (und im Freitext sichtbar). Ohne UI und mit Tests, damit sich
/// die Zuordnung prüfen lässt.
enum PairingCategory: String, CaseIterable, Identifiable, Sendable {
    case meat, fish, cheese, vegetables, pasta, dessert, aperitif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meat:       return tr("Fleisch")
        case .fish:       return tr("Fisch und Meeresfrüchte")
        case .cheese:     return tr("Käse")
        case .vegetables: return tr("Gemüse und Vegetarisches")
        case .pasta:      return tr("Pasta, Pizza und Reis")
        case .dessert:    return tr("Dessert und Süsses")
        case .aperitif:   return tr("Apéro und Snacks")
        }
    }

    var symbolName: String {
        switch self {
        case .meat:       return "fork.knife"
        case .fish:       return "fish"
        case .cheese:     return "triangle"
        case .vegetables: return "leaf"
        case .pasta:      return "takeoutbag.and.cup.and.straw"
        case .dessert:    return "birthday.cake"
        case .aperitif:   return "wineglass"
        }
    }

    /// Stichwörter, klein und ohne Akzente. Ab vier Buchstaben genügt ein Vorkommen im Wort
    /// („Hartkäse“ trifft „kaese“), kürzere müssen das ganze Wort sein („Ente“, nicht „Entrecôte“).
    private var keywords: [String] {
        switch self {
        case .meat:
            return ["fleisch", "rind", "kalb", "lamm", "schwein", "wild", "gefluegel", "huhn", "poulet", "pute",
                    "truthahn", "braten", "steak", "bbq", "barbecue", "wurst", "salami", "schinken",
                    "speck", "burger", "entrecote", "filet", "gulasch", "ragout", "ente", "reh", "hirsch", "hase",
                    "kaninchen", "charcuterie", "aufschnitt", "bratwurst", "rippli", "ribs", "fondue chinoise"]
        case .fish:
            return ["fisch", "meeresfruechte", "lachs", "thun", "muschel", "krevett", "crevett", "garnele",
                    "auster", "sushi", "krebs", "hummer", "scampi", "forelle", "zander", "dorade", "egli",
                    "calamari", "tintenfisch", "seafood", "sashimi", "kabeljau", "meeresfrucht", "ceviche"]
        case .cheese:
            return ["kaese", "raclette", "fondue", "gorgonzola", "parmesan", "pecorino", "camembert", "brie",
                    "gruyere", "mozzarella", "cheese", "emmentaler", "feta"]
        case .vegetables:
            return ["gemuese", "salat", "pilz", "spargel", "vegetar", "vegan", "tomat", "kuerbis", "auberginen",
                    "zucchini", "ofengemuese", "kartoffel", "risotto mit gemuese", "antipasti", "gratin", "quiche",
                    "suppe", "eintopf", "huelsenfrucht", "linsen", "tofu"]
        case .pasta:
            return ["pasta", "pizza", "nudel", "lasagne", "spaghetti", "risotto", "teigwaren", "gnocchi",
                    "tagliatelle", "penne", "ravioli", "paella", "reis", "couscous", "flammkuchen", "tarte"]
        case .dessert:
            return ["dessert", "schokolade", "kuchen", "torte", "gebaeck", "suess", "nachspeise",
                    "obst", "beeren", "creme", "tiramisu", "eis", "konfituere", "nuss", "praline", "biscuit",
                    "keks", "apfelkuchen"]
        case .aperitif:
            return ["aperitif", "apero", "snack", "tapas", "vorspeise", "oliven", "nuesse", "chips", "knabber",
                    "fingerfood", "canape", "bruschetta", "hors d", "anstossen", "feiern", "sommerabend",
                    "terrasse", "picknick", "brunch"]
        }
    }

    /// Alle Gruppen, in die dieser Text fällt.
    static func categories(in pairings: [String]) -> Set<PairingCategory> {
        var found: Set<PairingCategory> = []
        for pairing in pairings {
            let normalized = fold(pairing)
            let words = normalized.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            for category in allCases where !found.contains(category) {
                let hit = category.keywords.contains { keyword in
                    if keyword.count >= 4 { return normalized.contains(keyword) }
                    return words.contains(keyword)
                }
                if hit { found.insert(category) }
            }
        }
        return found
    }

    /// Wie der Text verglichen wird: klein, ohne Akzente, ä/ö/ü wie ae/oe/ue (und ss für ß).
    private static func fold(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de"))
    }
}
