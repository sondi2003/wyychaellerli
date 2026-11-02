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
        .padding(.bottom, 2)
        .background(Brand.burgundy)
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

#Preview {
    @Previewable @State var tab = AppTab.cellar
    VStack {
        Spacer()
        BrandTabBar(selection: $tab) { }
    }
}
