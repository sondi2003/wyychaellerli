import CloudKit
import Foundation
import OSLog

/// Zugriff auf den gemeinsamen Katalog in der **öffentlichen** CloudKit-Datenbank.
///
/// Der eigene Keller (Core Data, private und geteilte Datenbank) wird hier nicht berührt.
/// Alle Methoden wandeln `CKRecord` sofort in Werttypen um, damit nichts Nicht-Sendables
/// die Grenze zum Main Actor überquert.
///
/// Wer was darf, regeln die Rollen in der CloudKit-Konsole (siehe `Docs/Katalog.md`),
/// nicht dieser Code. Ein Nutzer ohne Admin-Rolle, der `accept` aufruft, scheitert am
/// Server mit `permissionFailure`.
final class CatalogStore: Sendable {

    enum RecordType {
        static let wine = "CatalogWine"
        static let submission = "WineSubmission"
        static let admin = "CatalogAdmin"
    }

    /// Kennungen der Abos. Fest, damit ein erneutes Anlegen das alte ersetzt statt
    /// ein zweites daneben zu stellen.
    enum SubscriptionID {
        static let accepted = "catalog-submission-accepted"
        static let rejected = "catalog-submission-rejected"
        static let newSubmission = "catalog-submission-new"
    }

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Catalog")

    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    // MARK: Abgleich

    /// Sucht den passenden Katalogeintrag: zuerst über den Strichcode (mit dem Jahrgang als
    /// Entscheider), dann über den exakten Schlüssel, zuletzt über das aussagekräftigste
    /// Suchwort plus die Ähnlichkeitsregel der Doppelerkennung.
    func lookup(_ candidate: DuplicateFinder.Candidate, barcode: String = "") async throws -> CatalogWine? {
        // Der Strichcode ist eine Zugabe: Scheitert die Abfrage (das Feld gibt es in dieser
        // Umgebung vielleicht noch nicht), geht es mit dem Namen weiter.
        if !barcode.isEmpty, let hit = try? await lookupBarcode(barcode, vintage: candidate.vintage) {
            return hit
        }
        guard !candidate.name.isEmpty else { return nil }

        let key = CatalogKey.make(producer: candidate.producer, name: candidate.name, vintage: candidate.vintage)
        if let exact = try await fetchWine(key) { return exact }

        guard let token = CatalogKey.searchToken(name: candidate.name, producer: candidate.producer) else {
            return nil
        }
        let query = CKQuery(recordType: RecordType.wine, predicate: NSPredicate(format: "searchTokens CONTAINS %@", token))
        let (results, _) = try await database.records(matching: query, resultsLimit: 50)
        let entries = results.compactMap { try? $0.1.get() }.map(Self.catalogWine)
        return CatalogMatcher.bestMatch(for: candidate, in: entries)
    }

    /// Katalogeinträge, die diesen Strichcode tragen – in der Regel einer je Jahrgang.
    private func lookupBarcode(_ barcode: String, vintage: Int) async throws -> CatalogWine? {
        let query = CKQuery(recordType: RecordType.wine, predicate: NSPredicate(format: "gtins CONTAINS %@", barcode))
        let (results, _) = try await database.records(matching: query, resultsLimit: 30)
        let entries = results.compactMap { try? $0.1.get() }.map(Self.catalogWine)
        return CatalogMatcher.match(barcode: barcode, vintage: vintage, in: entries)
    }

