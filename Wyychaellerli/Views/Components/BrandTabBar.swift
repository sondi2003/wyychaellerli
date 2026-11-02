import SwiftUI

/// Eigene Tableiste in Weinrot mit erhabenem Scan-Knopf in der Mitte.
///
/// Die Systemleiste schwebt seit iOS 26 als Glas und lässt sich weder einfärben noch
/// um einen Mittelknopf ergänzen. Deshalb zeichnet `ContentView` die Reiter selbst.
struct BrandTabBar: View {

    @Binding var selection: AppTab
    let onScan: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.cellar, title: "Wyychällerli", symbol: "cabinet")
            item(.advisor, title: "Wein-Berater", symbol: "sparkles")
            scanButton
            item(.rack, title: "Regal", symbol: "square.grid.3x3")
            item(.settings, title: "Einstellungen", symbol: "gearshape")
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        // Ohne Home-Indikator (iPhone SE) gibt es unten keinen Sicherheitsabstand –
        // die Beschriftung stiesse sonst an den Bildschirmrand.
        .padding(.bottom, hasHomeIndicator ? 2 : 8)
        // Das Weinrot reicht bis unter den Home-Indikator.
        .background(Brand.burgundy.ignoresSafeArea(edges: .bottom))
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

    /// Weisser Kreis, der über die Leiste hinausragt – der schnellste Weg zur neuen Flasche.
    private var scanButton: some View {
        Button(action: onScan) {
            Image(systemName: "camera.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Brand.burgundy)
                .frame(width: 62, height: 62)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Brand.burgundy, lineWidth: 4))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .offset(y: -14)
        .padding(.bottom, -14)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Etikett scannen")
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
        BrandTabBar(selection: $tab) { }
    }
}
