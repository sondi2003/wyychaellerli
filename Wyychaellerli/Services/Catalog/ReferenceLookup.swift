import Foundation
import UIKit

/// Abgleich eines Vorschlags mit einer Referenzquelle – nur für den Admin, und nie automatisch.
///
/// Die App spricht **nicht** selbst mit der Quelle: Deren Schnittstelle sperrt Programme, die sich
/// nicht wie ein Browser ausgeben (ehrlicher Absender → 403). Die Abfrage läuft deshalb über
/// den n8n-Strang „Webhook Quellensuche“ auf dem eigenen Server (`Docs/n8n-katalog-import.json`),
/// der die Treffer schon im Katalogformat zurückgibt, samt Adresse der Suche im Browser. Adresse
/// und Zugangsschlüssel trägt der Admin in den Einstellungen ein; der Schlüssel liegt in der
/// Keychain, nicht im Programm. Der Name der Quelle steht bewusst nirgends in der App.
///
/// Das Ergebnis ist ein **Angebot**: Es wird nie von selbst übernommen. Der Admin wählt einen
/// Treffer, sieht die Gegenüberstellung und übernimmt Feld für Feld.

// MARK: - Treffer

/// Ein Wein (ein Jahrgang) in der Quelle, schon in unseren Feldern.
struct ReferenceCandidate: Sendable, Equatable, Identifiable, Decodable {
    var vid: String
    var name: String
    var producer: String
    /// 0 = ohne Jahrgang („N.V.“).
    var vintage: Int
    var region: String
    var country: String
    var typeRaw: String
    var grape: String
    var foodPairings: [String]
    var rating: Double?
    var ratingsCount: Int
    /// Adresse des Flaschenfotos in der Quelle (https) oder leer.
    var imageURL: String

    var id: String { vid }

    init(vid: String, name: String, producer: String, vintage: Int, region: String = "",
         country: String = "", typeRaw: String = "", grape: String = "",
         foodPairings: [String] = [], rating: Double? = nil, ratingsCount: Int = 0, imageURL: String = "") {
        self.vid = vid
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.region = region
        self.country = country
        self.typeRaw = typeRaw
        self.grape = grape
        self.foodPairings = foodPairings
        self.rating = rating
        self.ratingsCount = ratingsCount
        self.imageURL = imageURL
    }

    /// Tolerant gelesen: Eine Änderung in der Quelle oder im Ablauf darf nicht zum Absturz
    /// führen, fehlende Felder sind einfach leer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { (try? c.decode(String.self, forKey: key)) ?? "" }
        vid = text(.vid)
        name = text(.name)
        producer = text(.producer)
        vintage = (try? c.decode(Int.self, forKey: .vintage)) ?? 0
        region = text(.region)
        country = text(.country)
        typeRaw = text(.typeRaw)
        grape = text(.grape)
        foodPairings = (try? c.decode([String].self, forKey: .foodPairings)) ?? []
        rating = try? c.decode(Double.self, forKey: .rating)
        ratingsCount = (try? c.decode(Int.self, forKey: .ratingsCount)) ?? 0
        imageURL = text(.imageURL)
    }

    private enum CodingKeys: String, CodingKey {
        case vid, name, producer, vintage, region, country, typeRaw, grape, foodPairings, rating, ratingsCount, imageURL
    }

    /// „Donatsch Unique Pinot Noir 2021“
    var title: String {
        let parts = [producer, name].filter { !$0.isEmpty }.joined(separator: " ")
        return vintage > 0 ? "\(parts) \(String(vintage))" : parts
    }
}

struct RankedReferenceCandidate: Equatable, Identifiable {
    let candidate: ReferenceCandidate
    let score: Double
    var id: String { candidate.id }
}

// MARK: - Suchwörter und Rangfolge

enum ReferenceRanker {

    /// Ab dieser Übereinstimmung gilt ein Treffer als Vorschlag.
    static let minimumScore = 0.5
    /// Wie viele Treffer zur Auswahl stehen.
    static let maximumResults = 5

    /// Die Suchformen, in der Reihenfolge, in der sie versucht werden. Die Quelle verhält sich je
    /// nach Wortlaut verschieden: Eine Wortgruppe wird oft als Ganzes gesucht („Villa Antinori“
    /// findet 10 Weine), liefert aber manchmal alles Mögliche („Antinori Villa Antinori“ 204);
    /// ein einzelnes Wort („antinori“) liefert den ganzen Produzenten, nach Bewertung sortiert,
    /// und der gesuchte Wein kann hinter Platz 48 liegen. Deshalb mehrere Formen:
    /// 1. der Name als Wortgruppe (wenn er aus mindestens zwei Wörtern besteht),
    /// 2. Produzent und Name zusammen,
    /// 3. das markanteste Einzelwort, 4. das markanteste Wort des Namens.
    static func searchTerms(for entry: CatalogWine) -> [String] {
        let name = phrase(entry.name)
        let producer = phrase(entry.producer)
        var terms: [String] = []
        func add(_ term: String) {
            let key = term.lowercased()
            if !term.isEmpty, !terms.contains(where: { $0.lowercased() == key }) { terms.append(term) }
        }
        if name.split(separator: " ").count >= 2 { add(name) }
        if !producer.isEmpty, !name.isEmpty { add(producer + " " + name) }
        if let single = CatalogKey.searchToken(name: entry.name, producer: entry.producer) { add(single) }
        if let fromName = CatalogKey.tokens(name: entry.name, producer: "").max(by: { $0.count < $1.count }) { add(fromName) }
        return terms
    }