    /// Ein Eintrag über seinen Schlüssel, oder `nil`, wenn es ihn nicht gibt.
    func fetchWine(_ key: String) async throws -> CatalogWine? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: key))
            return Self.catalogWine(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: Vorschläge

    /// Legt einen Vorschlag an. Braucht ein iCloud-Konto.
    func submit(_ draft: SubmissionDraft) async throws {
        let record = CKRecord(recordType: RecordType.submission)
        record["name"] = draft.name
        record["producer"] = draft.producer
        record["vintage"] = Int64(draft.vintage)
        record["grape"] = draft.grape
        record["region"] = draft.region
        record["country"] = draft.country
        record["typeRaw"] = draft.typeRaw
        record["alcoholPercent"] = draft.alcoholPercent
        record["catalogKey"] = draft.catalogKey
        record["wineUUID"] = draft.wineUUID
        // Nur setzen, wenn es etwas gibt: Ein Feld, das es in Production noch nicht gibt,
        // liesse sonst jeden Vorschlag scheitern – auch die ohne Strichcode.
        if !draft.barcode.isEmpty { record["barcode"] = draft.barcode }
        record["status"] = SubmissionStatus.pending.rawValue
        record["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let imageFile = try draft.labelImageData.map(Self.temporaryFile)
        if let imageFile { record["labelImage"] = CKAsset(fileURL: imageFile) }
        defer { if let imageFile { try? FileManager.default.removeItem(at: imageFile) } }

        _ = try await database.save(record)
        Self.logger.info("Vorschlag gesendet: \(draft.catalogKey, privacy: .public)")
    }

    /// Die eigenen Vorschläge, neueste zuerst. Ohne Etikettbild – die Liste braucht es nicht.
    func mySubmissions() async throws -> [CatalogSubmission] {
        let me = try await container.userRecordID()
        let predicate = NSPredicate(format: "creatorUserRecordID == %@", CKRecord.Reference(recordID: me, action: .none))
        return try await submissions(matching: predicate, withImages: false)
    }

    /// Alle offenen Vorschläge (nur mit Admin-Rolle lesbar).
    func pendingSubmissions() async throws -> [CatalogSubmission] {
        try await submissions(
            matching: NSPredicate(format: "status == %@", SubmissionStatus.pending.rawValue),
            withImages: true
        )
    }

    private func submissions(matching predicate: NSPredicate, withImages: Bool) async throws -> [CatalogSubmission] {
        let query = CKQuery(recordType: RecordType.submission, predicate: predicate)
        var keys = ["name", "producer", "vintage", "grape", "region", "country", "typeRaw",
                    "alcoholPercent", "catalogKey", "wineUUID", "status", "barcode"]
        if withImages { keys.append("labelImage") }
        var collected: [CatalogSubmission] = []
        var (results, cursor) = try await database.records(matching: query, desiredKeys: keys, resultsLimit: 200)
        collected += results.compactMap { try? $0.1.get() }.map(Self.submission)
        // Mehr als 200 offene Vorschläge sind selten, aber sie sollen nicht verschwinden.
        while let next = cursor {
            (results, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: keys, resultsLimit: 200)
            collected += results.compactMap { try? $0.1.get() }.map(Self.submission)
        }
        return collected.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: Katalog verwalten (Admin)

    /// Der ganze Katalog, ohne Etiketten – die würden bei ein paar hundert Weinen
    /// zig Megabyte laden. Das Bild holt `wineImage(_:)` erst beim Öffnen eines Eintrags.
    func allWines() async throws -> [CatalogWine] {
        let query = CKQuery(recordType: RecordType.wine, predicate: NSPredicate(value: true))
        let keys = ["name", "producer", "vintage", "grape", "region", "country", "typeRaw",
                    "alcoholPercent", "source", "sourceID", "adminEdited", "gtins", "foodPairings"]
        var collected: [CatalogWine] = []
        var (results, cursor) = try await database.records(matching: query, desiredKeys: keys, resultsLimit: 400)
        collected += results.compactMap { try? $0.1.get() }.map(Self.catalogWine)
        while let next = cursor {
            (results, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: keys, resultsLimit: 400)
            collected += results.compactMap { try? $0.1.get() }.map(Self.catalogWine)
        }
        return collected
    }

    /// Das Etikett eines Eintrags, oder `nil`, wenn keines hinterlegt ist.
    func wineImage(_ id: String) async throws -> Data? {
        let fetched = try await database.records(for: [CKRecord.ID(recordName: id)], desiredKeys: ["image"])
        let record = try fetched.values.first?.get()
        guard let url = (record?["image"] as? CKAsset)?.fileURL else { return nil }
        let data = try? Data(contentsOf: url)
        // Die heruntergeladene Datei braucht niemand mehr: Das Bild steht im Speicher und
        // landet nur dann dauerhaft am Wein, wenn der Nutzer es verwendet.
        try? FileManager.default.removeItem(at: url)
        return data
    }

    /// Was mit dem Etikett beim Sichern passiert.
    enum ImageChange: Sendable {
        case keep
        case replace(Data)
        case remove
    }

    enum EditError: LocalizedError {
        /// Unter dem neuen Schlüssel steht schon ein anderer Eintrag.
        case keyTaken(String)

        var errorDescription: String? {
            switch self {
            case .keyTaken(let name):
                return tr("Mit diesen Angaben steht schon „\(name)“ im Katalog. Ändere Name, Produzent oder Jahrgang, oder lösche einen der beiden Einträge.")
            }
        }
    }

    /// Sichert einen bearbeiteten Eintrag.
    ///
    /// Haben sich Name, Produzent oder Jahrgang geändert, ändert sich der Schlüssel: Der
    /// Eintrag zieht dann unter den neuen Schlüssel um, damit ein späterer Scan ihn auf
    /// dem schnellsten Weg findet, und der alte wird gelöscht. Steht unter dem neuen
    /// Schlüssel schon ein anderer Eintrag, wird nichts überschrieben.
    @discardableResult
    func save(_ entry: CatalogWine, previousID: String, image: ImageChange) async throws -> CatalogWine {
        var entry = entry
        entry.id = CatalogKey.make(producer: entry.producer, name: entry.name, vintage: entry.vintage)
        let moves = entry.id != previousID

        let record: CKRecord
        var imageData: Data?
        if moves {
            if let taken = try await fetchWine(entry.id) {
                throw EditError.keyTaken(taken.name)
            }
            record = CKRecord(recordType: RecordType.wine, recordID: CKRecord.ID(recordName: entry.id))
            // Beim Umzug muss das bestehende Etikett mit – es hängt am alten Datensatz.
            if case .keep = image { imageData = try await wineImage(previousID) }
        } else {
            record = try await database.record(for: CKRecord.ID(recordName: entry.id))
        }

        record["name"] = entry.name
        record["producer"] = entry.producer
        record["vintage"] = Int64(entry.vintage)
        record["grape"] = entry.grape
        record["region"] = entry.region
        record["country"] = entry.country
        record["typeRaw"] = entry.typeRaw
        record["alcoholPercent"] = entry.alcoholPercent
        record["searchTokens"] = CatalogKey.tokens(name: entry.name, producer: entry.producer)
        record["source"] = entry.source.isEmpty ? "admin" : entry.source
        record["sourceID"] = entry.sourceID
        record["adminEdited"] = Int64(1)
        // Hier gilt genau die Liste des Admins – er darf einen falschen Code auch entfernen.
        record["gtins"] = entry.gtins.isEmpty ? nil : entry.gtins
        record["foodPairings"] = entry.foodPairings.isEmpty ? nil : entry.foodPairings

        switch image {
        case .keep: break
        case .replace(let data): imageData = data
        case .remove: record["image"] = nil
        }
        let imageFile = try imageData.map(Self.temporaryFile)
        if let imageFile { record["image"] = CKAsset(fileURL: imageFile) }
        defer { if let imageFile { try? FileManager.default.removeItem(at: imageFile) } }

        let deleting = moves ? [CKRecord.ID(recordName: previousID)] : []
        try await modify(saving: [record], deleting: deleting, savePolicy: .changedKeys)
        Self.logger.info("Katalog bearbeitet: \(previousID, privacy: .public) → \(entry.id, privacy: .public)")
        entry.adminEdited = true
        return entry
    }

    func deleteWine(_ id: String) async throws {
        try await modify(saving: [], deleting: [CKRecord.ID(recordName: id)])
        Self.logger.info("Aus dem Katalog gelöscht: \(id, privacy: .public)")
    }

    // MARK: Admin

    /// Steht die eigene Kennung im Admin-Datensatz? Nur für die Anzeige – geschützt wird
    /// über die Rolle in der Konsole.
    func isAdmin() async -> Bool {
        do {
            let me = try await container.userRecordID()
            let record = try await database.record(for: CKRecord.ID(recordName: "admins"))
            let names = record["userRecordNames"] as? [String] ?? []
            return names.contains(me.recordName)
        } catch {
            return false
        }
    }

    /// Die eigene Kennung – Richard trägt sie in der Konsole in `CatalogAdmin` ein.
    func myRecordName() async -> String? {
        try? await container.userRecordID().recordName
    }

    /// Nimmt einen Vorschlag auf: schreibt den (allenfalls korrigierten) Eintrag in den
    /// Katalog und setzt **alle** offenen Vorschläge mit demselben Schlüssel auf
    /// „aufgenommen“, damit jeder Einreicher seine Mitteilung bekommt.
    func accept(_ submissionIDs: [String], as entry: CatalogWine, labelImageData: Data?) async throws {
        let id = CKRecord.ID(recordName: entry.id)
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: RecordType.wine, recordID: id)
        }
        record["name"] = entry.name
        record["producer"] = entry.producer
        record["vintage"] = Int64(entry.vintage)
        record["grape"] = entry.grape
        record["region"] = entry.region
        record["country"] = entry.country
        record["typeRaw"] = entry.typeRaw
        record["alcoholPercent"] = entry.alcoholPercent
        record["searchTokens"] = CatalogKey.tokens(name: entry.name, producer: entry.producer)
        record["source"] = entry.source
        record["sourceID"] = entry.sourceID
        record["adminEdited"] = Int64(1)
        // Beim Aufnehmen kommen Strichcodes **dazu**, bestehende bleiben.
        let merged = Self.unique((record["gtins"] as? [String] ?? []) + entry.gtins)
        if !merged.isEmpty { record["gtins"] = merged }
        // Speisen nur ergaenzen, wenn der Eintrag noch keine hat.
        if (record["foodPairings"] as? [String] ?? []).isEmpty, !entry.foodPairings.isEmpty {
            record["foodPairings"] = entry.foodPairings
        }
        let imageFile = try labelImageData.map(Self.temporaryFile)
        if let imageFile, record["image"] == nil { record["image"] = CKAsset(fileURL: imageFile) }
        defer { if let imageFile { try? FileManager.default.removeItem(at: imageFile) } }

        let decided = try await setStatus(.accepted, on: submissionIDs)
        try await modify(saving: [record] + decided, deleting: [], savePolicy: .changedKeys)
        Self.logger.info("Aufgenommen: \(entry.id, privacy: .public), \(submissionIDs.count) Vorschlag/Vorschläge")
    }

    /// Lehnt Vorschläge ab. Sie bleiben liegen, damit der Nutzer den Entscheid sieht.
    func reject(_ submissionIDs: [String]) async throws {
        let decided = try await setStatus(.rejected, on: submissionIDs)
        try await modify(saving: decided, deleting: [], savePolicy: .changedKeys)
    }

    private func setStatus(_ status: SubmissionStatus, on ids: [String]) async throws -> [CKRecord] {
        let fetched = try await database.records(for: ids.map { CKRecord.ID(recordName: $0) }, desiredKeys: ["status"])
        // Ein Vorschlag, den man nicht holen kann, darf nicht still wegfallen: Sonst wäre
        // der Eintrag im Katalog, der Vorschlag aber noch offen (oder umgekehrt).
        return try fetched.values.map { result in
            let record = try result.get()
            record["status"] = status.rawValue
            return record
        }
    }

    /// Schreibt Datensätze und **wirft den ersten Fehler**.
    ///
    /// `modifyRecords` wirft nur, wenn der ganze Auftrag scheitert. Fehlende Rechte, ein
    /// Feld, das es in Production noch nicht gibt, ein veralteter Datensatz – all das steht
    /// je Datensatz im Ergebnis. Wer es nicht liest, sieht „Erfolg“, obwohl nichts
    /// gespeichert wurde: Der Vorschlag verschwand aus der Liste, kam aber nie in den
    /// Katalog, und später stand er wieder da (Richard, 3.11.2026, TestFlight).
    ///
    /// Der Auftrag läuft atomar: Scheitert einer, melden **alle** `batchRequestFailed`.
    /// Gemeldet wird deshalb der eigentliche Grund, nicht dieser Folgefehler.
    private func modify(
        saving: [CKRecord],
        deleting: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged
    ) async throws {
        let result = try await database.modifyRecords(saving: saving, deleting: deleting, savePolicy: savePolicy)
        var failures: [Error] = []
        for (_, saved) in result.saveResults {
            if case .failure(let error) = saved { failures.append(error) }
        }
        for (_, deleted) in result.deleteResults {
            if case .failure(let error) = deleted { failures.append(error) }
        }
        guard !failures.isEmpty else { return }
        let reason = failures.first { ($0 as? CKError)?.code != .batchRequestFailed } ?? failures[0]
        Self.logger.error("Speichern abgelehnt: \(reason.localizedDescription, privacy: .public)")
        throw reason
    }

    /// Darf diese Apple-ID in den Katalog schreiben, wirkt die Rolle „Admin“ also in dieser
    /// Umgebung? Schreibt einen leeren Prüfdatensatz und löscht ihn sofort wieder.
    ///
    /// Das ist die einzige verlässliche Probe: Dass der Admin-Bereich **sichtbar** ist, sagt
    /// nichts – er hängt am Datensatz `admins`, den jeder lesen darf. Die Rechte hängen an
    /// der Rolle in der Konsole.
    func checkAdminRights() async throws {
        let id = CKRecord.ID(recordName: "rechtepruefung")
        try await modify(saving: [CKRecord(recordType: RecordType.wine, recordID: id)], deleting: [])
        try await modify(saving: [], deleting: [id])
    }

    // MARK: Mitteilungen

    /// Abos für den Entscheid über die eigenen Vorschläge – und für Richard eines auf neue
    /// Vorschläge. Gesendet wird von Apple, ein eigener Server ist nicht nötig.
    func installSubscriptions(includingAdmin: Bool) async throws {
        let me = try await container.userRecordID()
        let mine = CKRecord.Reference(recordID: me, action: .none)
        var subscriptions = [
            Self.decisionSubscription(.accepted, creator: mine, id: SubscriptionID.accepted,
                                      text: "Dein Vorschlag „%@“ wurde in den Katalog aufgenommen."),
            Self.decisionSubscription(.rejected, creator: mine, id: SubscriptionID.rejected,
                                      text: "Dein Vorschlag „%@“ wurde nicht aufgenommen.")
        ]
        if includingAdmin {
            let subscription = CKQuerySubscription(
                recordType: RecordType.submission,
                predicate: NSPredicate(format: "status == %@", SubmissionStatus.pending.rawValue),
                subscriptionID: SubscriptionID.newSubmission,
                options: [.firesOnRecordCreation]
            )
            subscription.notificationInfo = Self.notification(text: "Neuer Vorschlag: „%@“")
            subscriptions.append(subscription)
        }
        _ = try await database.modifySubscriptions(saving: subscriptions, deleting: [])
    }

    private static func decisionSubscription(
        _ status: SubmissionStatus,
        creator: CKRecord.Reference,
        id: String,
        text: String
    ) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: RecordType.submission,
            predicate: NSPredicate(format: "creatorUserRecordID == %@ AND status == %@", creator, status.rawValue),
            subscriptionID: id,
            options: [.firesOnRecordUpdate]
        )
        subscription.notificationInfo = notification(text: text)
        return subscription
    }

    /// Der Text ist ein Schlüssel im Sprachkatalog. iOS setzt ihn beim Empfang selbst in
    /// die Gerätesprache um und füllt `%@` mit dem Weinnamen aus dem Datensatz.
    private static func notification(text: String) -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "Wyychällerli-Katalog"
        info.alertLocalizationKey = text
        info.alertLocalizationArgs = ["name"]
        info.soundName = "default"
        return info
    }

    // MARK: Umwandlung

    private static func catalogWine(_ record: CKRecord) -> CatalogWine {
        CatalogWine(
            id: record.recordID.recordName,
            name: record["name"] as? String ?? "",
            producer: record["producer"] as? String ?? "",
            vintage: Int(record["vintage"] as? Int64 ?? 0),
            grape: record["grape"] as? String ?? "",
            region: record["region"] as? String ?? "",
            country: record["country"] as? String ?? "",
            typeRaw: record["typeRaw"] as? String ?? "",
            alcoholPercent: record["alcoholPercent"] as? Double ?? 0,
            source: record["source"] as? String ?? "",
            sourceID: record["sourceID"] as? String ?? "",
            adminEdited: (record["adminEdited"] as? Int64 ?? 0) == 1,
            gtins: record["gtins"] as? [String] ?? [],
            foodPairings: record["foodPairings"] as? [String] ?? []
        )
    }

    /// Doppelte entfernen, Reihenfolge behalten.
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func submission(_ record: CKRecord) -> CatalogSubmission {
        let asset = record["labelImage"] as? CKAsset
        return CatalogSubmission(
            id: record.recordID.recordName,
            name: record["name"] as? String ?? "",
            producer: record["producer"] as? String ?? "",
            vintage: Int(record["vintage"] as? Int64 ?? 0),
            grape: record["grape"] as? String ?? "",
            region: record["region"] as? String ?? "",
            country: record["country"] as? String ?? "",
            typeRaw: record["typeRaw"] as? String ?? "",
            alcoholPercent: record["alcoholPercent"] as? Double ?? 0,
            catalogKey: record["catalogKey"] as? String ?? "",
            wineUUID: record["wineUUID"] as? String ?? "",
            status: SubmissionStatus(rawValue: record["status"] as? String ?? "") ?? .pending,
            createdAt: record.creationDate,
            labelImageData: asset?.fileURL.flatMap { try? Data(contentsOf: $0) },
            barcode: record["barcode"] as? String ?? ""
        )
    }

    /// CloudKit nimmt Bilder nur als Datei entgegen.
    private static func temporaryFile(for data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url)
        return url
    }
}

// MARK: - Fehler in Klartext

extension CatalogStore {

    /// Übersetzt CloudKit-Fehler in einen Satz, mit dem ein Mensch etwas anfangen kann.
    static func friendlyMessage(for error: Error, asAdmin: Bool = false) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }
        switch ckError.code {
        case .notAuthenticated:
            return tr("Für Vorschläge braucht es ein iCloud-Konto. Melde dich in den Einstellungen von iOS bei iCloud an.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return tr("Der Katalog ist gerade nicht erreichbar. Versuche es später nochmals.")
        case .permissionFailure:
            return asAdmin
                ? tr("Dafür fehlt die Berechtigung. Die Rolle „Admin“ ist dieser Apple-ID in dieser Umgebung nicht zugewiesen – in der CloudKit-Konsole beim eigenen Benutzer eintragen.")
                : tr("Dafür fehlt die Berechtigung.")
        default:
            return ckError.localizedDescription
        }
    }
}
