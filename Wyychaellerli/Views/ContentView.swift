import CoreData
import PhotosUI
import SwiftUI
import TipKit
import UIKit

/// Die Reiter der App. Der Scan in der Mitte ist kein Reiter, sondern öffnet die Kamera.
/// Die Einstellungen sind ebenfalls keiner: Man braucht sie selten, sie öffnen sich über
/// das Zahnrad oben im Keller (`openSettings`).
enum AppTab: Hashable {
    case cellar
    case advisor
    case rack
    case ratings
}

/// Öffnet die Einstellungen als Blatt – von jedem Reiter aus, ohne den Reiter zu wechseln.
private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var openSettings: @MainActor () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
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
    /// Der Scan-Knopf in der Mitte der Leiste: Kamera, dann Scan-Blatt, dann Formular.
    @State private var isCapturingFront = false
    @State private var capturedFront: UIImage?
    @State private var frontForScan: CapturedPhoto?
    @State private var pendingScan: LabelScanResult?
    @State private var finishedScan: LabelScanResult?
    /// Rückfall ohne Kamera: Formular mit Scan-Blatt darin.
    @State private var isScanning = false
    /// Langes Drücken auf den Scan-Knopf: Foto aus der Mediathek oder ganz ohne Foto.
    @State private var isPickingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isAddingManually = false
    @State private var isShowingScanOptions = false
    @State private var scanOption: ScanOptionsSheet.Option?
    @State private var isShowingSettings = false
    private let notificationRouter = NotificationRouter.shared
    @State private var isKeyboardVisible = false
    /// Gemessene Höhe der Leiste ohne Home-Indikator.
    @State private var tabBarHeight: CGFloat = 56
    /// Höhe der Leiste plus 16 pt für den erhabenen Scan-Knopf; bei offener Tastatur null.
    private var tabBarClearance: CGFloat { isKeyboardVisible ? 0 : tabBarHeight + 16 }
    /// Ein empfohlener Wein, den jemand als Datei geschickt hat.
    @State private var incomingShare: WineShare?

    /// Öffnet die Einstellungen, wenn eine Mitteilung ein Ziel dort hinterlassen hat und
    /// nichts im Weg ist. Bleibt das Ziel liegen, kommt es mit dem nächsten Anlass wieder hierher.
    private func openNotificationTarget() {
        guard notificationRouter.destination != nil, !isShowingSplash, !party.isRunning else { return }
        isShowingSettings = true
    }

    var body: some View {
        ZStack {
            // Eigene Leiste statt TabView-Leiste (siehe `BrandTabBar`). Alle Reiter bleiben
            // geladen, damit Navigation und Scrollstand beim Wechseln erhalten bleiben.
            ZStack(alignment: .bottom) {
                ZStack {
                    tab(.cellar) { CellarView() }
                    tab(.advisor) { AdvisorView() }
                    tab(.rack) { RackView(isTab: true) }
                    tab(.ratings) { RatingsOverviewView(isTab: true) }
                }
                // Die Leiste liegt über den Reitern; jede Liste bekommt ihre Höhe als
                // Rand am Ende des Inhalts. `.safeAreaInset` und `.safeAreaPadding` an
                // diesem Stapel kamen bei den Listen in den Navigationsstapeln nicht an:
                // Auf dem iPhone SE (ohne Home-Indikator) blieb das Ende jeder Liste unter
                // der Leiste. Die 16 pt sind der erhabene Scan-Knopf.
                .contentMargins(.bottom, tabBarClearance, for: .scrollContent)
                .contentMargins(.bottom, isKeyboardVisible ? 0 : tabBarHeight, for: .scrollIndicators)
                .environment(\.tabBarClearance, tabBarClearance)

                // Über der Tastatur stünde die Leiste nur im Weg.
                if !isKeyboardVisible {
                    BrandTabBar(
                        selection: $selectedTab,
                        onScan: startScan,
                        onShowOptions: showScanOptions
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
                }
            }
            .environment(\.openSettings) { isShowingSettings = true }
            // Ein Blatt, keine Blase: Unter iOS 26 verankern sich `confirmationDialog`,
            // `Menu`, `.contextMenu` und `popoverTip` an einer Stelle – und jede davon hielt
            // die Markierung der Leiste fest (siehe `ScanButton`). Blätter sind nicht
            // verankert. Der gewählte Weg startet erst nach dem Schliessen, sonst verschluckt
            // UIKit die zweite Präsentation.
            .sheet(isPresented: $isShowingScanOptions, onDismiss: runScanOption) {
                ScanOptionsSheet { scanOption = $0 }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(isSheet: true)
            }
            // Ein Foto aus der Mediathek nimmt denselben Weg wie eines aus der Kamera.
            .photosPicker(isPresented: $isPickingPhoto, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        frontForScan = CapturedPhoto(image: image)
                    }
                    pickedPhoto = nil
                }
            }
            .sheet(isPresented: $isAddingManually) {
                WineFormView(mode: .add)
            }
            // Mittelknopf: erst nur die Kamera, ohne Formular und Scan-Blatt darunter –
            // sonst stapeln sich drei Ebenen sichtbar übereinander. Danach das Scan-Blatt mit
            // der Vorderseite (für Rückseite und „Etikett lesen“), danach das Formular.
            .fullScreenCover(isPresented: $isCapturingFront, onDismiss: {
                if let image = capturedFront {
                    capturedFront = nil
                    frontForScan = CapturedPhoto(image: image)
                }
            }) {
                CameraCaptureView { image in
                    capturedFront = image
                    isCapturingFront = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $frontForScan, onDismiss: {
                if let result = pendingScan {
                    pendingScan = nil
                    finishedScan = result
                }
            }) { photo in
                LabelScanView(initialFront: photo.image) { result in
                    pendingScan = result
                }
            }
            .sheet(item: $finishedScan) { result in
                WineFormView(mode: .add, scanResult: result)
            }
            // Ohne Kamera (z. B. iPad ohne Rückkamera) der bisherige Weg übers Formular.
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
        // Tipp auf eine Katalog-Mitteilung: Die Einstellungen öffnen sich und führen selbst
        // zum Ziel (`SettingsView`). Erst nach dem Splash und nie während einer Party – der
        // Keller soll in der gesperrten Runde nicht über eine Mitteilung aufgehen.
        .onChange(of: notificationRouter.destination, initial: true) { openNotificationTarget() }
        .onChange(of: isShowingSplash) { openNotificationTarget() }
        .onChange(of: party.isRunning) { openNotificationTarget() }
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

    private func showScanOptions() {
        ScanOptionsTip().invalidate(reason: .actionPerformed)
        isShowingScanOptions = true
    }

    private func runScanOption() {
        guard let option = scanOption else { return }
        scanOption = nil
        switch option {
        case .camera: startScan()
        case .photos: isPickingPhoto = true
        case .manual: isAddingManually = true
        }
    }

    private func startScan() {
        if CameraCaptureView.isSupported {
            isCapturingFront = true
        } else {
            isScanning = true
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

/// Ein Foto als Wert für `.sheet(item:)`.
private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
        .environment(CatalogCenter())
}