    /// Text ohne Jahreszahlen, mit einfachen Leerzeichen.
    private static func phrase(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !($0.count == 4 && $0.allSatisfy(\.isNumber)) }
            .joined(separator: " ")
    }

    /// Ab dieser Übereinstimmung ist der beste Treffer gut genug, um nicht weiter zu suchen.
    static let goodScore = 0.8

    /// Bewertet die Treffer gegen den Vorschlag und liefert die besten zuerst.
    /// `minimum` und `limit` lassen sich für die freie Suche lockern: Wer selbst einen Begriff
    /// eingibt, will alles sehen, was die Quelle liefert, nicht nur das, was dem Vorschlag gleicht.
    static func rank(
        _ candidates: [ReferenceCandidate], for entry: CatalogWine,
        minimum: Double = minimumScore, limit: Int = maximumResults
    ) -> [RankedReferenceCandidate] {
        let ours = words(entry.producer + " " + entry.name)
        guard !ours.isEmpty else { return [] }
        var seen = Set<String>()
        return candidates
            .filter { seen.insert($0.vid).inserted }
            .map { RankedReferenceCandidate(candidate: $0, score: score($0, ours: ours, vintage: entry.vintage)) }
            .filter { $0.score >= minimum }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.candidate.ratingsCount > $1.candidate.ratingsCount
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Anteil der eigenen Wörter, die der Treffer enthält (zu 60 %), und umgekehrt (zu 40 %);
    /// dazu der Jahrgang (nur bei bereits passendem Namen): gleich +0,25, abweichend −0,1. Ein anderer Jahrgang bleibt ein
    /// möglicher Treffer – der Jahrgang auf dem Etikett kann falsch gelesen sein.
    static func score(_ candidate: ReferenceCandidate, ours: [String], vintage: Int) -> Double {
        let theirs = words(candidate.producer + " " + candidate.name)
        guard !theirs.isEmpty else { return 0 }
        let shared = Double(ours.filter { word in theirs.contains { same(word, $0) } }.count)
        let sharedBack = Double(theirs.filter { word in ours.contains { same(word, $0) } }.count)
        var value = 0.6 * shared / Double(ours.count) + 0.4 * sharedBack / Double(theirs.count)
        // Der Jahrgang ordnet nur unter Treffern, die schon über den Namen passen – sonst
        // höbe er einen fremden Wein desselben Jahrgangs über die Schwelle.
        if value >= minimumScore, vintage > 0, candidate.vintage > 0 {
            value += candidate.vintage == vintage ? 0.25 : -0.1
        }
        return value
    }

    /// Gleiches Wort, auch mit einem Tippfehler (ab fünf Buchstaben).
    private static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard min(a.count, b.count) >= 5 else { return false }
        return DuplicateFinder.ratio(a, b) >= 0.8
    }

    private static func words(_ text: String) -> [String] {
        let list = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}

// MARK: - Gegenüberstellung

/// Die Felder, die sich vergleichen und übernehmen lassen.
enum ReferenceField: CaseIterable, Identifiable {
    case producer, name, vintage, type, grape, region, country, food

    var id: Self { self }

    var title: String {
        switch self {
        case .producer: tr("Produzent")
        case .name: tr("Name")
        case .vintage: tr("Jahrgang")
        case .type: tr("Weinart")
        case .grape: tr("Rebsorte")
        case .region: tr("Region")
        case .country: tr("Land")
        case .food: tr("Passt zu")
        }
    }

    /// Wert im Vorschlag, als Text.
    func current(_ entry: CatalogWine) -> String {
        switch self {
        case .producer: entry.producer
        case .name: entry.name
        case .vintage: entry.vintage > 0 ? String(entry.vintage) : ""
        case .type: Self.typeName(entry.typeRaw)
        case .grape: entry.grape
        case .region: entry.region
        case .country: entry.country
        case .food: entry.foodPairings.joined(separator: ", ")
        }
    }

