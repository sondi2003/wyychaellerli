import SwiftUI
import UIKit

/// Beobachtet, ob der geführte Zugriff von iOS gerade läuft.
///
/// **Die App kann ihn nicht selbst einschalten.** Es gibt zwar `requestGuidedAccessSession`,
/// das funktioniert aber nur auf Geräten, die von einer Geräteverwaltung (MDM) dafür
/// freigegeben wurden – auf einem privaten iPhone schlägt der Aufruf fehl. Was die App
/// tun kann: erkennen, ob er läuft, und den Weg dorthin zeigen.
@Observable
@MainActor
final class GuidedAccessMonitor {

    private(set) var isActive = UIAccessibility.isGuidedAccessEnabled

    init() {
        // Der Beobachter lebt so lange wie die App; ein `deinit` zum Abmelden ginge
        // nicht, weil dieser Typ am Hauptakteur hängt und `deinit` das nicht ist.
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isActive = UIAccessibility.isGuidedAccessEnabled
            }
        }
    }
}

/// Erklärt vor dem Weitergeben, wie das Gerät auf diese App festgenagelt wird.
///
/// Ohne geführten Zugriff kann ein Gast zwar nicht an den Keller – der Party-Modus kommt
/// nach jedem Wegwischen zurück –, wohl aber in andere Apps.
struct GuidedAccessCard: View {

    let isActive: Bool

    var body: some View {
        if isActive {
            Label("Geführter Zugriff läuft – das Gerät bleibt auf dieser App.", systemImage: "lock.shield.fill")
                .font(.footnote)
                .foregroundStyle(Brand.success)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Brand.success.opacity(0.12), in: RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Bevor du weitergibst", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                Text("Drücke jetzt **dreimal die Seitentaste** und tippe auf „Starten“. Dann bleibt das Gerät auf dieser App, bis du es wieder freigibst – niemand kommt in andere Apps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Beim ersten Mal muss der geführte Zugriff eingeschaltet werden: iPhone-Einstellungen → Bedienungshilfen → Geführter Zugriff. Dort auch einen Code oder Face ID festlegen.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
        }
    }
}
