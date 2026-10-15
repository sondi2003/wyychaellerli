import SwiftUI

/// Fünf Sterne in halben Schritten.
///
/// Halbe Schritte, weil bei zwei Personen der Mittelwert sonst in groben Sprüngen
/// steht: Zehn Stufen unterscheiden „ganz gut“ von „richtig gut“, ohne eine Genauigkeit
/// vorzutäuschen, die beim Trinken niemand hat. Feiner als halbe Sterne wäre Unsinn.
struct StarRatingView: View {

    /// 0 = nicht bewertet, sonst 0,5 bis 5,0.
    @Binding var value: Double
    /// Nur anzeigen, nicht verändern.
    var isEditable = true
    var size: CGFloat = 30

    private let starCount = 5
    private var spacing: CGFloat { size * 0.12 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...starCount, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .font(.system(size: size))
                    .foregroundStyle(value > 0 ? Color.yellow : Color.secondary.opacity(0.35))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .contentShape(Rectangle())
        .modifier(StarInputModifier(value: $value, isEditable: isEditable, starCount: starCount, size: size, spacing: spacing))
        .animation(.snappy(duration: 0.15), value: value)
        .accessibilityElement()
        .accessibilityLabel("Bewertung")
        .accessibilityValue(value > 0 ? tr("\(value.formatted(.number.precision(.fractionLength(0...1)))) von 5") : tr("keine"))
        .accessibilityAdjustableAction { direction in
            guard isEditable else { return }
            switch direction {
            case .increment: value = min(5, value + 0.5)
            case .decrement: value = max(0, value - 0.5)
            @unknown default: break
            }
        }
    }

    private func symbol(for index: Int) -> String {
        let filled = Double(index)
        if value >= filled { return "star.fill" }
        if value >= filled - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Wandelt Tippen und Ziehen in halbe Sterne um.
///
/// Als eigener Modifier, damit die Breite eines Sterns aus derselben Rechnung stammt
/// wie die Darstellung – sonst trifft man neben dem sichtbaren Stern.
private struct StarInputModifier: ViewModifier {

    @Binding var value: Double
    let isEditable: Bool
    let starCount: Int
    let size: CGFloat
    let spacing: CGFloat

    func body(content: Content) -> some View {
        if isEditable {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let step = size + spacing
                        let raw = (gesture.location.x + spacing / 2) / step
                        // Auf halbe Sterne runden und in 0,5 … 5,0 halten.
                        let halved = (raw * 2).rounded(.up) / 2
                        value = min(Double(starCount), max(0.5, halved))
                    }
            )
        } else {
            content
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        StarRatingView(value: .constant(3.5))
        StarRatingView(value: .constant(5))
        StarRatingView(value: .constant(0))
        StarRatingView(value: .constant(4), isEditable: false, size: 16)
    }
    .padding()
}
