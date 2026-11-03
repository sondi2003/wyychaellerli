import SwiftUI

/// Filter der Kellerliste: Trinkreife, Alkoholgehalt und Archiv.
///
/// Früher lagen sie im Menü oben links, zusammen mit Regal, Bewertungen und Party –
/// Filter, Wege und Aktionen durcheinander. Jetzt hat jedes seinen Ort: die Filter hier,
/// sichtbar gemacht als Chips in der Reihe über der Liste. Die Weinart bleibt in der Reihe,
/// sie ist der häufigste Filter und braucht keinen Umweg.
struct CellarFilterSheet: View {

    @Bindable var viewModel: CellarViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    chipRow {
                        PillChip(title: tr("Alle"), isSelected: !viewModel.showOnlyDrinkSoon) {
                            viewModel.showOnlyDrinkSoon = false
                        }
                        PillChip(
                            title: tr("Bald trinken"),
                            symbol: "clock.badge.exclamationmark",
                            isSelected: viewModel.showOnlyDrinkSoon
                        ) {
                            viewModel.showOnlyDrinkSoon = true
                        }
                    }
                } header: {
                    Text("Trinkreife")
                } footer: {
                    Text("Flaschen, deren Trinkfenster dieses Jahr endet oder schon vorbei ist.")
                }

                Section {
                    chipRow {
                        PillChip(title: tr("Alle"), isSelected: viewModel.strengthFilter == nil) {
                            viewModel.strengthFilter = nil
                        }
                        ForEach(Wine.Strength.allCases) { strength in
                            PillChip(
                                title: strength.title,
                                symbol: strength.symbolName,
                                isSelected: viewModel.strengthFilter == strength
                            ) {
                                viewModel.strengthFilter = strength
                            }
                        }
                    }
                } header: {
                    Text("Alkoholgehalt")
                } footer: {
                    Text(verbatim: Wine.Strength.allCases.map { "\($0.title) \($0.range)" }.joined(separator: " · "))
                }

                Section {
                    Toggle("Archiv anzeigen", isOn: $viewModel.showArchived)
                } footer: {
                    Text("Statt des Bestands erscheinen die archivierten Weine.")
                }

                Section {
                    Button {
                        viewModel.resetFilters()
                    } label: {
                        Text("Filter zurücksetzen")
                    }
                    .buttonStyle(.brand(.outline, large: true))
                    .disabled(!viewModel.isFiltering)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        // Fester Grund: Halbhohe Blätter sind unter iOS 26 aus Glas, die Liste dahinter
        // schien durch, und der gewählte Chip wirkte ausgegraut. Halbe Höhe reichte auf
        // dem iPhone SE nicht bis zu „Archiv“ und „Zurücksetzen“.
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    /// Chips nebeneinander; bricht auf schmalen Geräten um, statt seitlich zu scrollen.
    private func chipRow(@ViewBuilder content: () -> some View) -> some View {
        FlowLayout(spacing: 8) {
            content()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text(verbatim: "Keller")
        .sheet(isPresented: .constant(true)) {
            CellarFilterSheet(viewModel: CellarViewModel())
        }
}
