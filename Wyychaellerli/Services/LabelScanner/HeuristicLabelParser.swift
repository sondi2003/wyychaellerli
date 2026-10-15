import Foundation

/// Einfache, regelbasierte Zuordnung ohne KI – als Fallback, wenn weder Apple Intelligence
/// noch ein Cloud-Anbieter verfügbar sind. Findet Jahrgang, Alkohol, Typ, bekannte Rebsorten
/// und Appellationen zuverlässig; Name und Produzent sind eine Schätzung.
enum HeuristicLabelParser {

    static func parse(recognizedText text: String) -> WineLabelExtraction {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }   // Abschnittstitel ausblenden
        let joined = lines.joined(separator: " ")
        let lowered = joined.lowercased()

        var result = WineLabelExtraction()
        result.vintage = detectVintage(in: lines)
        result.alcoholPercent = detectAlcohol(in: joined)
        result.type = detectType(in: lowered)
        result.grape = detectGrapes(in: lowered)
        result.region = detectRegion(in: lines)
        result.country = detectCountry(in: lowered)
        result.producer = lines.first { line in
            producerKeywords.contains { line.lowercased().contains($0) }
        } ?? ""
        result.name = detectName(in: lines, producer: result.producer, region: result.region)
        return result
    }

    // MARK: Regeln

    private static let producerKeywords = [
        "domaine", "château", "chateau", "weingut", "cantina", "bodega", "tenuta",
        "azienda", "clos ", "mas ", "quinta", "weinkellerei", "winery", "estate"
    ]

    /// Der Jahrgang – oder 0, wenn keiner dasteht. **Es wird nie einer geraten.**
    ///
    /// Eine vierstellige Zahl allein genügt nicht: Auf Schweizer Etiketten steht die
    /// Adresse des Winzers, und Postleitzahlen wie „1950 Sion“ oder „2000 Neuchâtel“
    /// liegen mitten im Jahrgangsbereich. Solche Zeilen werden übersprungen –
    /// erkennbar daran, dass direkt nach der Zahl ein grossgeschriebenes Wort folgt.
    ///
    /// Steht die Zahl hinter „Jahrgang“, „Millésime“ oder „Vintage“, zählt sie in
    /// jedem Fall: Dann ist sie ausdrücklich als Jahrgang bezeichnet.
    private static func detectVintage(in lines: [String]) -> Int {
        let yearPattern = #"\b(19[5-9]\d|20[0-4]\d)\b"#

        // 1. Ausdrücklich bezeichnet – das schlägt alles andere.
        for line in lines {
            let lowered = line.lowercased()
            guard vintageKeywords.contains(where: lowered.contains) else { continue }
            if let year = firstMatch(yearPattern, in: line).flatMap(Int.init) { return year }
        }

        // 2. Sonst die erste Zahl, die nicht nach Postleitzahl aussieht.
        for line in lines {
            guard let year = firstMatch(yearPattern, in: line).flatMap(Int.init) else { continue }
            if looksLikePostalCode(String(year), in: line) { continue }
            return year
        }
        return 0
    }

    private static let vintageKeywords = ["jahrgang", "millésime", "millesime", "vintage", "annata", "cosecha", "vendemmia"]

    /// „2000 Neuchâtel“, „1950 Sion“ – Zahl am Wortanfang, danach ein Ortsname.
    private static func looksLikePostalCode(_ year: String, in line: String) -> Bool {
        guard let range = line.range(of: year) else { return false }
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let firstWord = after.split(separator: " ").first, firstWord.count >= 3 else { return false }
        // Ein Ortsname beginnt gross und besteht aus Buchstaben.
        guard let initial = firstWord.first, initial.isUppercase else { return false }
        return firstWord.allSatisfy { $0.isLetter || $0 == "-" }
    }

    private static func detectAlcohol(in text: String) -> Double {
        // "14.5%", "14,5 %", "ALC. 14.5% BY VOL", "13% vol" – aber nicht "100% manuell".
        for match in allMatches(#"(\d{1,2}(?:[.,]\d)?)\s*%"#, in: text, group: 1) {
            if let value = Double(match.replacingOccurrences(of: ",", with: ".")), (5...25).contains(value) {
                return value
            }
        }
        return 0
    }

    /// Reihenfolge zählt: Ein Glühwein-Etikett nennt fast immer auch „Rotwein“ oder „vin rouge“,
    /// deshalb muss Glühwein vor den Farbbegriffen geprüft werden.
    private static let typeKeywords: [(keywords: [String], type: String)] = [
        (["glühwein", "gluhwein", "gluehwein", "glueh wein", "vin chaud", "mulled wine", "glögg", "glogg", "punsch", "winterwein"], "mulled"),
        (["brut", "champagne", "crémant", "cremant", "prosecco", "spumante", "sekt", "cava", "mousseux", "franciacorta", "extra dry"], "sparkling"),
        (["rosé", "rose ", "rosato", "rosado"], "rose"),
        (["rouge", "red wine", "vin rouge", "rosso", "tinto", "rotwein"], "red"),
        (["blanc", "white wine", "bianco", "blanco", "weiss", "weiß"], "white")
    ]

    private static func detectType(in text: String) -> String {
        for entry in typeKeywords where entry.keywords.contains(where: text.contains) {
            return entry.type
        }
        return "unknown"
    }

    /// Suchstamm (kleingeschrieben, tolerant gegenüber OCR-Fehlern) und Anzeigename.
    private static let grapes: [(stem: String, display: String)] = [
        ("grenache", "Grenache"), ("garnacha", "Garnacha"), ("mourv", "Mourvèdre"), ("monastrell", "Monastrell"),
        ("carignan", "Carignan"), ("syrah", "Syrah"), ("shiraz", "Shiraz"), ("merlot", "Merlot"),
        ("cabernet sauvignon", "Cabernet Sauvignon"), ("cabernet franc", "Cabernet Franc"),
        ("pinot noir", "Pinot Noir"), ("pinot nero", "Pinot Nero"), ("spätburgunder", "Spätburgunder"),
        ("blaufränkisch", "Blaufränkisch"), ("zweigelt", "Zweigelt"), ("nebbiolo", "Nebbiolo"),
        ("sangiovese", "Sangiovese"), ("barbera", "Barbera"), ("dolcetto", "Dolcetto"), ("corvina", "Corvina"),
        ("tempranillo", "Tempranillo"), ("malbec", "Malbec"), ("gamay", "Gamay"), ("cinsault", "Cinsault"),
        ("primitivo", "Primitivo"), ("zinfandel", "Zinfandel"), ("chardonnay", "Chardonnay"),
        ("sauvignon blanc", "Sauvignon Blanc"), ("riesling", "Riesling"), ("chasselas", "Chasselas"),
        ("fendant", "Fendant"), ("pinot gris", "Pinot Gris"), ("pinot grigio", "Pinot Grigio"),
        ("grauburgunder", "Grauburgunder"), ("pinot blanc", "Pinot Blanc"), ("weissburgunder", "Weissburgunder"),
        ("gewürztraminer", "Gewürztraminer"), ("viognier", "Viognier"), ("marsanne", "Marsanne"),
        ("roussanne", "Roussanne"), ("chenin", "Chenin Blanc"), ("vermentino", "Vermentino"),
        ("grüner veltliner", "Grüner Veltliner"), ("silvaner", "Silvaner"), ("müller-thurgau", "Müller-Thurgau"),
        ("albariño", "Albariño"), ("verdejo", "Verdejo"), ("glera", "Glera"), ("trebbiano", "Trebbiano"),
        ("garganega", "Garganega"), ("muscat", "Muscat"), ("petite arvine", "Petite Arvine"),
        ("humagne", "Humagne"), ("cornalin", "Cornalin"), ("gamaret", "Gamaret")
    ]

    private static func detectGrapes(in text: String) -> String {
        var found: [String] = []
        for grape in grapes where text.contains(grape.stem) && !found.contains(grape.display) {
            found.append(grape.display)
        }
        return found.joined(separator: ", ")
    }

    /// Suchbegriffe (kleingeschrieben) je Land. Rückenetiketten tragen fast immer
    /// eine Herkunftsangabe wie „Product of France“ oder „Prodotto in Italia“.
    private static var countries: [(needles: [String], name: String)] { [
        (["france", "frankreich", "français", "francia"], tr("Frankreich")),
        (["italia", "italy", "italien", "italie"], tr("Italien")),
        (["españa", "espana", "spain", "spanien", "espagne"], tr("Spanien")),
        (["deutschland", "germany", "allemagne", "german"], tr("Deutschland")),
        (["schweiz", "suisse", "switzerland", "svizzera"], tr("Schweiz")),
        (["österreich", "osterreich", "austria"], tr("Österreich")),
        (["portugal"], tr("Portugal")),
        (["chile"], tr("Chile")),
        (["argentina", "argentinien"], tr("Argentinien")),
        (["south africa", "südafrika", "sudafrika"], tr("Südafrika")),
        (["australia", "australien"], tr("Australien")),
        (["new zealand", "neuseeland"], tr("Neuseeland")),
        (["u.s.a", "usa", "california", "kalifornien"], tr("USA")),
        (["griechenland", "greece", "hellas"], tr("Griechenland")),
        (["ungarn", "hungary", "magyar"], tr("Ungarn"))
    ] }

    private static func detectCountry(in text: String) -> String {
        for entry in countries where entry.needles.contains(where: text.contains) {
            return entry.name
        }
        return ""
    }

    private static func detectRegion(in lines: [String]) -> String {
        // "Appellation Collioure Contrôlée" / "Appellation d'origine protégée Collioure"
        for line in lines {
            if let match = firstMatch(#"(?i)appellation\s+(.+?)\s+(contr[ôo]l[ée]e|prot[ée]g[ée]e)"#, in: line, group: 1) {
                return match.replacingOccurrences(of: "(?i)d'origine\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        // Zeile mit DOC/DOCG/DO/IGP/AOC/AOP: Region = Rest der Zeile
        for line in lines {
            if let match = firstMatch(#"^(.+?)\s+(DOCG|DOC|DOP|AOC|AOP|IGP|IGT|D\.O\.)\b"#, in: line, group: 1) {
                return match
            }
        }
        return ""
    }

    /// Erste „echte“ Zeile, die weder Produzent, Region, Typ-Angabe noch Kleingedrucktes ist.
    private static func detectName(in lines: [String], producer: String, region: String) -> String {
        let allTypeKeywords = typeKeywords.flatMap(\.keywords) + ["wine", "vin ", "vino", "wein"]
        let candidates = lines.filter { line in
            let lowered = line.lowercased()
            let letters = line.filter(\.isLetter).count
            guard letters >= 3, line.count <= 40 else { return false }
            guard Double(letters) / Double(line.count) >= 0.6 else { return false }   // "•LE", "750 ML."
            guard line != producer else { return false }
            // Region auch bei OCR-Fehlern erkennen ("Collicure" vs. "Collioure").
            guard region.isEmpty || editDistance(lowered, region.lowercased()) > 2 else { return false }
            guard !lowered.contains("appellation"), !line.contains("%"), !lowered.contains("www.") else { return false }
            guard !allTypeKeywords.contains(where: lowered.contains) else { return false }
            guard !lowered.hasPrefix("cépage"), !lowered.hasPrefix("terroir") else { return false }
            return true
        }
        // Mischschreibung ("La Pinède") ist meist der Cuvée-Name; Versalien eher Produzent/Pflichttext.
        return candidates.first { $0 != $0.uppercased() } ?? candidates.first ?? ""
    }

    /// Levenshtein-Distanz für kurze Strings.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }

    private static func allMatches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let groupRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[groupRange])
    }
}
