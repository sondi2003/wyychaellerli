import SwiftUI

/// Schalter oben rechts im Berater: Lokale KI oder die externe KI mit hinterlegtem Key.
///
/// Zeigt, wer antwortet, und wechselt mit einem Tipp (`AISettings.prefersExternal`, dieselbe
/// Einstellung wie „Externe KI zuerst fragen“ in den Einstellungen). **Nur sichtbar, wenn es
/// etwas zu schalten gibt**: ein Key ist hinterlegt *und* ein lokales Modell ist nutzbar. Mit
/// nur einer Möglichkeit wäre es eine Anzeige ohne Wirkung. Die Wahl zwischen mehreren
/// Anbietern bleibt in den Einstellungen.
struct AdvisorSourceToggle: View {

    let settings: AISettings
    let local: LocalAIStatus

    /// Gibt es zwei Wege, zwischen denen man wählen kann?
    static func isAvailable(hasExternalKey: Bool, hasLocalModel: Bool) -> Bool {
        hasExternalKey && hasLocalModel
    }

    var body: some View {
        if let provider = settings.activeProvider, let localSource = local.primary {
            let isExternal = settings.prefersExternal
            let name = isExternal ? provider.displayName : localSource.shortName
            Button {
                settings.prefersExternal.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExternal ? provider.symbolName : localSource.symbolName)
                    Text(verbatim: name)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
            }
            .sensoryFeedback(.selection, trigger: isExternal)
            .accessibilityLabel(Text(verbatim: tr("Aktive Quelle: \(name)")))
            .accessibilityHint(Text("Wechselt zwischen lokaler und externer KI."))
        }
    }
}
