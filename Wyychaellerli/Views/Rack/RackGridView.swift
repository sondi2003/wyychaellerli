import SwiftUI
import UniformTypeIdentifiers

/// Das Regal als Raster.
///
/// Bewusst ein eigener, dummer Baustein ohne Datenzugriff: Dieselbe Darstellung wird
/// später auf der Detailseite eines Weins gebraucht, dort aber nur mit hervorgehobenen
/// Plätzen und ohne Bedienung.
struct RackGridView: View {

    let rows: Int
    let columns: Int
    /// Was in welchem Fach liegt. Fehlt ein Eintrag, ist das Fach frei.
    let occupancy: [Position: Slot]
    /// Diese Plätze werden hervorgehoben und pulsieren.
    var highlighted: Set<Position> = []
    /// Diese Plätze sind ausgewählt (Mehrfachauswahl beim Einräumen).
    var selected: Set<Position> = []
    /// Kantenlänge eines Fachs.
    var tile: CGFloat = 44
    /// Enger, wenn das ganze Regal auf die Breite passen soll.
    var spacing: CGFloat = 6
    var onTap: ((Position) -> Void)?
    /// Wird beim Wischen über ein Fach gemeldet. Nur gesetzt, wenn Wischen erlaubt ist.
    var onDragOver: ((Position) -> Void)?
    /// Umräumen per Ziehen: von Fach, nach Fach. Nur gesetzt, wo Umräumen erlaubt ist.
    var onMove: ((Position, Position) -> Void)?
    /// Kennung des Regals. Ein Zug gilt nur im Regal, in dem er begonnen hat – sonst
    /// würde ein Fach „B3“ aus einem anderen Fenster oder Regal das hiesige „B3“ greifen.
    var dragScope: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<max(rows, 1), id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<max(columns, 1), id: \.self) { column in
                        cell(at: Position(row: row, column: column))
                    }
                }
            }
        }
        // Wischen über mehrere Fächer. Die Rasterweite ist bekannt, deshalb lässt sich
        // die Position aus dem Berührungspunkt rechnen – zuverlässiger als Treffer je Feld.
        .gesture(dragSelection, isEnabled: onDragOver != nil)
        .onAppear {
            guard !reduceMotion, !highlighted.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var dragSelection: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let step = tile + spacing
                let column = Int(value.location.x / step)
                let row = Int(value.location.y / step)
                guard row >= 0, row < rows, column >= 0, column < columns else { return }
                onDragOver?(Position(row: row, column: column))
            }
    }

    @ViewBuilder
    private func cell(at position: Position) -> some View {
        let slot = occupancy[position]
        let isHighlighted = highlighted.contains(position)
        let isSelected = selected.contains(position)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        cellButton(at: position, slot: slot, isHighlighted: isHighlighted, isSelected: isSelected, shape: shape)
            .modifier(MoveModifier(
                position: position,
                bottleColor: slot?.wine?.type.color,
                tile: tile,
                scope: dragScope,
                onMove: onMove
            ))
    }

    private func cellButton(
        at position: Position,
        slot: Slot?,
        isHighlighted: Bool,
        isSelected: Bool,
        shape: RoundedRectangle
    ) -> some View {
        Button {
            onTap?(position)
        } label: {
            ZStack {
                shape.fill(isSelected ? Color.accentColor : fill(for: slot, highlighted: isHighlighted))
                shape.strokeBorder(
                    isSelected ? Color.accentColor : border(for: slot, highlighted: isHighlighted),
                    lineWidth: isHighlighted || isSelected ? 2 : 1
                )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: tile * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                } else if let slot, let wine = slot.wine {
                    BottleIcon(color: isHighlighted ? Color.accentColor : wine.type.color)
                        .frame(width: tile * 0.34, height: tile * 0.72)
                }
            }
            .frame(width: tile, height: tile)
            // Nur der hervorgehobene Platz pulsiert, und nur wenn Bewegung erlaubt ist.
            .scaleEffect(isHighlighted && pulse && !reduceMotion ? 1.09 : 1)
            .shadow(
                color: isHighlighted ? Color.accentColor.opacity(pulse && !reduceMotion ? 0.55 : 0.3) : .clear,
                radius: isHighlighted ? 7 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(label(for: position, slot: slot))
    }

    private func fill(for slot: Slot?, highlighted: Bool) -> Color {
        guard let wine = slot?.wine else {
            return highlighted ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill)
        }
        return wine.type.color.opacity(highlighted ? 0.3 : 0.16)
    }

    private func border(for slot: Slot?, highlighted: Bool) -> Color {
        if highlighted { return .accentColor }
        return slot?.wine == nil ? Color.secondary.opacity(0.25) : (slot?.wine?.type.color ?? .secondary).opacity(0.4)
    }

    private func label(for position: Position, slot: Slot?) -> String {
        if selected.contains(position) { return "Fach \(position.label), ausgewählt" }
        guard let wine = slot?.wine else { return "Fach \(position.label), frei" }
        return "Fach \(position.label), \(wine.name)"
    }
}

