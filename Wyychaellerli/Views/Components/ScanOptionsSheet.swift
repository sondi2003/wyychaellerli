import SwiftUI

/// Die Auswahl hinter langem Drücken auf den Scan-Knopf: drei Wege zum neuen Wein.
///
/// Ein niedriges Blatt statt eines Menüs am Knopf – warum, steht bei `ScanButton`.
struct ScanOptionsSheet: View {

    enum Option { case camera, photos, manual }

    let onChoose: (Option) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wein hinzufügen")
                .font(.headline)
                .padding(.bottom, 8)
            row(.camera, title: "Etikett fotografieren", symbol: "camera")
            row(.photos, title: "Aus Fotos", symbol: "photo")
            row(.manual, title: "Ohne Foto erfassen", symbol: "square.and.pencil")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func row(_ option: Option, title: LocalizedStringKey, symbol: String) -> some View {
        Button {
            onChoose(option)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 28)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Text(verbatim: "Keller")
        .sheet(isPresented: .constant(true)) {
            ScanOptionsSheet { _ in }
        }
}
