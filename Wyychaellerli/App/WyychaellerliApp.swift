import SwiftUI

@main
struct WyychaellerliApp: App {

    /// Nötig, damit Freigabe-Einladungen ankommen (siehe SceneDelegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Core Data mit CloudKit. Wird von App und Siri-Intent gemeinsam genutzt.
    private let persistence = PersistenceController.shared

    /// Einstellungen (Provider, Modelle, Keys) – einmal pro App-Lebenszyklus.
    @State private var settings = AISettings()

    /// Wer an diesem Gerät bewertet (Kennung aus iCloud, Name aus den Einstellungen).
    @State private var rater = CurrentRater()

    /// Ob gerade eine Party läuft. Muss über der ganzen App liegen, damit der gesperrte
    /// Modus auch einen Neustart übersteht.
    @State private var party = PartySession()

    /// Der KI-Service ist zustandslos und kann geteilt werden.
    private let aiService = AIService()

    /// Hell, dunkel oder dem System folgen. Gilt für die ganze App.
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system

    init() {
        QuickTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(rater)
                .environment(party)
                .environment(\.aiService, aiService)
                .environment(\.managedObjectContext, persistence.viewContext)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    // Einmalige Übernahme aus der früheren SwiftData-Ablage.
                    LegacyImporter.importIfNeeded(into: persistence.viewContext)
                    // Alkoholgehalt aus den Notizen ins eigene Feld holen.
                    AlcoholNoteMigration.run(in: persistence.viewContext)
                    await rater.refresh()
                    rater.adoptExistingRatings(in: persistence.viewContext)
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
