import CloudKit
import CoreData
import SwiftUI

/// Abschnitt „Teilen“ in den Einstellungen: Keller für eine zweite Person freigeben,
/// Teilnehmer sehen, Freigabe verwalten.
struct CellarSharingSection: View {

    @Environment(\.managedObjectContext) private var context

    @State private var share: CKShare?
    @State private var isPreparing = false
    /// Was der Freigabe-Dialog braucht – als **ein** Wert.
    ///
    /// Vorher hingen Freigabe und Container an getrennten Zuständen und das Sheet prüfte
    /// beide beim Aufbauen. Direkt nach dem Anlegen einer Freigabe meldet der Speicher
    /// eine Änderung, `refresh()` lief los und setzte `share` kurz auf `nil` – der Inhalt
    /// des Sheets wurde leer und es schloss sich sofort wieder. Beim zweiten Tippen war
    /// die Freigabe gefunden und es klappte. Mit einem Wert kann das nicht mehr passieren.
    @State private var presentation: SharePresentation?
    @State private var errorMessage: String?
    /// Ist der Keller von jemand anderem geteilt worden, gibt es hier nichts zu verwalten.
    @State private var isGuest = false
    /// Konnte der geteilte Speicher nicht geladen werden, ist keine Einladung annehmbar.
    @State private var isSharedStoreMissing = false

    /// Eingeladene Personen ohne den Eigentümer. Zählt auch Einladungen, die noch offen sind.
    private var participants: [CKShare.Participant] {
        (share?.participants ?? []).filter { $0.role != .owner }
    }

    /// Eine angelegte, aber nie verschickte Freigabe gilt noch nicht als geteilt.
    private var isActuallyShared: Bool { !participants.isEmpty }

    var body: some View {
        Section {
            if isSharedStoreMissing {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Geteilte Ablage nicht verfügbar")
                            .font(.body.weight(.semibold))
                        Text("Solange sie fehlt, kann keine Einladung angenommen werden – ein mit dir geteilter Keller bliebe unsichtbar. Meist hilft ein Neustart der App; bleibt es dabei, prüfe die iCloud-Anmeldung.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if isGuest {
                Label {
                    Text("Ein Weinkeller wurde mit dir geteilt. Verwalten kann ihn nur die Person, die ihn freigegeben hat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } else if isActuallyShared {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keller ist freigegeben")
                            .font(.body.weight(.semibold))
                        Text(participants.count == 1
                             ? "1 weitere Person hat Zugriff."
                             : "\(participants.count) weitere Personen haben Zugriff.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Button {
                    guard let share else { return }
                    presentation = SharePresentation(
                        share: share,
                        container: CKContainer(identifier: PersistenceController.cloudContainerIdentifier)
                    )
                } label: {
                    Label("Freigabe verwalten", systemImage: "person.crop.circle.badge.checkmark")
                }
            } else {
                Button {
                    Task { await prepareShare() }
                } label: {
                    HStack {
                        Label("Weinkeller teilen", systemImage: "square.and.arrow.up")
                        if isPreparing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Teilen")
        } footer: {
            if isGuest {
                Text("Änderungen am Bestand sehen beide Seiten.")
            } else {
                Text("Lade eine Person mit eigener Apple-ID ein. Beide sehen denselben Bestand, auch wenn eine Flasche abgebucht wird.")
            }
        }
        .sheet(item: $presentation, onDismiss: {
            // Teilnehmerliste kann sich geändert haben, auch durch „Freigabe beenden“.
            refresh()
        }) { presented in
            CloudSharingView(share: presented.share, container: presented.container, title: "Wyychällerli")
                .ignoresSafeArea()
        }
        .task { refresh() }
        // Die Daten der Gegenseite treffen verzögert ein; dann neu bewerten.
        .onReceive(NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange
        )) { _ in
            refresh()
        }
    }

    // MARK: Aktionen

    private func refresh() {
        // Während der Dialog offen ist, nichts anfassen – er verwaltet die Freigabe selbst.
        guard presentation == nil else { return }
        isSharedStoreMissing = !PersistenceController.shared.isSharedStoreAvailable
        // Gibt es einen Keller aus der geteilten Ablage, sind wir Gast.
        if Cellar.sharedWithMe(in: context) != nil {
            isGuest = true
            share = nil
            return
        }
        isGuest = false
        // Bewusst ohne Anlegen: Das blosse Öffnen der Einstellungen soll keinen Keller erzeugen.
        if let cellar = Cellar.own(in: context) {
            share = PersistenceController.shared.existingShare(for: cellar)
        } else {
            // Zweites Gerät, auf dem der Keller noch nicht eingetroffen ist: Die Freigabe
            // kann trotzdem schon im Speicher liegen.
            share = PersistenceController.shared.sharesInPrivateStore().first
        }
    }

    /// Übersetzt die technischen CloudKit-Meldungen in etwas Lesbares.
    private static func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return tr("Du bist auf diesem Gerät nicht in iCloud angemeldet. Melde dich in den Systemeinstellungen an und versuch es erneut.")
            case .networkUnavailable, .networkFailure:
                return tr("Keine Verbindung zu iCloud. Bitte später erneut versuchen.")
            case .quotaExceeded:
                return tr("Dein iCloud-Speicher ist voll.")
            default:
                break
            }
        }
        if text.contains("ckaccountstatusnoaccount") || text.contains("without an icloud account") {
            return tr("Du bist auf diesem Gerät nicht in iCloud angemeldet. Melde dich in den Systemeinstellungen an und versuch es erneut.")
        }
        if text.contains("network") {
            return tr("Keine Verbindung zu iCloud. Bitte später erneut versuchen.")
        }
        return tr("Die Freigabe hat nicht geklappt. Bitte später erneut versuchen.")
    }

    private func prepareShare() async {
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        let cellar = Cellar.findOrCreateOwn(in: context)
        do {
            // Eine bereits angelegte Freigabe wiederverwenden, sonst entstehen Dubletten.
            if let existing = share {
                // Freigaben aus früheren Versionen haben noch keinen Titel.
                let titled = await PersistenceController.shared.ensuringTitle(on: existing)
                share = titled
                presentation = SharePresentation(
                    share: titled,
                    container: CKContainer(identifier: PersistenceController.cloudContainerIdentifier)
                )
                return
            }
            let (newShare, container) = try await PersistenceController.shared.share(cellar)
            share = newShare
            presentation = SharePresentation(share: newShare, container: container)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }
}

// MARK: - Was der Freigabe-Dialog braucht

/// Freigabe und Container zusammen, damit das Sheet an einen konkreten Wert gebunden ist
/// und nicht mitten in der Darstellung leer werden kann.
private struct SharePresentation: Identifiable {
    let share: CKShare
    let container: CKContainer
    var id: String { share.recordID.recordName }
}
