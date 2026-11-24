import SwiftUI

/// Momentaufnahme eines Weins für die Siri-Karte. Bewusst ein einfacher Wert,
/// damit kein SwiftData-Objekt in die Snippet-Darstellung wandert.
struct WineSnapshot: Sendable, Equatable {
    let name: String
    let producer: String
    let subtitle: String
    let fitName: String
    let fitSymbol: String
    let typeColorName: String
    let typeSymbol: String
    let imageData: Data?

    init(wine: Wine, fit: FitLevel?) {
        name = wine.name
        producer = wine.producer
        subtitle = wine.subtitle
        fitName = fit?.displayName ?? ""
        fitSymbol = fit?.symbolName ?? ""
        typeColorName = wine.type.rawValue
        typeSymbol = wine.type.symbolName
        imageData = wine.labelImageData
    }
}

/// Karte, die Siri unter der gesprochenen Antwort einblendet.
/// Deckt Empfehlung, ehrliche Absage und Hinweise (kein Key, leerer Keller) ab.
struct PairingSnippetView: View {

    let headline: String
    let message: String
    let wine: WineSnapshot?
    let shoppingTip: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let wine {
                HStack(spacing: 12) {
                    labelImage(for: wine)
                    VStack(alignment: .leading, spacing: 2) {
                        if !wine.producer.isEmpty {
                            Text(wine.producer)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(wine.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(wine.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if !wine.fitName.isEmpty {
                        Label(wine.fitName, systemImage: wine.fitSymbol)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            } else {
                Label(headline, systemImage: "wineglass")
                    .font(.headline)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !shoppingTip.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cart")
                        .foregroundStyle(.secondary)
                    Text(shoppingTip)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func labelImage(for wine: WineSnapshot) -> some View {
        if let data = wine.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.small, style: .continuous))
        } else {
            Image(systemName: wine.typeSymbol)
                .font(.title2)
                .frame(width: 48, height: 60)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Brand.Radius.small, style: .continuous))
        }
    }
}
