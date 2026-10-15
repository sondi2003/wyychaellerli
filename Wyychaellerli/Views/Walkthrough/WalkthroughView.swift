import SwiftUI

/// Die Einführung beim ersten Start: sechs Seiten, je ein gezeichnetes Bild und drei Sätze.
///
/// Erscheint einmal nach dem Splash und lässt sich in den Einstellungen wieder aufrufen.
/// Bewusst keine Screenshots, sondern gezeichnete Bilder: Die veralten nicht mit jeder
/// Änderung an der Oberfläche und funktionieren in Hell und Dunkel.
struct WalkthroughView: View {

    /// Einmal gesehen, nicht wieder – bis man es in den Einstellungen zurücksetzt.
    static let seenKey = "walkthrough.seen"

    @Environment(\.dismiss) private var dismiss
    @State private var page = WalkthroughView.startPage

    /// Nur zum Prüfen der Seiten ohne Tippen: `SIMCTL_CHILD_WALKTHROUGH_PAGE=3`.
    private static var startPage: Int {
        #if DEBUG
        return Int(ProcessInfo.processInfo.environment["WALKTHROUGH_PAGE"] ?? "") ?? 0
        #else
        return 0
        #endif
    }

    private let pages = WalkthroughPage.all
    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Überspringen") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(isLastPage ? 0 : 1)
                    .accessibilityHidden(isLastPage)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    pageView(item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Eigene Punkte statt der von iOS: Die sind auf hellem Grund kaum zu sehen.
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == page ? 20 : 7, height: 7)
                        .animation(.snappy, value: page)
                }
            }
            .padding(.bottom, 18)
            .accessibilityHidden(true)

            Button {
                if isLastPage {
                    finish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLastPage ? "Los geht's" : "Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityLabel("Einführung, Seite \(page + 1) von \(pages.count)")
    }

    private func pageView(_ item: WalkthroughPage) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                item.illustration
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(item.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }
}

// MARK: - Seiten

struct WalkthroughPage {
    let title: String
    let text: String
    let illustration: AnyView

    static var all: [WalkthroughPage] { [
        WalkthroughPage(
            title: tr("Willkommen im Wyychällerli"),
            text: tr("Dein Weinkeller in der Hosentasche: was da ist, wo es liegt und wozu es passt. Ein paar Wischer zeigen dir das Wichtigste."),
            illustration: AnyView(WelcomeIllustration())
        ),
        WalkthroughPage(
            title: tr("Etikett scannen statt tippen"),
            text: tr("Tippe oben rechts auf + und fotografiere die Flasche, wie sie steht. Die App findet das Etikett selbst, liest Name, Jahrgang, Rebsorte und Region und füllt alles vor. Fotografierst du auch die Rückseite, kommen die Notizen gleich mit."),
            illustration: AnyView(ScanIllustration())
        ),
        WalkthroughPage(
            title: tr("Bestand im Blick"),
            text: tr("Jede Zeile zeigt, wie viele Flaschen da sind. Mit dem Minus buchst du eine getrunkene Flasche ab. Bei der letzten fragt die App, ob der Wein ins Archiv soll."),
            illustration: AnyView(StockIllustration())
        ),
        WalkthroughPage(
            title: tr("Dein Regal"),
            text: tr("Unter dem Menü oben links legst du dein Regal an – mit so vielen Ebenen und Fächern, wie es wirklich hat. Tippe auf einen Wein und wisch über die freien Fächer, um seine Flaschen einzuräumen. Später pulsiert auf der Detailseite das Fach, in dem er liegt."),
            illustration: AnyView(RackIllustration())
        ),
        WalkthroughPage(
            title: tr("Der Wein-Berater"),
            text: tr("Sag, was es zu essen gibt. Der Berater schlägt bis zu drei Flaschen aus deinem Bestand vor und sagt ehrlich, wie gut sie passen. Geht auch per Siri."),
            illustration: AnyView(AdvisorIllustration())
        ),
        WalkthroughPage(
            title: tr("Zu zweit über iCloud"),
            text: tr("In den Einstellungen teilst du deinen Keller mit einer zweiten Apple-ID. Bestand, Regal und Bewertungen bleiben auf allen Geräten gleich – nimmt jemand eine Flasche, sehen es alle."),
            illustration: AnyView(ShareIllustration())
        ),
    ] }
}

#Preview {
    WalkthroughView()
}