    /// Wert in der Quelle, als Text.
    func reference(_ candidate: ReferenceCandidate) -> String {
        switch self {
        case .producer: candidate.producer
        case .name: candidate.name
        case .vintage: candidate.vintage > 0 ? String(candidate.vintage) : ""
        case .type: Self.typeName(candidate.typeRaw)
        case .grape: candidate.grape
        case .region: candidate.region
        case .country: candidate.country
        case .food: candidate.foodPairings.joined(separator: ", ")
        }
    }

    func apply(_ candidate: ReferenceCandidate, to entry: inout CatalogWine) {
        switch self {
        case .producer: entry.producer = candidate.producer
        case .name: entry.name = candidate.name
        case .vintage: entry.vintage = candidate.vintage
        case .type: entry.typeRaw = candidate.typeRaw
        case .grape: entry.grape = candidate.grape
        case .region: entry.region = candidate.region
        case .country: entry.country = candidate.country
        case .food: entry.foodPairings = candidate.foodPairings
        }
    }

    private static func typeName(_ raw: String) -> String {
        WineType(rawValue: raw)?.displayName ?? ""
    }
}

struct ReferenceComparisonRow: Equatable, Identifiable {
    enum State: Equatable {
        /// Beide gleich.
        case same
        /// Beide haben etwas, aber Verschiedenes.
        case different
        /// Nur die Quelle kennt den Wert – eine Ergänzung.
        case fillable
        /// Die Quelle kennt den Wert nicht; der Vorschlag bleibt.
        case referenceEmpty
    }

    let field: ReferenceField
    let current: String
    let reference: String
    let state: State
    var id: ReferenceField { field }
}

enum ReferenceComparison {

    static func rows(entry: CatalogWine, candidate: ReferenceCandidate) -> [ReferenceComparisonRow] {
        ReferenceField.allCases.map { field in
            let current = field.current(entry)
            let reference = field.reference(candidate)
            let state: ReferenceComparisonRow.State
            if reference.isEmpty {
                state = .referenceEmpty
            } else if current.isEmpty {
                state = .fillable
            } else if DuplicateFinder.normalized(current) == DuplicateFinder.normalized(reference) {
                state = .same
            } else {
                state = .different
            }
            return ReferenceComparisonRow(field: field, current: current, reference: reference, state: state)
        }
    }

    /// Übernimmt alle Felder mit dem angegebenen Zustand.
    static func apply(_ candidate: ReferenceCandidate, to entry: CatalogWine, states: Set<ReferenceComparisonRow.State>) -> CatalogWine {
        var result = entry
        for row in rows(entry: entry, candidate: candidate) where states.contains(row.state) {
            row.field.apply(candidate, to: &result)
        }
        return result
    }
}

// MARK: - Einstellungen und Abfrage

/// Adresse des Webhooks und Zugangsschlüssel. Die Adresse ist unkritisch (UserDefaults),
/// der Schlüssel liegt in der Keychain.
enum ReferenceLookupSettings {

    static let urlKey = "reference.lookup.url"
    static let tokenAccount = "reference.lookup.token"

    static var urlString: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: urlKey) }
    }

    static var token: String {
        get { KeychainStore.string(for: tokenAccount) ?? "" }
        set { try? KeychainStore.set(newValue, for: tokenAccount) }
    }

    static var endpoint: URL? {
        guard let url = URL(string: urlString), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    static var isConfigured: Bool { endpoint != nil && !token.isEmpty }

    // MARK: Suche im Browser

    static let browserKey = "reference.browser.url"

    /// Adresse der Suche im Browser, mit „{q}“ als Platz für den Suchbegriff. In einer Adresse
    /// muss der Host stehen; der Name der Quelle bleibt nur aus Texten und Bezeichnern heraus.
    /// Eine in den Einstellungen eingetragene Adresse hat Vorrang.
    static let defaultBrowserSearch = "https://www.vivino.com/search/wines?q={q}"

    static var browserSearchString: String {
        get {
            let stored = UserDefaults.standard.string(forKey: browserKey) ?? ""
            return stored.isEmpty ? defaultBrowserSearch : stored
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: browserKey) }
    }

    /// Die Suche im Browser für einen Begriff.
    static func browserURL(for term: String) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = browserSearchString
        guard !trimmed.isEmpty, !template.isEmpty else { return nil }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        let text = template.contains("{q}")
            ? template.replacingOccurrences(of: "{q}", with: encoded)
            : template + (template.contains("?") ? "&" : "?") + "q=" + encoded
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// Suchbegriff aus Produzent, Name und Jahrgang des Vorschlags, für die Suche im Browser.
    static func browserTerm(for entry: CatalogWine) -> String {
        var words = [entry.producer, entry.name]
        if entry.vintage > 0 { words.append(String(entry.vintage)) }
        return words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum ReferenceLookupError: LocalizedError, Equatable {
    case notConfigured
    case server(String)
    case unreadable
    case transport

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            tr("Der Abgleich mit der Quelle ist nicht eingerichtet. Adresse und Schlüssel stehen in den Einstellungen unter „Quellenabgleich“.")
        case .server(let message):
            message
        case .unreadable:
            tr("Die Antwort des Servers war nicht lesbar. Läuft der Ablauf „Webhook Quellensuche“ in n8n, und ist er aktiv?")
        case .transport:
            tr("Der Server ist nicht erreichbar.")
        }
    }
}

