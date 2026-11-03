import CoreData
import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// Der gemeinsame Katalog aus Sicht der Oberfläche: Abgleich, Vorschläge, Status und der
/// Admin-Bereich. Eine Instanz für die ganze App, über die Umgebung verteilt.
///
/// Fällt CloudKit aus – kein Netz, kein Konto, Katalog in dieser Umgebung noch nicht
/// eingerichtet –, arbeitet die App ohne Katalog weiter. Der Abgleich ist eine Zugabe,
/// nie eine Voraussetzung.
@Observable
@MainActor
final class CatalogCenter {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Catalog")
    static let contributeKey = "catalog.contribute"

    private let store: CatalogStore
    private let defaults: UserDefaults

    /// „Neue Weine vorschlagen“. Ausdrücklich einzuschalten – ohne Zustimmung verlässt
    /// nichts aus dem Keller das Gerät.
    var contributesNewWines: Bool {
        didSet { defaults.set(contributesNewWines, forKey: Self.contributeKey) }
    }

    /// Die eigenen Vorschläge, neueste zuerst.
    private(set) var submissions: [CatalogSubmission] = []
    /// Steht diese Apple-ID im Admin-Datensatz?
    private(set) var isAdmin = false
    /// Offene Vorschläge (nur für den Admin geladen).
    private(set) var pendingCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.store = CatalogStore(containerIdentifier: PersistenceController.cloudContainerIdentifier)
        self.contributesNewWines = defaults.bool(forKey: Self.contributeKey)
    }

    // MARK: Status

    /// Lädt eigene Vorschläge und den Admin-Zustand. Fehler bleiben still: Ohne Katalog
    /// zeigt die App eben keinen Katalog-Status.
    func refresh() async {
        isAdmin = await store.isAdmin()
        do {
            submissions = try await store.mySubmissions()
        } catch {
            Self.logger.info("Eigene Vorschläge nicht geladen: \(error.localizedDescription, privacy: .public)")
        }
        if isAdmin {
            _ = try? await pendingSubmissions()
        }
        // Wer schon vorgeschlagen hat, braucht die Abos – auch nach einer Neuinstallation.
        if !submissions.isEmpty || isAdmin {
            await installSubscriptions()
        }
    }

    /// Status des jüngsten Vorschlags zu diesem Wein, falls es einen gibt.
    func submissionStatus(for wine: Wine) -> SubmissionStatus? {
        guard let uuid = wine.uuid?.uuidString else { return nil }
        return submissions.first { $0.wineUUID == uuid }?.status
    }

    // MARK: Abgleich

    /// Der passende Katalogeintrag oder `nil` – auch bei jedem Fehler.
    func lookup(name: String, producer: String, vintage: Int) async -> CatalogWine? {
        let candidate = DuplicateFinder.Candidate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            producer: producer.trimmingCharacters(in: .whitespacesAndNewlines),
            vintage: vintage
        )
        guard !candidate.name.isEmpty else { return nil }
        do {
            return try await store.lookup(candidate)
        } catch {
            Self.logger.info("Katalog-Abgleich fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func lookup(_ wine: Wine) async -> CatalogWine? {
        await lookup(name: wine.name, producer: wine.producer, vintage: Int(wine.vintage))
    }

    /// Ergebnis des Abgleichs über den ganzen Keller.
    struct CellarCheck {
        var missing: [Wine] = []
        var inCatalog = 0
        var alreadySubmitted = 0
    }

    /// Gleicht alle Weine ab. Archivierte zählen mit – getrunken ist nicht unbekannt.
    func checkCellar(_ wines: [Wine], progress: (Int) -> Void) async -> CellarCheck {
        var result = CellarCheck()
        for (index, wine) in wines.enumerated() {
            progress(index + 1)
            if submissionStatus(for: wine) != nil {
                result.alreadySubmitted += 1
            } else if await lookup(wine) != nil {
                result.inCatalog += 1
            } else {
                result.missing.append(wine)
            }
        }
        return result
    }

    // MARK: Vorschlagen

    /// Schickt die Stammdaten und das Vorderseiten-Etikett zur Prüfung.
    func submit(_ wine: Wine) async throws {
        if wine.uuid == nil {
            wine.uuid = UUID()
            wine.managedObjectContext?.saveChanges()
        }
        let draft = SubmissionDraft(
            name: wine.name,
            producer: wine.producer,
            vintage: Int(wine.vintage),
            grape: wine.grape,
            region: wine.region,
            country: wine.country,
            typeRaw: wine.type.rawValue,
            alcoholPercent: wine.alcoholPercent,
            wineUUID: wine.uuid?.uuidString ?? "",
            labelImageData: wine.labelImageData
        )
        try await store.submit(draft)
        await requestNotificationPermission()
        await installSubscriptions()
        submissions = (try? await store.mySubmissions()) ?? submissions
    }

    /// Nach dem Sichern eines neuen Weins: Ist das Vorschlagen eingeschaltet und der Wein
    /// weder im Katalog noch schon vorgeschlagen, geht er still zur Prüfung.
    func submitIfNew(_ wine: Wine) async {
        guard contributesNewWines, submissionStatus(for: wine) == nil else { return }
        guard await lookup(wine) == nil else { return }
        do {
            try await submit(wine)
        } catch {
            Self.logger.info("Automatischer Vorschlag fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Admin

    /// Vorschläge, über die in dieser Sitzung schon entschieden wurde.
    ///
    /// Der Index einer CloudKit-Abfrage läuft dem Speichern ein paar Sekunden hinterher:
    /// Direkt nach dem Ablehnen meldet `status == pending` den Vorschlag noch, und er stand
    /// wieder in der Liste samt Zähler. Deshalb blenden wir Entschiedenes selbst aus.
    private var decidedSubmissionIDs = Set<String>()

    func pendingSubmissions() async throws -> [CatalogSubmission] {
        let pending = try await store.pendingSubmissions()
            .filter { !decidedSubmissionIDs.contains($0.id) }
        pendingCount = pending.count
        return pending
    }

    func existingEntry(for key: String) async -> CatalogWine? {
        try? await store.fetchWine(key)
    }

    /// Nimmt alle Vorschläge einer Gruppe als einen Eintrag auf.
    func accept(_ group: [CatalogSubmission], as entry: CatalogWine) async throws {
        let image = group.lazy.compactMap(\.labelImageData).first
        try await store.accept(group.map(\.id), as: entry, labelImageData: image)
        markDecided(group)
    }

    func reject(_ group: [CatalogSubmission]) async throws {
        try await store.reject(group.map(\.id))
        markDecided(group)
    }

    private func markDecided(_ group: [CatalogSubmission]) {
        let ids = group.map(\.id)
        let newlyDecided = ids.filter { decidedSubmissionIDs.insert($0).inserted }.count
        pendingCount = max(0, pendingCount - newlyDecided)
    }

    // MARK: Katalog verwalten

    func allCatalogWines() async throws -> [CatalogWine] {
        try await store.allWines()
    }

    func catalogImage(_ id: String) async -> Data? {
        try? await store.wineImage(id)
    }

    func saveCatalogWine(_ entry: CatalogWine, previousID: String, image: CatalogStore.ImageChange) async throws -> CatalogWine {
        try await store.save(entry, previousID: previousID, image: image)
    }

    func deleteCatalogWine(_ id: String) async throws {
        try await store.deleteWine(id)
    }

    func myRecordName() async -> String? {
        await store.myRecordName()
    }

    // MARK: Mitteilungen

    /// Fragt einmal nach Mitteilungen – beim ersten Vorschlag, nicht beim App-Start.
    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Einmal je Start genügt; die festen Kennungen ersetzen ein altes Abo ohnehin.
    private var didInstallSubscriptions = false

    private func installSubscriptions() async {
        guard !didInstallSubscriptions else { return }
        do {
            try await store.installSubscriptions(includingAdmin: isAdmin)
            didInstallSubscriptions = true
        } catch {
            Self.logger.info("Abos nicht angelegt: \(error.localizedDescription, privacy: .public)")
        }
    }
}
