import CoreData
import SwiftUI

/// Zeilen, Spalten und Name des Regals.
///
/// Verkleinern kann Fächer ausserhalb des Rasters lassen. Statt sie stillschweigend zu
/// löschen, nennt die Ansicht die Zahl der betroffenen Flaschen; sie werden nur aus dem
/// Regal genommen, der Bestand bleibt.
struct RackEditorView: View {

    @ObservedObject var rack: Rack
    /// Das letzte Regal darf nicht gelöscht werden – sonst stünde man ohne da.
    var canDelete = false
    var onDelete: () -> Void = {}

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var rows = 1
    @State private var columns = 12
    @State private var isConfirmingDelete = false

    private var losingSlots: [Slot] {
        rack.slotsOutsideGrid(rows: rows, columns: columns)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Regal", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    if (rack.cellar?.rackCount ?? 1) > 1 {
                        Text("Steht bei mehreren Regalen an jedem Fach – „\(name.isEmpty ? "Regal" : name) · B3“.")
                    }
                }

                Section {
                    Stepper(value: $rows, in: Rack.rowRange) {
                        LabeledContent("Ebenen", value: "\(rows)")
                    }
                    Stepper(value: $columns, in: Rack.columnRange) {
                        LabeledContent("Fächer je Ebene", value: "\(columns)")
                    }
                } header: {
                    Text("Grösse")
                } footer: {
                    Text("Ergibt \(rows * columns) Fächer. Ein Fach nimmt eine Flasche auf.")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        RackGridView(
                            rows: rows,
                            columns: columns,
                            occupancy: rack.occupancy(),
                            tile: columns > 10 ? 26 : 34
                        )
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Vorschau")
                }

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Regal löschen", systemImage: "trash")
                        }
                    } footer: {
                        Text(rack.usedCount == 0
                             ? "Das Regal ist leer und wird einfach entfernt."
                             : "\(rack.usedCount) Flaschen werden aus dem Regal genommen. Der Bestand im Keller bleibt unverändert.")
                    }
                }

                if !losingSlots.isEmpty {
                    Section {
                        Label {
                            Text("\(losingSlots.count) Flaschen liegen ausserhalb des neuen Rasters und werden aus dem Regal genommen. Der Bestand bleibt unverändert.")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Regal bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = rack.name
                rows = rack.rowCount
                columns = rack.columnCount
            }
            .confirmationDialog("Regal löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("„\(rack.name)“ wird entfernt, auch auf den anderen Geräten. Die Flaschen bleiben im Keller, sie sind danach nur nicht mehr verortet.")
            }
        }
    }

    /// Löscht das Regal samt seiner Fächer. Der Bestand am Wein bleibt – die Flaschen
    /// gelten danach nur als nicht verortet.
    private func delete() {
        context.delete(rack)
        context.saveChanges()
        onDelete()
        dismiss()
    }

    private func save() {
        for slot in losingSlots {
            context.delete(slot)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rack.name = trimmed.isEmpty ? tr("Regal") : trimmed
        rack.rows = Int64(rows)
        rack.columns = Int64(columns)
        context.saveChanges()
        dismiss()
    }
}
