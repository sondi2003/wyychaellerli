import SwiftUI

@main
struct WyychaellerliApp: App {
    @Environment(\.scenePhase) private var scenePhase

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
                // Kommt man nach einer Weile zurück in die App, steht die Liste wieder aktuell da.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await catalog.refreshDirectory(maxAge: 600) } }
                }
                .task(id: language) {
                    await localAI.refresh()
                }
                .task {
                    // Einmalige Übernahme aus der früheren SwiftData-Ablage.
                    LegacyImporter.importIfNeeded(into: persistence.viewContext)
                    // Alkoholgehalt aus den Notizen ins eigene Feld holen.
                    AlcoholNoteMigration.run(in: persistence.viewContext)
                    #if DEBUG
                    // Vorführung: Tipp auf eine Katalog-Mitteilung, ohne Push (im Simulator fehlt
                    // die Erlaubnis). `NOTIFY_DEMO=review` oder `=mine`.
                    switch ProcessInfo.processInfo.environment["NOTIFY_DEMO"] {
                    case "review": NotificationRouter.shared.open(.review(recordName: nil))
                    case "mine": NotificationRouter.shared.open(.mySubmissions)
                    default: break
                    }
                    // Vorführung: ein paar erfundene Weine, damit sich Filter im Simulator ansehen lassen.
                    if ProcessInfo.processInfo.environment["CELLAR_DEMO"] == "1" {
                        let context = persistence.viewContext
                        if (try? context.count(for: Wine.fetchRequest())) == 0 {
                            let cellar = Cellar.active(in: context)
                            let year = Calendar.current.component(.year, from: .now)
                            // Ein gezeichnetes „Etikett“, damit sich die grosse Bühne der Detailseite ansehen lässt.
                            let label = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 760)).image { ctx in
                                UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1).setFill()
                                ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 760))
                                UIColor(red: 0.45, green: 0.07, blue: 0.14, alpha: 1).setFill()
                                ctx.fill(CGRect(x: 60, y: 90, width: 480, height: 8))
                                ("CICERO" as NSString).draw(at: CGPoint(x: 150, y: 300), withAttributes: [
                                    .font: UIFont.systemFont(ofSize: 72, weight: .heavy),
                                    .foregroundColor: UIColor(red: 0.17, green: 0.02, blue: 0.05, alpha: 1)
                                ])
                            }.jpegData(compressionQuality: 0.8)
                            // (Name, Produzent, Jahrgang, Rebsorte, Region, Land, Art, Flaschen, Alkohol, ab, bis, Speisen)
                            let demo: [(String, String, Int, String, String, String, WineType, Int, Double, Int, Int, [String])] = [
                                ("Cicero Pinot Noir", "Weingut Cicero", year - 7, "Pinot Noir", "Bündner Herrschaft", "Schweiz", .red, 2, 13.5, year - 4, year, ["Rindsfilet", "Hartkäse", "Pilzrisotto"]),
                                ("Jeninser", "", year - 3, "Blauburgunder", "Graubünden", "Suisse", .red, 3, 13, year - 1, year + 3, []),
                                ("Cuvée Prestige", "Château Exemple", year - 9, "Merlot, Cabernet", "Bordeaux", "Frankreich", .red, 1, 14, year - 6, year - 1, ["Lamm"]),
                                ("Barolo", "Cantina Esempio", year - 5, "Nebbiolo", "Piemont", "Italien", .red, 6, 14.5, year + 2, year + 10, []),
                                ("Chianti Classico Riserva della Casa", "", year - 4, "Sangiovese", "Toskana", "Italien", .red, 2, 0, 0, 0, []),
                                ("Fendant", "", year - 1, "Chasselas", "Wallis", "Schweiz", .white, 4, 12, year - 1, year + 1, ["Raclette", "Fondue"]),
                                ("Crémant", "", 0, "Chardonnay", "Elsass", "Frankreich", .sparkling, 2, 12.5, 0, 0, ["Apéro"]),
                                ("Rosé d'été", "", year - 1, "Grenache", "Provence", "Frankreich", .rose, 1, 12.5, 0, 0, [])
                            ]
                            var first: Wine?
                            for entry in demo {
                                let wine = Wine.create(
                                    in: context, cellar: cellar, name: entry.0, producer: entry.1, vintage: entry.2,
                                    grape: entry.3, region: entry.4, country: entry.5, type: entry.6, quantity: entry.7,
                                    alcoholPercent: entry.8, foodPairings: entry.11,
                                    labelImageData: first == nil ? label : nil, drinkFrom: entry.9, drinkTo: entry.10)
                                if first == nil { first = wine }
                            }
                            if let first {
                                let rating = Rating.create(in: context, wine: first, raterID: "demo", raterName: "Demo")
                                rating.stars = 4
                            }
                            context.saveChanges()
                        }
                    }
                    #endif
                    await rater.refresh()
                    rater.adoptExistingRatings(in: persistence.viewContext)
                    Task { await catalog.refreshDirectory(maxAge: 600) }
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
