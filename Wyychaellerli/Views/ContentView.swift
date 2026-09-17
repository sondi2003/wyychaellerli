import CoreData
import SwiftUI

/// Die drei Tabs der App.
enum AppTab: Hashable {
    case cellar
    case advisor
    case settings
}

struct ContentView: View {

    /// Liest eine Empfehlungsdatei ein.
    ///
    /// Kommt sie aus einer anderen App, liegt sie ausserhalb unseres Sandkastens –
    /// ohne `startAccessingSecurityScopedResource` gäbe es keinen Lesezugriff.
    static func readShare(at url: URL) -> WineShare? {
        guard url.pathExtension.lowercased() == WineShare.fileExtension else { return nil }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? WineShare.decoded(from: data)
    }


    @Environment(\.managedObjectContext) private var context
    @Environment(PartySession.self) private var party

    @State private var selectedTab: AppTab = .cellar
    @State private var isShowingSplash = true
    @AppStorage(WalkthroughView.seenKey) private var hasSeenWalkthrough = false
    @State private var isShowingWalkthrough = false
    /// Ein empfohlener Wein, den jemand als Datei geschickt hat.
    @State private var incomingShare: WineShare?

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                CellarView()
                    .tabItem { Label("Wyychällerli", systemImage: "cabinet") }
                    .tag(AppTab.cellar)

                AdvisorView(selectedTab: $selectedTab)
                    .tabItem { Label("Wein-Berater", systemImage: "sparkles") }
                    .tag(AppTab.advisor)

                SettingsView()
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }

            if isShowingSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(1)
            }

            // Über allem: Wer das Gerät in der Hand hat, kommt nur mit Code heraus.
            // Auch nach einem Neustart – deshalb hier und nicht als Sheet in der Liste.
            if let model = party.model {
                PartyView(model: model) { party.end() }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: party.isRunning)
        .onAppear { party.restoreIfNeeded(in: context) }
        // Eine .wyy-Datei aus Nachrichten, Mail oder Dateien: erst zeigen, dann übernehmen.
        .onOpenURL { url in
            guard !party.isRunning, let share = Self.readShare(at: url) else { return }
            incomingShare = share
        }
        .sheet(item: $incomingShare) { share in
            WineImportSheet(share: share)
        }
        .task {
            try? await Task.sleep(for: SplashView.displayDuration)
            withAnimation(.easeInOut(duration: 0.5)) {
                isShowingSplash = false
            }
            // Die Einführung kommt erst, wenn der Splash weg ist – sonst überlagern sie sich.
            // Und nie während einer Party: Der gesperrte Modus muss der oberste bleiben.
            if !hasSeenWalkthrough, !party.isRunning {
                try? await Task.sleep(for: .milliseconds(400))
                isShowingWalkthrough = true
            }
        }
        .fullScreenCover(isPresented: $isShowingWalkthrough) {
            WalkthroughView()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
}
