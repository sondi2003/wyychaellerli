import CoreData
import SwiftUI

/// Die eigenen Vorschläge mit ihrem Stand.
struct MySubmissionsView: View {

    @Environment(CatalogCenter.self) private var catalog
    @Environment(\.managedObjectContext) private var context
    @State private var recordName: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if catalog.submissions.isEmpty {
                Section {
                    Text(isLoading
                         ? tr("Lade …")
                         : tr("Noch keine Vorschläge. Schick einen Wein über seine Detailseite oder über „Keller abgleichen“."))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(catalog.submissions) { submission in
                        row(submission)
                    }
                } footer: {
                    Text("Über den Entscheid kommt eine Mitteilung, sofern du sie erlaubt hast.")
                }
            }

            // Für die Einrichtung des Admin-Bereichs: Diese Kennung kommt in der
            // CloudKit-Konsole in den Datensatz „admins“.
            if let recordName {
                Section {
                    Text(verbatim: recordName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Deine Katalog-Kennung")
                }
            }
        }
        .appTitle(tr("Meine Vorschläge"))
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await catalog.refresh() }
        .task {
            await catalog.refresh()
            recordName = await catalog.myRecordName()
            isLoading = false
        }
    }

    /// Etikett aus dem eigenen Keller – liegt schon auf dem Gerät, nichts wird geladen.
    /// Der Status steht unter dem Namen statt daneben, sonst drückt der Name ihn auf
    /// Breite null, und die Zeile wächst Buchstabe für Buchstabe in die Höhe.
    private func row(_ submission: CatalogSubmission) -> some View {
        HStack(spacing: 12) {
            if let wine = localWine(submission.wineUUID) {
                LabelThumbnail(wine: wine, size: 44)
            } else {
                Image(systemName: "wineglass")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: submission.vintage > 0 ? "\(submission.name) \(String(submission.vintage))" : submission.name)
                if !submission.producer.isEmpty {
                    Text(verbatim: submission.producer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: submission.status.symbolName)
                    Text(verbatim: submission.status.title)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(submission.status == .accepted ? Color.green : Brand.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func localWine(_ uuidString: String) -> Wine? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

#Preview {
    NavigationStack {
        MySubmissionsView()
    }
    .environment(CatalogCenter())
    .environment(\.managedObjectContext, PreviewData.context)
}
