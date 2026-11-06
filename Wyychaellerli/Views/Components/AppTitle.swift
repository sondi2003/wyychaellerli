import SwiftUI

/// Navigationstitel, der beim Sprachwechsel **sofort** nachzieht – auch in Ansichten, die
/// gerade offen sind.
///
/// Ein `navigationTitle("Literal")` löst über die Umgebungssprache auf, und die erreicht
/// bereits präsentierte oder gerade neu aufgebaute Ansichten erst einen Schritt später; der
/// UIKit-Titel liest sie einmal und nie wieder. `tr` liest die gewählte Sprache direkt aus
/// `UserDefaults`. Der Modifier hängt zusätzlich an `AppLanguage.storageKey` und wertet den
/// Titel damit bei **jedem** Wechsel neu aus – ohne das bliebe der alte Text stehen, weil
/// die Ansicht selbst keinen Anlass hat, ihren Rumpf noch einmal zu rechnen.
///
/// Gilt für feste und berechnete Titel (`appTitle(tr("Filter"))`, `appTitle(mode.title)`).
/// Titel, die ein Datum der Nutzer sind (Weinname, Regalname), bleiben `navigationTitle`.
private struct AppTitleModifier: ViewModifier {

    let title: () -> String
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    func body(content: Content) -> some View {
        let _ = language
        return content.navigationTitle(title())
    }
}

extension View {
    func appTitle(_ title: @autoclosure @escaping () -> String) -> some View {
        modifier(AppTitleModifier(title: title))
    }
}
