import SwiftUI
import UIKit

/// Einen Wein weiterempfehlen: Etikett, Angaben und ein eigener Satz dazu.
///
/// Ein Sheet für beide Empfänger. Wer die App nicht hat, bekommt Bild und Text und
/// kann damit alles anfangen; wer sie hat, übernimmt den Wein aus der angehängten
/// Datei mit einem Tipp.
struct WineShareSheet: View {

    @ObservedObject var wine: Wine

    @Environment(\.dismiss) private var dismiss
    @Environment(CurrentRater.self) private var rater

    @State private var comment = ""
    @State private var includesData = true
    @State private var isPresentingShare = false
    @FocusState private var isCommentFocused: Bool

    /// Häufige Anlässe – spart Tippen und trifft meistens.
    private let suggestions = [
        "Den kann ich empfehlen.",
        "Gerade im Angebot.",
        "Gibt's bei Coop.",
        "Gibt's bei Denner.",
        "Der passt gut zum Essen."
    ]

    private var share: WineShare {
        WineShare(wine: wine, comment: comment, senderName: rater.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text("Vorschau")
                }

                Section {
                    TextField("z. B. gibt's bei Denner für 12.90", text: $comment, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isCommentFocused)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    comment = suggestion
                                    isCommentFocused = false
                                }
                                .font(.footnote)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Dein Hinweis")
                } footer: {
                    Text("Steht in der Nachricht unter den Angaben – etwa wo es den Wein gibt oder was er gerade kostet.")
                }

                Section {
                    Toggle("Weindaten anhängen", isOn: $includesData)
                } footer: {
                    Text(includesData
                         ? "Hängt eine kleine Datei an. Wer Wyychällerli hat, tippt sie an und hat den Wein mit allen Angaben und Etiketten im eigenen Keller. Alle anderen sehen einfach Bild und Text."
                         : "Es werden nur Etikett und Text verschickt.")
                }
            }
            .navigationTitle("Wein empfehlen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Teilen") { isPresentingShare = true }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isPresentingShare) {
                ShareActivityView(items: shareItems()) { completed in
                    isPresentingShare = false
                    if completed { dismiss() }
                }
            }
        }
    }

    // MARK: Vorschau

    private var preview: some View {
        HStack(alignment: .top, spacing: 14) {
            if let image = wine.labelImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                WineTypeIcon(type: wine.type, size: 56)
            }
            Text(share.messageText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Bild, Text und – auf Wunsch – die Datei. Was das Ziel davon nimmt, entscheidet es
    /// selbst: Nachrichten zeigt alles, Mail hängt die Datei an, die Zwischenablage
    /// nimmt den Text.
    private func shareItems() -> [Any] {
        var items: [Any] = [share.messageText]
        if let image = wine.labelImage {
            items.append(image)
        }
        if includesData, let url = try? share.writeToTemporaryFile() {
            items.append(url)
        }
        return items
    }
}

/// Apples Teilen-Fenster. `ShareLink` kann nur gleichartige Dinge; hier sind es Text,
/// Bild und Datei zugleich.
struct ShareActivityView: UIViewControllerRepresentable {

    let items: [Any]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
