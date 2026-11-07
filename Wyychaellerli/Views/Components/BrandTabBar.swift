import SwiftUI

/// Eigene Tableiste in Weinrot mit erhabenem Scan-Knopf in der Mitte.
///
/// Die Systemleiste schwebt seit iOS 26 als Glas und lässt sich weder einfärben noch
/// um einen Mittelknopf ergänzen. Deshalb zeichnet `ContentView` die Reiter selbst.
struct BrandTabBar: View {

    @Binding var selection: AppTab
    let onScan: () -> Void
    /// Langes Drücken auf den Scan-Knopf: die Auswahl zeigt `ContentView`.
    var onShowOptions: () -> Void = {}

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.cellar, title: "Wyychällerli", symbol: "cabinet")
            item(.advisor, title: "Wein-Berater", symbol: "sparkles")
            ScanButton(onScan: onScan, onShowOptions: onShowOptions)
            item(.rack, title: "Regal", symbol: "square.grid.3x3")
            item(.ratings, title: "Bewertungen", symbol: "star")
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        // Ohne Home-Indikator (iPhone SE) gibt es unten keinen Sicherheitsabstand –
        // die Beschriftung stiesse sonst an den Bildschirmrand.
        .padding(.bottom, hasHomeIndicator ? 2 : 8)
        // Das Weinrot reicht bis unter den Home-Indikator und seitlich bis an den Rand: Auf
        // dem iPhone Duo steht rechts (oder links) ein senkrechter Streifen mit Uhr und
        // Knöpfen, die Leiste endete sonst davor und liess unten einen weissen Rest.
        // Die Reiter selbst bleiben innerhalb des sicheren Bereichs.
        .background(Brand.burgundy.ignoresSafeArea(edges: [.bottom, .horizontal]))
    }

    private var hasHomeIndicator: Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return (window?.safeAreaInsets.bottom ?? 0) > 0
    }

    private func item(_ tab: AppTab, title: LocalizedStringKey, symbol: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 30)
                    // Gewählter Reiter: dunkle Kapsel hinter dem Symbol, wie auf der Vorlage.
                    .background(isSelected ? Brand.deep.opacity(0.55) : .clear, in: Capsule())
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(.snappy, value: isSelected)
    }
}

/// Weisser Kreis, der über die Leiste hinausragt – der schnellste Weg zur neuen Flasche.
///
/// Ein Tipp öffnet sofort die Kamera, langes Drücken die Auswahl: Foto aus der
/// Mediathek oder ganz ohne Foto. Ohne Foto braucht es selten (Etikett unlesbar,
/// Flasche schon getrunken), deshalb kein eigener Knopf dafür.
///
/// **Nichts an der Leiste präsentieren** – kein `Menu`, kein `.contextMenu`, kein
/// `popoverTip`, kein `confirmationDialog`. Mit jedem davon zeichnete SwiftUI die Leiste
/// nach einem Reiterwechsel nicht mehr neu („AttributeGraph: cycle detected“): Die Leiste
/// wird vermessen (`onGeometryChange` in `ContentView`), und die Präsentation hängt an
/// ihrer Lage. Die Markierung blieb dann auf dem ersten Reiter stehen. Ein
/// `confirmationDialog` weiter oben in `ContentView` tat dasselbe. Deshalb nur Gesten; die
/// Auswahl ist ein Blatt (`ScanOptionsSheet`), der Tipp steht in der Kellerliste.
private struct ScanButton: View {
    let onScan: () -> Void
    let onShowOptions: () -> Void

    var body: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Brand.burgundy)
            .frame(width: 62, height: 62)
            .background(Circle().fill(.white))
            .overlay(Circle().strokeBorder(Brand.burgundy, lineWidth: 4))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .contentShape(Circle())
            .onTapGesture { onScan() }
            .onLongPressGesture(minimumDuration: 0.4) { onShowOptions() }
            .offset(y: -14)
            .padding(.bottom, -14)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Etikett scannen")
            .accessibilityAction { onScan() }
            .accessibilityAction(named: "Weitere Wege") { onShowOptions() }
    }
}

/// Wie viel Platz die Tableiste unten belegt, samt erhabenem Scan-Knopf.
///
/// Die Leiste liegt über den Reitern. Eine Ansicht mit eigener Knopfleiste unten
/// (`.safeAreaInset(edge: .bottom)`) muss sie um diesen Wert anheben, sonst liegt die
/// Knopfleiste hinter der Tableiste.
private struct TabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarClearance: CGFloat {
        get { self[TabBarClearanceKey.self] }
        set { self[TabBarClearanceKey.self] = newValue }
    }
}

#Preview {
    @Previewable @State var tab = AppTab.cellar
    VStack {
        Spacer()
        BrandTabBar(selection: $tab, onScan: {})
    }
}
