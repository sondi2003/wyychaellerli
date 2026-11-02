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

    /// Sucht den passenden Katalogeintrag: zuerst über den exakten Schlüssel, dann über
    /// das aussagekräftigste Suchwort plus die Ähnlichkeitsregel der Doppelerkennung.
    func lookup(_ candidate: DuplicateFinder.Candidate) async throws -> CatalogWine? {
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
                    "alcoholPercent", "catalogKey", "wineUUID", "status"]
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
        let imageFile = try labelImageData.map(Self.temporaryFile)
        if let imageFile, record["image"] == nil { record["image"] = CKAsset(fileURL: imageFile) }
        defer { if let imageFile { try? FileManager.default.removeItem(at: imageFile) } }

        let decided = try await setStatus(.accepted, on: submissionIDs)
        _ = try await database.modifyRecords(saving: [record] + decided, deleting: [], savePolicy: .changedKeys)
        Self.logger.info("Aufgenommen: \(entry.id, privacy: .public), \(submissionIDs.count) Vorschlag/Vorschläge")
    }

    /// Lehnt Vorschläge ab. Sie bleiben liegen, damit der Nutzer den Entscheid sieht.
    func reject(_ submissionIDs: [String]) async throws {
        let decided = try await setStatus(.rejected, on: submissionIDs)
        _ = try await database.modifyRecords(saving: decided, deleting: [], savePolicy: .changedKeys)
    }

    private func setStatus(_ status: SubmissionStatus, on ids: [String]) async throws -> [CKRecord] {
        let fetched = try await database.records(for: ids.map { CKRecord.ID(recordName: $0) }, desiredKeys: ["status"])
        return fetched.values.compactMap { try? $0.get() }.map { record in
            record["status"] = status.rawValue
            return record
        }
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
            adminEdited: (record["adminEdited"] as? Int64 ?? 0) == 1
        )
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
            labelImageData: asset?.fileURL.flatMap { try? Data(contentsOf: $0) }
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
    static func friendlyMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }
        switch ckError.code {
        case .notAuthenticated:
            return tr("Für Vorschläge braucht es ein iCloud-Konto. Melde dich in den Einstellungen von iOS bei iCloud an.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return tr("Der Katalog ist gerade nicht erreichbar. Versuche es später nochmals.")
        case .permissionFailure:
            return tr("Dafür fehlt die Berechtigung.")
        default:
            return ckError.localizedDescription
        }
    }
}
