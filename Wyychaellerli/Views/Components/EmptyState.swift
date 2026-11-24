import SwiftUI

/// Der eine Leerzustand der App: Symbol im zarten Kreis, Titel, ein Satz, darunter – wo es
/// etwas zu tun gibt – ein Marken-Knopf und allenfalls eine kleine Zusatzzeile.
///
/// Ersetzt `ContentUnavailableView` auf den ganzen Seiten (leerer Keller, Regal,
/// Bewertungen, Statistik, Archiv): Dort standen weisser und grauer Grund, drei
/// Knopfformen und ein graues Symbol nebeneinander.
struct EmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let message: LocalizedStringKey
    /// Kleine Zeile unter dem Knopf, z. B. ein Hinweis auf iCloud.
    var footnote: LocalizedStringKey? = nil
    /// `false` in einer Liste oder unter anderem Inhalt: dann ohne eigenen Grund und ohne
    /// die ganze Höhe zu füllen.
    var fillsScreen = true
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 72, height: 72)
                .background(Brand.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            VStack(spacing: 10) {
                actions()
            }
            .padding(.top, 20)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: fillsScreen ? .infinity : nil)
        .background(fillsScreen ? Color(.systemGroupedBackground) : Color.clear)
    }
}

extension EmptyState where Actions == EmptyView {
    init(title: LocalizedStringKey, symbol: String, message: LocalizedStringKey,
         footnote: LocalizedStringKey? = nil, fillsScreen: Bool = true) {
        self.init(title: title, symbol: symbol, message: message, footnote: footnote,
                  fillsScreen: fillsScreen, actions: { EmptyView() })
    }
}

#Preview {
    EmptyState(title: "Noch kein Regal", symbol: "square.grid.3x3",
               message: "Lege dein Regal an, dann kannst du deine Flaschen darin einräumen und später wiederfinden.") {
        Button("Regal anlegen") {}.buttonStyle(.brandFilled)
    }
}
