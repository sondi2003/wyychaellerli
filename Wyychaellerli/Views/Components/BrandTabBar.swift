import SwiftUI

/// Eigene Tableiste: schwebende Glas-Kapsel mit vier Reitern, daneben der Scan-Knopf
/// als eigener Kreis in der Akzentfarbe.
///
/// Die Systemleiste kennt keinen abgesetzten Aktionsknopf in Markenfarbe. Deshalb zeichnet
/// `ContentView` die Reiter selbst. Ab iOS 26 ist die Kapsel echtes Glas (`glassEffect`),
/// davor ein Material. Der Inhalt läuft unter der Leiste durch; den Abstand am Ende der
/// Listen regelt `ContentView` über `contentMargins`.
struct BrandTabBar: View {

    @Binding var selection: AppTab
    /// Ob das Gerät unten einen Home-Indikator hat. Kommt von `ContentView`, das den
    /// sicheren Bereich über SwiftUI liest – **nicht** hier über `keyWindow.safeAreaInsets`:
    /// Das erzwingt mitten im Aufbau der Ansicht ein Layout und endete in
    /// „AttributeGraph: cycle detected“ (Leiste zeichnete nicht mehr neu).
    var hasHomeIndicator = true
    let onScan: () -> Void
    /// Langes Drücken auf den Scan-Knopf: die Auswahl zeigt `ContentView`.
    var onShowOptions: () -> Void = {}

    /// Höhe von Kapsel und Scan-Knopf – beide gleich hoch, damit sie als Paar lesen.
    static let barHeight: CGFloat = 58

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                item(.cellar, title: "Keller", symbol: "cabinet")
                item(.advisor, title: "Berater", symbol: "sparkles")
                item(.rack, title: "Regal", symbol: "square.grid.3x3")
                item(.ratings, title: "Bewertungen", symbol: "star")
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(height: Self.barHeight)
            .barGlass(in: Capsule())

            ScanButton(onScan: onScan, onShowOptions: onShowOptions)
        }
        .padding(.horizontal, 12)
        // Mit Home-Indikator rückt die Leiste etwas in den sicheren Bereich hinein, wie die
        // Systemleiste von iOS 26 – sonst schwebte sie auffällig hoch. Ohne Home-Indikator
        // (iPhone SE) braucht sie Abstand zum Bildschirmrand.
        .padding(.bottom, Self.bottomPadding(hasHomeIndicator: hasHomeIndicator))
        // Die Beschriftung wächst mit der Systemschrift, aber nur so weit, wie vier Reiter
        // nebeneinander Platz haben.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private static func bottomPadding(hasHomeIndicator: Bool) -> CGFloat { hasHomeIndicator ? -10 : 8 }

    /// Was die Leiste über dem sicheren Bereich belegt. `ContentView` rechnet damit den
    /// Abstand am Ende der Listen aus – bewusst ohne Vermessung der Leiste.
    static func occupiedHeight(hasHomeIndicator: Bool) -> CGFloat {
        barHeight + bottomPadding(hasHomeIndicator: hasHomeIndicator)
    }

    private func item(_ tab: AppTab, title: LocalizedStringKey, symbol: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.primary.opacity(0.62)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Gewählter Reiter: zarte Pille im Akzent, Symbol und Schrift ebenfalls.
            .background(isSelected ? Brand.accent.opacity(0.14) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(.snappy, value: isSelected)
    }
}

/// Kreis in der Akzentfarbe neben der Kapsel – der schnellste Weg zur neuen Flasche.
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
            .font(.title3.weight(.semibold))
            .foregroundStyle(Brand.onAccent)
            .frame(width: BrandTabBar.barHeight, height: BrandTabBar.barHeight)
            .scanGlass()
            .contentShape(Circle())
            .onTapGesture { onScan() }
            .onLongPressGesture(minimumDuration: 0.4) { onShowOptions() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Etikett scannen")
            .accessibilityAction { onScan() }
            .accessibilityAction(named: "Weitere Wege") { onShowOptions() }
    }
}

private extension View {

    /// Grund der Kapsel: ab iOS 26 Glas, davor ein Material mit feinem Rand.
    @ViewBuilder
    func barGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    /// Grund des Scan-Knopfs: ab iOS 26 getöntes Glas, das auf Berührung reagiert,
    /// davor ein gefüllter Kreis.
    @ViewBuilder
    func scanGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(Brand.accent).interactive(), in: Circle())
        } else {
            background(Brand.accent, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
    }
}

/// Wie viel Platz die Tableiste unten belegt, samt etwas Luft darüber.
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