enum ReferenceLookup {

    private struct Response: Decodable {
        var ok: Bool
        var meldung: String?
        var searchURL: String?
        var candidates: [ReferenceCandidate]?
    }

    /// Was eine Abfrage liefert: die Treffer und die Adresse derselben Suche im Browser.
    struct Reply: Equatable {
        var candidates: [ReferenceCandidate]
        var searchURL: URL?
    }

    /// Die besten Treffer, bewertet, samt Adresse der Suche im Browser (vom Server, damit die
    /// App den Namen der Quelle nicht kennen muss).
    struct Result: Equatable {
        var ranked: [RankedReferenceCandidate]
        var searchURL: URL?
    }

    /// Der Fehlertext zu einem HTTP-Code, mit der Meldung von n8n (`{"message": …}`), damit sich
    /// „falscher Schlüssel“, „Schlüssel fehlt“ und „Zugangsdaten am Knoten nicht gewählt“
    /// unterscheiden lassen.
    static func describe(status: Int, body: Data) -> String {
        struct Reply: Decodable { var message: String? }
        let detail = (try? JSONDecoder().decode(Reply.self, from: body))?.message ?? ""
        let suffix = detail.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(detail)"
        switch status {
        case 401, 403:
            return tr("Der Server lehnt den Zugriff ab (\(suffix)). Stimmt der Schlüssel, und heisst der Header in den n8n-Zugangsdaten „X-Admin-Token“?")
        case 404:
            return tr("Die Adresse wurde nicht gefunden (\(suffix)). Ist der Ablauf in n8n aktiv, und ist es die Produktionsadresse?")
        default:
            return tr("Der Server antwortet mit einem Fehler (\(suffix)).")
        }
    }

    /// Antwort des Ablaufs lesen – getrennt von der Abfrage, damit sie ohne Netz testbar ist.
    static func parse(_ data: Data) throws -> Reply {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ReferenceLookupError.unreadable
        }
        guard response.ok else {
            throw ReferenceLookupError.server(response.meldung ?? tr("Der Abgleich ist fehlgeschlagen."))
        }
        let link = response.searchURL.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        return Reply(candidates: response.candidates ?? [], searchURL: link)
    }

    /// Sucht mit einem Wort. Der Ablauf bremst selbst (30 Abfragen pro Stunde).
    static func search(term: String) async throws -> Reply {
        guard let url = ReferenceLookupSettings.endpoint, !ReferenceLookupSettings.token.isEmpty else {
            throw ReferenceLookupError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ReferenceLookupSettings.token, forHTTPHeaderField: "X-Admin-Token")
        request.httpBody = try JSONEncoder().encode(["term": term])

        let data: Data
        let status: Int
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            data = body
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw ReferenceLookupError.transport
        }
        if status != 200 {
            throw ReferenceLookupError.server(describe(status: status, body: data))
        }
        return try parse(data)
    }

    /// Lädt das Flaschenfoto. Nur über https, höchstens 5 MB und nur, wenn es sich als Bild
    /// lesen lässt; alles andere liefert `nil`. Die Adresse stammt aus der Antwort des eigenen,
    /// durch den Schlüssel geschützten Servers.
    static func image(for candidate: ReferenceCandidate) async -> Data? {
        guard let url = URL(string: candidate.imageURL), url.scheme == "https", url.host != nil else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > 1000, data.count < 5_000_000,
              UIImage(data: data) != nil else { return nil }
        return data
    }

    /// Versucht die Suchformen nacheinander und führt alle Treffer zusammen; sobald der beste
    /// gut genug ist, wird nicht weiter gefragt (jede Abfrage kostet einen Platz in der
    /// Stundenbremse des Ablaufs).
    static func find(for entry: CatalogWine) async throws -> Result {
        var lastError: Error?
        var all: [ReferenceCandidate] = []
        var best: [RankedReferenceCandidate] = []
        var link: URL?
        for term in ReferenceRanker.searchTerms(for: entry) {
            do {
                let reply = try await search(term: term)
                all += reply.candidates
                if link == nil { link = reply.searchURL }
                best = ReferenceRanker.rank(all, for: entry)
                if let top = best.first, top.score >= ReferenceRanker.goodScore { break }
            } catch {
                lastError = error
            }
        }
        if best.isEmpty, link == nil, let lastError { throw lastError }
        return Result(ranked: best, searchURL: link)
    }
}