/// Was beim Ziehen eines Fachs mitgeht: wo die Flasche herkommt.
///
/// Als JSON, damit keine eigene Typkennung in `Info.plist` deklariert werden muss. Die
/// Regalkennung steht dabei, damit ein fremder Zug nicht versehentlich greift.
struct SlotDragItem: Codable, Transferable {
    let row: Int
    let column: Int
    let scope: UUID?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    var position: Position { Position(row: row, column: column) }
}

/// Macht ein belegtes Fach ziehbar und jedes Fach zum Ziel – aber nur, wo `onMove` gesetzt ist.
private struct MoveModifier: ViewModifier {
    let position: Position
    /// `nil` bei freiem Fach: Dort gibt es nichts zu ziehen, es ist nur Ziel.
    let bottleColor: Color?
    let tile: CGFloat
    let scope: UUID?
    let onMove: ((Position, Position) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onMove {
            if let bottleColor {
                content
                    .draggable(SlotDragItem(row: position.row, column: position.column, scope: scope)) {
                        BottleIcon(color: bottleColor)
                            .frame(width: tile * 0.34, height: tile * 0.72)
                            .padding(8)
                    }
                    .dropDestination(for: SlotDragItem.self) { items, _ in
                        drop(items, onMove: onMove)
                    }
            } else {
                content
                    .dropDestination(for: SlotDragItem.self) { items, _ in
                        drop(items, onMove: onMove)
                    }
            }
        } else {
            content
        }
    }

    private func drop(_ items: [SlotDragItem], onMove: (Position, Position) -> Void) -> Bool {
        guard let item = items.first, item.scope == scope else { return false }
        onMove(item.position, position)
        return true
    }
}

/// Eine liegende Weinflasche als Silhouette, in der Farbe der Weinart.
///
/// SF Symbols kennt keine Weinflasche (nur `waterbottle`, eine Sportflasche), deshalb
/// selbst gezeichnet. Als `Shape` skaliert sie verlustfrei auf jede Fachgrösse.
struct BottleIcon: View {
    let color: Color

    var body: some View {
        ZStack {
            BottleShape()
                .fill(color)
            // Etikett: ein heller Streifen auf dem Bauch, damit es als Flasche lesbar bleibt.
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: proxy.size.width * 0.08, style: .continuous)
                    .fill(.white.opacity(0.55))
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 0.24)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.66)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Aufrecht stehende Flasche: Hals oben, Schulter, Bauch, flacher Boden.
struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let neckW = w * 0.40
        let neckH = h * 0.30
        let shoulderH = h * 0.14
        let corner = w * 0.14
        let x0 = rect.minX
        let y0 = rect.minY

        var path = Path()
        // Hals mit abgerundeter Öffnung.
        path.move(to: CGPoint(x: x0 + (w - neckW) / 2, y: y0 + neckH))
        path.addLine(to: CGPoint(x: x0 + (w - neckW) / 2, y: y0 + corner))
        path.addQuadCurve(to: CGPoint(x: x0 + (w - neckW) / 2 + corner, y: y0),
                          control: CGPoint(x: x0 + (w - neckW) / 2, y: y0))
        path.addLine(to: CGPoint(x: x0 + (w + neckW) / 2 - corner, y: y0))
        path.addQuadCurve(to: CGPoint(x: x0 + (w + neckW) / 2, y: y0 + corner),
                          control: CGPoint(x: x0 + (w + neckW) / 2, y: y0))
        path.addLine(to: CGPoint(x: x0 + (w + neckW) / 2, y: y0 + neckH))
        // Schulter rechts, gerundet in den Bauch.
        path.addQuadCurve(to: CGPoint(x: x0 + w, y: y0 + neckH + shoulderH),
                          control: CGPoint(x: x0 + w, y: y0 + neckH))
        // Bauch rechts bis zum Boden.
        path.addLine(to: CGPoint(x: x0 + w, y: y0 + h - corner))
        path.addQuadCurve(to: CGPoint(x: x0 + w - corner, y: y0 + h),
                          control: CGPoint(x: x0 + w, y: y0 + h))
        path.addLine(to: CGPoint(x: x0 + corner, y: y0 + h))
        path.addQuadCurve(to: CGPoint(x: x0, y: y0 + h - corner),
                          control: CGPoint(x: x0, y: y0 + h))
        path.addLine(to: CGPoint(x: x0, y: y0 + neckH + shoulderH))
        // Schulter links zurück zum Hals.
        path.addQuadCurve(to: CGPoint(x: x0 + (w - neckW) / 2, y: y0 + neckH),
                          control: CGPoint(x: x0, y: y0 + neckH))
        path.closeSubpath()
        return path
    }
}

#Preview {
    RackGridView(rows: 3, columns: 6, occupancy: [:], highlighted: [Position(row: 1, column: 2)])
        .padding()
}
