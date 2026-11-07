import Foundation
import UIKit

/// Abgleich eines Vorschlags mit Vivino – nur für den Admin, und nie automatisch.
///
/// Die App spricht **nicht** selbst mit Vivino: Die Schnittstelle sperrt Programme, die sich
/// nicht wie ein Browser ausgeben (ehrlicher Absender → 403). Die Abfrage läuft deshalb über
/// den n8n-Strang „Webhook Vivino-Suche“ auf dem eigenen Server (`Docs/n8n-vivino-import.json`),
/// der die Treffer schon im Katalogformat zurückgibt. Adresse und Zugangsschlüssel trägt der
/// Admin in den Einstellungen ein; der Schlüssel liegt in der Keychain, nicht im Programm.
///
/// Das Ergebnis ist ein **Angebot**: Es wird nie von selbst übernommen. Der Admin wählt einen
/// Treffer, sieht die Gegenüberstellung und übernimmt Feld für Feld.

// MARK: - Treffer

/// Ein Wein (ein Jahrgang) bei Vivino, schon in unseren Feldern.
struct VivinoCandidate: Sendable, Equatable, Identifiable, Decodable {
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
    /// Adresse des Flaschenfotos bei Vivino (https) oder leer.
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

    /// Tolerant gelesen: Eine Änderung bei Vivino oder im Ablauf darf nicht zum Absturz
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

struct RankedVivinoCandidate: Equatable, Identifiable {
    let candidate: VivinoCandidate
    let score: Double
    var id: String { candidate.id }
}

// MARK: - Suchwörter und Rangfolge

enum VivinoRanker {

    /// Ab dieser Übereinstimmung gilt ein Treffer als Vorschlag.
    static let minimumScore = 0.5
    /// Wie viele Treffer zur Auswahl stehen.
    static let maximumResults = 5

    /// Die Suchformen, in der Reihenfolge, in der sie versucht werden. Vivino verhält sich je
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
    static func rank(_ candidates: [VivinoCandidate], for entry: CatalogWine) -> [RankedVivinoCandidate] {
        let ours = words(entry.producer + " " + entry.name)
        guard !ours.isEmpty else { return [] }
        var seen = Set<String>()
        return candidates
            .filter { seen.insert($0.vid).inserted }
            .map { RankedVivinoCandidate(candidate: $0, score: score($0, ours: ours, vintage: entry.vintage)) }
            .filter { $0.score >= minimumScore }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.candidate.ratingsCount > $1.candidate.ratingsCount
            }
            .prefix(maximumResults)
            .map { $0 }
    }

