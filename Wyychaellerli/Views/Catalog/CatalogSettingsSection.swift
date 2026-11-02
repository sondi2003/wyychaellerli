import SwiftUI

/// Abschnitt „Gemeinsamer Katalog“ in den Einstellungen.
struct CatalogSettingsSection: View {

    @Environment(CatalogCenter.self) private var catalog

    var body: some View {
        @Bindable var catalog = catalog
        Section {
            Toggle("Neue Weine vorschlagen", isOn: $catalog.contributesNewWines)
            NavigationLink {
                CatalogCellarCheckView()
            } label: {
                Label("Keller mit dem Katalog abgleichen", systemImage: "arrow.triangle.2.circlepath")
            }
            NavigationLink {
                MySubmissionsView()
            } label: {
                HStack {
                    Label("Meine Vorschläge", systemImage: "paperplane")
                    Spacer()
                    if !catalog.submissions.isEmpty {
                        Text(verbatim: "\(catalog.submissions.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #if DEBUG
            // Nur zum Prüfen der Darstellung ohne iCloud (Simulator):
            // `SIMCTL_CHILD_CATALOG_DEMO=1 xcrun simctl launch …`
            if ProcessInfo.processInfo.environment["CATALOG_DEMO"] != nil {
                NavigationLink {
                    AdminSubmissionEditor(group: .demo) { _ in }
                } label: {
                    Label("Vorführung: Vorschlag prüfen" as String, systemImage: "hammer")
                }
            }
            #endif
            if catalog.isAdmin {
                NavigationLink {
                    AdminReviewView()
                } label: {
                    HStack {
                        Label("Vorschläge prüfen", systemImage: "checkmark.shield")
                        Spacer()
                        if catalog.pendingCount > 0 {
                            Text(verbatim: "\(catalog.pendingCount)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Brand.onAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Brand.accent, in: Capsule())
                                .fixedSize()
                        }
                    }
                }
            }
        } header: {
            Text("Gemeinsamer Katalog")
        } footer: {
            Text("Der Katalog ergänzt beim Scannen fehlende Angaben. Eingeschaltet geht jeder neue Wein, der noch nicht drinsteht, zur Prüfung: nur Stammdaten und das Foto der Vorderseite, nie Notizen, Bewertungen oder Bestand. Über den Entscheid kommt eine Mitteilung.")
        }
    }
}

#Preview {
    NavigationStack {
        Form { CatalogSettingsSection() }
    }
    .environment(CatalogCenter())
}
