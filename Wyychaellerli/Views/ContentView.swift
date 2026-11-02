import CoreData
import SwiftUI
import UIKit

/// Die Reiter der App. Der Scan in der Mitte ist kein Reiter, sondern öffnet ein Blatt.
enum AppTab: Hashable {
    case cellar
    case advisor
    case rack
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
    /// Ein Sprachwechsel baut die Tabs neu auf, damit auch berechnete Texte nachziehen.
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var isShowingSplash = true
    @AppStorage(WalkthroughView.seenKey) private var hasSeenWalkthrough = false
    @State private var isShowingWalkthrough = false
    /// Der Scan-Knopf in der Mitte der Leiste.
    @State private var isScanning = false
    @State private var isKeyboardVisible = false
    /// Ein empfohlener Wein, den jemand als Datei geschickt hat.
    @State private var incomingShare: WineShare?

    var body: some View {
        ZStack {
            // Eigene Leiste statt TabView-Leiste (siehe `BrandTabBar`). Alle Reiter bleiben
            // geladen, damit Navigation und Scrollstand beim Wechseln erhalten bleiben.
            ZStack {
                tab(.cellar) { CellarView() }
                tab(.advisor) { AdvisorView(selectedTab: $selectedTab) }
                tab(.rack) { RackView(isTab: true) }
                tab(.settings) { SettingsView() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Über der Tastatur stünde die Leiste nur im Weg.
                if !isKeyboardVisible {
                    BrandTabBar(selection: $selectedTab) { isScanning = true }
                }
            }
            .sheet(isPresented: $isScanning) {
                WineFormView(mode: .add, startWithScanner: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
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

    /// Ein Reiter, nur sichtbar und bedienbar, wenn er gewählt ist.
    /// Ein Sprachwechsel baut ihn neu auf, damit auch berechnete Texte nachziehen.
    private func tab(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = selectedTab == tab
        return content()
            .id(language)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
}
