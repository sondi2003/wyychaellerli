import CoreData
import PhotosUI
import SwiftUI
import TipKit
import UIKit

/// Die Reiter der App. Die Einstellungen sind keiner: Man braucht sie selten, sie öffnen
/// sich über das Zahnrad oben im Keller (`openSettings`).
enum AppTab: Hashable {
    case cellar
    case advisor
    case rack
    case ratings
    /// Der abgesetzte Scan-Knopf der Leiste. Wird nie gewählt: Der Tipp öffnet die Kamera.
    case scan
}

/// Die Wege zum neuen Wein: Kamera (Scan-Knopf der Leiste), Mediathek, ohne Foto.
enum AddWineOption { case camera, photos, manual }

/// Startet einen der Wege zum neuen Wein – vom Plus-Menü im Keller aus.
private struct AddWineKey: EnvironmentKey {
    static let defaultValue: @MainActor (AddWineOption) -> Void = { _ in }
}

extension EnvironmentValues {
    var addWine: @MainActor (AddWineOption) -> Void {
        get { self[AddWineKey.self] }
        set { self[AddWineKey.self] = newValue }
    }
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
    /// Der Scan-Knopf neben der Leiste: Kamera, dann Scan-Blatt, dann Formular.
    @State private var isCapturingFront = false
    @State private var capturedFront: UIImage?
    @State private var frontForScan: CapturedPhoto?
    @State private var pendingScan: LabelScanResult?
    @State private var finishedScan: LabelScanResult?
    /// Rückfall ohne Kamera: Formular mit Scan-Blatt darin.
    @State private var isScanning = false
    /// Plus-Menü im Keller: Foto aus der Mediathek oder ganz ohne Foto.
    @State private var isPickingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isAddingManually = false
    @State private var isShowingSettings = false
    private let notificationRouter = NotificationRouter.shared
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
            tabs
            .environment(\.openSettings) { isShowingSettings = true }
            .environment(\.addWine) { add($0) }
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
            // Scan-Knopf: erst nur die Kamera, ohne Formular und Scan-Blatt darunter –
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

    // MARK: Leiste

    /// Die Systemleiste: vier Reiter und ein abgesetzter fünfter als Scan-Knopf
    /// (`TabRole.prominent`, neu in iOS 27). Er wird nie wirklich gewählt – die Bindung
    /// fängt den Tipp ab und öffnet die Kamera. Beim Scrollen nach unten zieht sich die
    /// Leiste auf den aktiven Reiter zusammen.
    ///
    /// Bis 24.11.2026 stand hier eine eigene Leiste (`BrandTabBar`): Die Systemleiste liess
    /// sich nicht weinrot färben und kannte keinen Aktionsknopf. Beides ist erledigt – die
    /// Leiste ist Glas, und `.prominent` ist der Aktionsknopf.
    private var tabs: some View {
        let selection = Binding<AppTab>(
            get: { selectedTab },
            set: { newValue in
                if newValue == .scan { startScan() } else { selectedTab = newValue }
            }
        )
        // `.id(language)`: Ein Sprachwechsel baut die Reiter neu auf, damit auch berechnete
        // Texte nachziehen.
        return TabView(selection: selection) {
            Tab("Keller", systemImage: "cabinet", value: AppTab.cellar) { CellarView().id(language) }
            Tab("Berater", systemImage: "sparkles", value: AppTab.advisor) { AdvisorView().id(language) }
            Tab("Regal", systemImage: "square.grid.3x3", value: AppTab.rack) { RackView(isTab: true).id(language) }
            Tab("Bewertungen", systemImage: "star", value: AppTab.ratings) { RatingsOverviewView(isTab: true).id(language) }
            Tab("Etikett scannen", systemImage: "camera.fill", value: AppTab.scan, role: .prominent) { Color.clear }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private func add(_ option: AddWineOption) {
        ScanOptionsTip().invalidate(reason: .actionPerformed)
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
