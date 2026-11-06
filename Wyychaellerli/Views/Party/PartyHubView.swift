import CoreData
import SwiftUI

/// „Party“: Einstieg in die Abstimmung unter Gästen – starten oder die Historie ansehen.
///
/// Ein eigenes Blatt, aufgerufen über den Party-Knopf links oben im Berater. Früher stand an
/// der Stelle eine Karte unter der Empfehlung; sie schob die eigentliche Aufgabe des Beraters
/// nach unten und war mit Karte, Knöpfen und Text doppelt so gross wie nötig.
///
/// **Gestartet wird erst, wenn das Blatt zu ist** (`onStart` meldet es, `AdvisorView` startet
/// im `onDismiss`): Die Party liegt in `ContentView` als Ebene über allem, ein noch offenes
/// Blatt läge davor.
struct PartyHubView: View {

    /// Wird gerufen, wenn die Party starten soll – kurz bevor sich das Blatt schliesst.
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var isMissingDeviceLock = false

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var fetched: FetchedResults<PartyWin>

    /// Nur die Abende **dieses** Kellers (siehe `PartyHistoryView`).
    private var winCount: Int {
        guard let cellar = Cellar.current(in: context) else { return fetched.count }
        return fetched.filter { $0.cellar == cellar }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    Button {
                        // Ohne Gerätesperre kein Party-Modus – sonst käme man nicht heraus.
                        if PartyLock.isAvailable {
                            onStart()
                            dismiss()
                        } else {
                            isMissingDeviceLock = true
                        }
                    } label: {
                        Label("Party starten", systemImage: "party.popper")
                    }
                    .buttonStyle(.brand(.filled, large: true))

                    NavigationLink {
                        PartyHistoryView(isEmbedded: true)
                    } label: {
                        HStack {
                            Label("Historie", systemImage: "trophy")
                            Spacer()
                            if winCount > 0 {
                                Text(verbatim: "\(winCount)")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .appTitle(tr("Party"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Gerät ohne Sperre", isPresented: $isMissingDeviceLock) {
                Button("Verstanden", role: .cancel) { }
            } message: {
                Text("Der Party-Modus lässt sich nur mit Face ID, Touch ID oder Gerätecode wieder verlassen. Richte in den iPhone-Einstellungen unter „Face ID & Code“ eine Sperre ein.")
            }
        }
    }

    /// Die zweite Antwort auf „Welche Flasche öffnen wir?“: nicht nach dem Essen, sondern
    /// nach Stimmen.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Gemeinsam abstimmen")
                    .font(.headline)
                    .foregroundStyle(.white)
            } icon: {
                Image(systemName: "party.popper.fill")
                    .foregroundStyle(Brand.rose)
            }
            Text("Die Gäste wählen, welche Flasche heute aufgeht. Das iPhone geht von Hand zu Hand.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Brand.rose.opacity(0.7), lineWidth: 1.5)
        )
    }
}

#Preview {
    PartyHubView(onStart: {})
        .environment(\.managedObjectContext, PreviewData.context)
}
