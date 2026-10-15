import CoreData
import SwiftUI
import UIKit

/// Der Party-Modus: gesperrter Vollbild-Ablauf, durch den das Gerät wandert.
///
/// Nichts hier führt in den Rest der App – kein Tab, keine Toolbar, kein Weg zur
/// Detailseite. Hinaus kommt nur, wer den Code kennt (oder Face ID hat).
struct PartyView: View {

    @Environment(\.managedObjectContext) private var context

    @State private var model: PartyViewModel
    /// Wird gerufen, wenn die Party beendet ist.
    let onFinish: () -> Void

    @State private var isConfirmingAbort = false
    /// Ob das Gerät gerade auf diese App festgenagelt ist.
    @State private var guidedAccess = GuidedAccessMonitor()

    init(model: PartyViewModel, onFinish: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                content
            }
        }
        // Das Gerät wandert von Hand zu Hand – schaltet sich der Bildschirm ab, braucht
        // der nächste Gast den Gerätecode, und die Party steht.
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.resolveCandidates(in: context)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog(
            "Abstimmung verwerfen?",
            isPresented: $isConfirmingAbort,
            titleVisibility: .visible
        ) {
            Button("Verwerfen", role: .destructive) {
                model.discard()
                onFinish()
            }
            Button("Weitermachen", role: .cancel) { }
        } message: {
            Text("Die bisherigen Stimmen gehen verloren.")
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack {
            Label("Party", systemImage: "party.popper.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Spacer()
            // Grünes Schild = das Gerät kann nicht verlassen werden.
            if guidedAccess.isActive {
                Image(systemName: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Geführter Zugriff läuft")
            }
            Text(phaseTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                Task { await unlock() }
            } label: {
                Image(systemName: "lock.fill")
                    .font(.subheadline)
                    .padding(8)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Party beenden")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var phaseTitle: String {
        switch model.state.phase {
        case .candidates: return tr("Flaschen wählen")
        case .guests:     return tr("Wer ist dabei?")
        case .handover:   return tr("Weitergeben")
        case .voting:     return tr("Abstimmen")
        case .draw:       return tr("Auslosung")
        case .podium:     return tr("Ergebnis")
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        switch model.state.phase {
        case .candidates:
            PartyCandidatesView(model: model)
        case .guests:
            PartyGuestsView(model: model, isGuidedAccessActive: guidedAccess.isActive)
        case .handover:
            PartyHandoverView(model: model)
        case .voting:
            PartyVotingView(model: model)
        case .draw:
            PartyDrawView(model: model)
        case .podium:
            // Auch vom Podest aus geht es nur über die Gerätesperre hinaus – sonst
            // könnte ein Gast am Schluss einfach weiterklicken.
            PartyPodiumView(model: model) { Task { await unlock() } }
        }
    }

    // MARK: Beenden

    /// Gerätesperre abfragen. Beim Gast schlägt Face ID fehl (falsches Gesicht), und die
    /// Code-Eingabe kennt er nicht – genau das ist der Riegel.
    private func unlock() async {
        guard await PartyLock.unlock(reason: "Party-Modus verlassen") else { return }
        finish()
    }

    /// Steht ein Sieger fest, wandert er in die Historie – sonst wird gefragt.
    private func finish() {
        if model.state.winnerID != nil {
            model.recordResult(in: context)
            model.discard()
            onFinish()
        } else if model.hasAnyVote {
            isConfirmingAbort = true
        } else {
            model.discard()
            onFinish()
        }
    }
}

// MARK: - Übergabe

/// Zwischenschirm von Gast zu Gast.
///
/// Ohne ihn sähe der Nächste noch die Auswahl seines Vorgängers – und wüsste, was
/// gerade gewählt wurde. Der neue Gast tippt selbst, damit er die Karten frisch sieht.
struct PartyHandoverView: View {

    @Bindable var model: PartyViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.wave.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)

            if let guest = model.state.currentGuest {
                VStack(spacing: 8) {
                    Text("Bitte weitergeben an")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(guest.name)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                }

                Text("\(model.state.votesPerGuest) Stimmen – höchstens eine je Flasche.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    model.beginTurn()
                } label: {
                    Text("Ich bin's, los geht's")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)

                Button("Aussetzen, jemand anderes zuerst") {
                    model.skipTurn()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Noch offen: \(model.state.pendingGuests.count)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