    /// Anteil der eigenen Wörter, die der Treffer enthält (zu 60 %), und umgekehrt (zu 40 %);
    /// dazu der Jahrgang (nur bei bereits passendem Namen): gleich +0,25, abweichend −0,1. Ein anderer Jahrgang bleibt ein
    /// möglicher Treffer – der Jahrgang auf dem Etikett kann falsch gelesen sein.
    static func score(_ candidate: VivinoCandidate, ours: [String], vintage: Int) -> Double {
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
enum VivinoField: CaseIterable, Identifiable {
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

    /// Wert bei Vivino, als Text.
    func vivino(_ candidate: VivinoCandidate) -> String {
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

    func apply(_ candidate: VivinoCandidate, to entry: inout CatalogWine) {
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

struct VivinoComparisonRow: Equatable, Identifiable {
    enum State: Equatable {
        /// Beide gleich.
        case same
        /// Beide haben etwas, aber Verschiedenes.
        case different
        /// Nur Vivino kennt den Wert – eine Ergänzung.
        case fillable
        /// Vivino kennt den Wert nicht; der Vorschlag bleibt.
        case vivinoEmpty
    }

    let field: VivinoField
    let current: String
    let vivino: String
    let state: State
    var id: VivinoField { field }
}

enum VivinoComparison {

    static func rows(entry: CatalogWine, candidate: VivinoCandidate) -> [VivinoComparisonRow] {
        VivinoField.allCases.map { field in
            let current = field.current(entry)
            let vivino = field.vivino(candidate)
            let state: VivinoComparisonRow.State
            if vivino.isEmpty {
                state = .vivinoEmpty
            } else if current.isEmpty {
                state = .fillable
            } else if DuplicateFinder.normalized(current) == DuplicateFinder.normalized(vivino) {
                state = .same
            } else {
                state = .different
            }
            return VivinoComparisonRow(field: field, current: current, vivino: vivino, state: state)
        }
    }

    /// Übernimmt alle Felder mit dem angegebenen Zustand.
    static func apply(_ candidate: VivinoCandidate, to entry: CatalogWine, states: Set<VivinoComparisonRow.State>) -> CatalogWine {
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
enum VivinoLookupSettings {

    static let urlKey = "vivino.lookup.url"
    static let tokenAccount = "vivino.lookup.token"

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
}

enum VivinoLookupError: LocalizedError, Equatable {
    case notConfigured
    case server(String)
    case unreadable
    case transport

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            tr("Der Vivino-Abgleich ist nicht eingerichtet. Adresse und Schlüssel stehen in den Einstellungen unter „Vivino-Abgleich“.")
        case .server(let message):
            message
        case .unreadable:
            tr("Die Antwort des Servers war nicht lesbar. Läuft der Ablauf „Webhook Vivino-Suche“ in n8n, und ist er aktiv?")
        case .transport:
            tr("Der Server ist nicht erreichbar.")
        }
    }
}

enum VivinoLookup {

    private struct Response: Decodable {
        var ok: Bool
        var meldung: String?
        var candidates: [VivinoCandidate]?
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
    static func parse(_ data: Data) throws -> [VivinoCandidate] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw VivinoLookupError.unreadable
        }
        guard response.ok else {
            throw VivinoLookupError.server(response.meldung ?? tr("Der Abgleich ist fehlgeschlagen."))
        }
        return response.candidates ?? []
    }

    /// Sucht mit einem Wort. Der Ablauf bremst selbst (30 Abfragen pro Stunde).
    static func search(term: String) async throws -> [VivinoCandidate] {
        guard let url = VivinoLookupSettings.endpoint, !VivinoLookupSettings.token.isEmpty else {
            throw VivinoLookupError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(VivinoLookupSettings.token, forHTTPHeaderField: "X-Admin-Token")
        request.httpBody = try JSONEncoder().encode(["term": term])

        let data: Data
        let status: Int
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            data = body
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw VivinoLookupError.transport
        }
        if status != 200 {
            throw VivinoLookupError.server(describe(status: status, body: data))
        }
        return try parse(data)
    }

    /// Lädt das Flaschenfoto. Nur vom Bilderserver von Vivino über https und höchstens 5 MB;
    /// alles andere liefert `nil`. Die Adresse stammt aus der Antwort des eigenen Servers, wird
    /// aber trotzdem geprüft.
    static func image(for candidate: VivinoCandidate) async -> Data? {
        guard let url = URL(string: candidate.imageURL), url.scheme == "https",
              let host = url.host, host == "images.vivino.com" else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > 1000, data.count < 5_000_000,
              UIImage(data: data) != nil else { return nil }
        return data
    }

    /// Versucht die Suchformen nacheinander und führt alle Treffer zusammen; sobald der beste
    /// gut genug ist, wird nicht weiter gefragt (jede Abfrage kostet einen Platz in der
    /// Stundenbremse des Ablaufs).
    static func find(for entry: CatalogWine) async throws -> [RankedVivinoCandidate] {
        var lastError: Error?
        var all: [VivinoCandidate] = []
        var best: [RankedVivinoCandidate] = []
        for term in VivinoRanker.searchTerms(for: entry) {
            do {
                all += try await search(term: term)
                best = VivinoRanker.rank(all, for: entry)
                if let top = best.first, top.score >= VivinoRanker.goodScore { return best }
            } catch {
                lastError = error
            }
        }
        if best.isEmpty, let lastError { throw lastError }
        return best
    }
}
