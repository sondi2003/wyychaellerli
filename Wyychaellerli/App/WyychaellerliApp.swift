import SwiftUI

@main
struct WyychaellerliApp: App {

    /// Nötig, damit Freigabe-Einladungen ankommen (siehe SceneDelegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Core Data mit CloudKit. Wird von App und Siri-Intent gemeinsam genutzt.
    private let persistence = PersistenceController.shared

    /// Einstellungen (Provider, Modelle, Keys) – einmal pro App-Lebenszyklus.
    @State private var settings = AISettings()

    /// Welche lokalen KI-Modelle (auf dem Gerät, Private Cloud) gerade nutzbar sind.
    @State private var localAI = LocalAIStatus()

    /// Wer an diesem Gerät bewertet (Kennung aus iCloud, Name aus den Einstellungen).
    @State private var rater = CurrentRater()

    /// Ob gerade eine Party läuft. Muss über der ganzen App liegen, damit der gesperrte
    /// Modus auch einen Neustart übersteht.
    @State private var party = PartySession()

    /// Der gemeinsame Katalog in der öffentlichen CloudKit-Datenbank.
    @State private var catalog = CatalogCenter()

    /// Der KI-Service ist zustandslos und kann geteilt werden.
    private let aiService = AIService()

    /// Hell, dunkel oder dem System folgen. Gilt für die ganze App.
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system

    /// Sprache der Oberfläche. `Text("…")` löst über die Locale der Umgebung auf.
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    init() {
        QuickTips.configure()
        Brand.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(rater)
                .environment(localAI)
                .environment(party)
                .environment(catalog)
                .environment(\.aiService, aiService)
                .environment(\.managedObjectContext, persistence.viewContext)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Brand.accent)
                .environment(\.locale, language.locale)
                .task(id: language) {
                    await localAI.refresh()
                }
                .task {
                    // Einmalige Übernahme aus der früheren SwiftData-Ablage.
                    LegacyImporter.importIfNeeded(into: persistence.viewContext)
                    // Alkoholgehalt aus den Notizen ins eigene Feld holen.
                    AlcoholNoteMigration.run(in: persistence.viewContext)
                    #if DEBUG
                    // Vorführung: ein paar erfundene Weine, damit sich Filter im Simulator ansehen lassen.
                    if ProcessInfo.processInfo.environment["CELLAR_DEMO"] == "1" {
                        let context = persistence.viewContext
                        if (try? context.count(for: Wine.fetchRequest())) == 0 {
                            for (name, country, type) in [("Cicero", "Schweiz", WineType.red), ("Jeninser", "Suisse", .red),
                                                          ("Cuvée Prestige", "Frankreich", .red), ("Barolo", "Italien", .red),
                                                          ("Chianti", "Italien", .red), ("Fendant", "Schweiz", .white)] {
                                Wine.create(in: context, cellar: Cellar.active(in: context), name: name, vintage: 2022, grape: "Merlot",
                                            country: country, type: type, quantity: 2)
                            }
                            context.saveChanges()
                        }
                    }
                    #endif
                    await rater.refresh()
                    rater.adoptExistingRatings(in: persistence.viewContext)
                    Task { await catalog.refreshDirectory() }
                    await catalog.refresh()
                }
        }
    }
}

// MARK: - AIService per Environment verfügbar machen

private struct AIServiceKey: EnvironmentKey {
    static let defaultValue = AIService()
}

extension EnvironmentValues {
    var aiService: AIService {
        get { self[AIServiceKey.self] }
        set { self[AIServiceKey.self] = newValue }
    }
}
