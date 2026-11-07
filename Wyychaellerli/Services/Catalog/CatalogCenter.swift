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
    /// Alle Katalogweine als Text auf dem Gerät, für die Suche beim Tippen. Keine Bilder.
    private(set) var directory = CatalogDirectory.empty
    private var isLoadingDirectory = false
    /// Zählt jedes Neuladen. Ansichten, die aus der Liste rechnen (Länderübersicht), hängen
    /// ihre Berechnung daran – die Weinzahl allein bemerkt Änderungen ohne Zuwachs nicht.
    private(set) var directoryVersion = 0
    static let directoryRefreshedKey = "catalog.directory.refreshedAt"
    /// So alt darf die Liste werden, bevor sie neu geladen wird, wenn niemand etwas Genaueres
    /// verlangt. Beim Start und beim Öffnen der App gilt kürzer (`refreshDirectory(maxAge:)`).
    static let directoryMaxAge: TimeInterval = 12 * 3600

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

    // MARK: Liste auf dem Gerät

    /// Liest die gespeicherte Liste sofort und lädt sie bei Bedarf neu: wenn sie leer ist
    /// oder älter als zwölf Stunden. Schlägt das Laden fehl (kein Netz, kein Konto), bleibt
    /// die alte Liste stehen – lieber eine ältere als keine.
    func refreshDirectory(force: Bool = false, maxAge: TimeInterval = CatalogCenter.directoryMaxAge) async {
        guard !isLoadingDirectory else { return }
        #if DEBUG
        // Vorführung ohne iCloud: erfundene Weine, damit sich die Suche im Simulator ansehen lässt.
        // Vorführung der Länderübersicht: 621 erfundene Weine aus zwölf Ländern.
        if ProcessInfo.processInfo.environment["CATALOG_DEMO"] == "2" {
            let counts: [(String, Int)] = [
                ("Chile", 193), ("Italien", 110), ("Argentinien", 97), ("USA", 96), ("Neuseeland", 96),
                ("Frankreich", 8), ("Schweiz", 8), ("Deutschland", 4), ("Portugal", 3), ("Spanien", 3),
                ("Südafrika", 2), ("Nordmazedonien", 1)
            ]
            directory = CatalogDirectory(entries: counts.flatMap { country, count in
                (0..<count).map { index in
                    CatalogWine(id: "demo_\(country)_\(index)", name: "Wein \(index)", producer: "", vintage: 2020, grape: "",
                                region: "", country: country, typeRaw: "red", alcoholPercent: 0, source: "")
                }
            })
            return
        }
        if ProcessInfo.processInfo.environment["CATALOG_DEMO"] == "1" {
            func demo(_ name: String, _ producer: String, _ vintage: Int, _ region: String) -> CatalogWine {
                CatalogWine(id: "demo_\(name)_\(vintage)", name: name, producer: producer, vintage: vintage, grape: "Merlot",
                            region: region, country: "Schweiz", typeRaw: "red", alcoholPercent: 13.5, source: "import")
            }
            directory = CatalogDirectory(entries: [
                demo("Con Brio", "Cantina Zeni", 2018, "Tessin"), demo("Con Brio", "Cantina Zeni", 2019, "Tessin"),
                demo("Con Brio", "Cantina Zeni", 2020, "Tessin"), demo("Cicero", "Weingut Studach", 2021, "Graubünden"),
                demo("Trio", "Kellerei Test", 2020, "Wallis")
            ])
            return
        }
        #endif
        isLoadingDirectory = true
        defer { isLoadingDirectory = false }

        if directory.isEmpty {
            let stored = await Task.detached { CatalogDirectoryStorage.load() }.value
            if !stored.isEmpty { directory = await Task.detached { CatalogDirectory(entries: stored) }.value }
        }
        let last = defaults.object(forKey: Self.directoryRefreshedKey) as? Date
        let isStale = last.map { Date().timeIntervalSince($0) > maxAge } ?? true
        guard force || directory.isEmpty || isStale else { return }

        do {
            let entries = try await store.allWines()
            // Ein leeres Ergebnis ist verdächtig (Index fehlt, Fehler): nicht über eine
            // gute Liste schreiben.
            guard !entries.isEmpty else { return }
            directory = await Task.detached { CatalogDirectory(entries: entries) }.value
            directoryVersion += 1
            await Task.detached { CatalogDirectoryStorage.save(entries) }.value
            defaults.set(Date(), forKey: Self.directoryRefreshedKey)
            Self.logger.info("Katalogliste geladen: \(entries.count) Weine")
        } catch {
            Self.logger.info("Katalogliste nicht geladen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Führt die Liste auf dem Gerät nach, wenn der Admin selbst etwas ändert. Sonst fehlt ein
    /// eben aufgenommener Wein bei den Vorschlägen, bis die Liste neu geladen wird (Start,
    /// zehn Minuten Pause, zwölf Stunden) – so fehlte der Jahrgang 2024 neben dem 2022.
    /// Andere Geräte holen ihn beim nächsten Neuladen. Ist die Liste noch nicht geladen, bleibt
    /// alles, wie es ist: Eine Liste mit einem einzigen Wein dürfte die Datei nicht ersetzen.
    ///
    /// - `replace`: der Eintrag ersetzt den bisherigen (Bearbeiten); sonst ergänzt er ihn
    ///   (Aufnehmen: Ein bestehender Eintrag behält seine Angaben und bekommt nur Lücken gefüllt).
    private func applyLocally(adding entry: CatalogWine?, removing id: String? = nil, replace: Bool = false) {
        guard !directory.isEmpty else { return }
        var list = directory.entries
        if let id { list.removeAll { $0.id == id } }
        if let entry {
            if let index = list.firstIndex(where: { $0.id == entry.id }) {
                if replace {
                    list[index] = entry
                } else {
                    var merged = list[index]
                    merged.fillEmptyFields(from: entry)
                    list[index] = merged
                }
            } else {
                list.append(entry)
            }
        }
        directory = CatalogDirectory(entries: list)
        directoryVersion += 1
        let snapshot = list
        Task.detached { CatalogDirectoryStorage.save(snapshot) }
    }

    /// Vorschläge beim Tippen – sofort, ohne Netz.
    func suggestions(for query: String, vintage: Int) -> [CatalogDirectory.Suggestion] {
        directory.suggestions(for: query, vintage: vintage)
    }

    // MARK: Abgleich

    /// Der passende Katalogeintrag oder `nil` – auch bei jedem Fehler.
    func lookup(name: String, producer: String, vintage: Int, barcode: String = "") async -> CatalogWine? {
        let candidate = DuplicateFinder.Candidate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            producer: producer.trimmingCharacters(in: .whitespacesAndNewlines),
            vintage: vintage
        )
        // Mit Strichcode genügt er auch ohne lesbaren Namen.
        guard !candidate.name.isEmpty || !barcode.isEmpty else { return nil }
        do {
            return try await store.lookup(candidate, barcode: barcode)
        } catch {
            Self.logger.info("Katalog-Abgleich fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func lookup(_ wine: Wine) async -> CatalogWine? {
        await lookup(name: wine.name, producer: wine.producer, vintage: Int(wine.vintage), barcode: wine.barcode)
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
            labelImageData: wine.labelImageData,
            barcode: wine.barcode
        )
        try await store.submit(draft)
        await requestNotificationPermission()
        await installSubscriptions()
        submissions = (try? await store.mySubmissions()) ?? submissions
    }

    /// Was der Nutzer zum angezeigten Katalogtreffer gesagt hat.
    enum CatalogChoice: Sendable {
        /// Kein Treffer gezeigt: Beim Sichern wird noch einmal nachgesehen.
        case none
        /// „Das ist mein Wein“: Fehlendes geht als Ergänzung zur Prüfung.
        case confirmed(CatalogWine)
        /// „Anderer Wein“: Es ist ein eigener, neuer Vorschlag.
        case declined(id: String)
        /// Der Treffer wurde gezeigt, aber nicht beantwortet: Es geht nichts an den Katalog –
        /// weder ein Duplikat noch eine Ergänzung an einen Wein, der vielleicht nicht passt.
        case ignored(id: String)
    }

    /// Nach dem Sichern eines neuen Weins: Ist das Vorschlagen eingeschaltet und der Wein
    /// noch nicht vorgeschlagen, geht er still zur Prüfung.
    ///
    /// Steht er schon im Katalog (und der Nutzer hat es bestätigt), geht nur das als
    /// **Ergänzung** zur Prüfung, was dem Eintrag fehlt: leere Felder, ein Strichcode, ein
    /// Foto. Direkt eintragen darf ein Nutzer nichts: Schreiben kann nur der Admin, das ist
    /// so gewollt (sonst könnte jeder den Katalog verfälschen).
    func submitIfNew(_ wine: Wine, choice: CatalogChoice = .none) async {
        guard contributesNewWines, submissionStatus(for: wine) == nil else { return }
        let found: CatalogWine?
        switch choice {
        case .confirmed(let entry):
            found = entry
        case .ignored:
            return
        case .declined(let id):
            let again = await lookup(wine)
            found = again?.id == id ? nil : again
        case .none:
            found = await lookup(wine)
        }
        do {
            if let found {
                try await submitSupplement(to: found, from: wine)
            } else {
                try await submit(wine)
            }
        } catch {
            Self.logger.info("Automatischer Vorschlag fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func submitSupplement(to entry: CatalogWine, from wine: Wine) async throws {
        if wine.uuid == nil {
            wine.uuid = UUID()
            wine.managedObjectContext?.saveChanges()
        }
        let hasImage = wine.labelImageData == nil ? true : await catalogImage(entry.id) != nil
        guard let draft = SubmissionDraft(
            supplementing: entry, producer: wine.producer, grape: wine.grape, region: wine.region,
            country: wine.country, alcoholPercent: wine.alcoholPercent, barcode: wine.barcode,
            labelImageData: wine.labelImageData, entryHasImage: hasImage,
            wineUUID: wine.uuid?.uuidString ?? ""
        ) else { return }
        try await store.submit(draft)
        await requestNotificationPermission()
        await installSubscriptions()
        submissions = (try? await store.mySubmissions()) ?? submissions
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
    /// - `photo`: ein vom Admin gewähltes Foto (aus der Quelle); es ersetzt ein vorhandenes im Katalog.
    func accept(_ group: [CatalogSubmission], as entry: CatalogWine, photo: Data? = nil) async throws {
        let image = photo ?? group.lazy.compactMap(\.labelImageData).first
        try await store.accept(group.map(\.id), as: entry, labelImageData: image, replacingImage: photo != nil)
        markDecided(group)
        applyLocally(adding: entry)
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
        #if DEBUG
        // Vorführung ohne iCloud: `CATALOG_DEMO_IMAGE=/Pfad/zum/Foto.png` liefert für jeden
        // Katalogwein dieses Foto (zum Prüfen des Etikett-Zuschnitts im Simulator).
        if let path = ProcessInfo.processInfo.environment["CATALOG_DEMO_IMAGE"] {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        #endif
        return try? await store.wineImage(id)
    }

    func saveCatalogWine(_ entry: CatalogWine, previousID: String, image: CatalogStore.ImageChange) async throws -> CatalogWine {
        let saved = try await store.save(entry, previousID: previousID, image: image)
        applyLocally(adding: saved, removing: previousID == saved.id ? nil : previousID, replace: true)
        return saved
    }

    func deleteCatalogWine(_ id: String) async throws {
        try await store.deleteWine(id)
        applyLocally(adding: nil, removing: id)
    }

    /// Wirkt die Rolle „Admin“ in dieser Umgebung? Wirft, wenn nicht.
    func checkAdminRights() async throws {
        try await store.checkAdminRights()
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
