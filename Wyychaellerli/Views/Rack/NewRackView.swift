import SwiftUI

/// Ein weiteres Regal anlegen – Name und Grösse.
///
/// Der Name trägt bei mehreren Regalen die ganze Last: Er steht später an jedem Fach
/// („Küche · B3“). Deshalb Vorschläge statt eines leeren Felds.
struct NewRackView: View {

    let onCreate: (String, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var rows = 1
    @State private var columns = 12
    @FocusState private var isNameFocused: Bool

    private let suggestions = [tr("Keller"), tr("Küche"), tr("Garage"), tr("Vorrat"), tr("Schrank")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    name = suggestion
                                    isNameFocused = false
                                }
                                .font(.subheadline)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Name")
                } footer: {
                    Text("Der Name steht später an jedem Fach – „Küche · B3“. Wähle etwas, das den Ort beschreibt.")
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
                    Text("Ergibt \(rows * columns) Fächer. Lässt sich später jederzeit ändern.")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        RackGridView(
                            rows: rows,
                            columns: columns,
                            occupancy: [:],
                            tile: columns > 10 ? 26 : 34
                        )
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Vorschau")
                }
            }
            .navigationTitle("Neues Regal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        onCreate(name, rows, columns)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}
