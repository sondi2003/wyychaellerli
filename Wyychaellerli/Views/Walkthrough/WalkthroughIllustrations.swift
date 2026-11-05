import SwiftUI

// Gezeichnete Bilder für die Einführung. Alle aus einfachen Formen und SF Symbols,
// damit sie in jeder Grösse und in Hell wie Dunkel sauber bleiben.

// MARK: - Bausteine

/// Eine Textzeile, angedeutet als graue Kapsel.
private struct TextLine: View {
    var width: CGFloat
    var height: CGFloat = 8
    var tone: Color = .secondary.opacity(0.28)

    var body: some View {
        Capsule().fill(tone).frame(width: width, height: height)
    }
}

/// Ein Fach im Regal, wie es das echte Raster zeichnet.
private struct Cell: View {
    var color: Color? = nil
    var highlighted = false
    var selected = false
    var size: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            shape.fill(selected ? Color.accentColor : fill)
            shape.strokeBorder(border, lineWidth: highlighted || selected ? 2 : 1)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            } else if let color {
                BottleIcon(color: highlighted ? Color.accentColor : color)
                    .frame(width: size * 0.34, height: size * 0.72)
            }
        }
        .frame(width: size, height: size)
    }

    private var fill: Color {
        guard let color else { return highlighted ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill) }
        return color.opacity(highlighted ? 0.3 : 0.16)
    }

    private var border: Color {
        if highlighted { return .accentColor }
        return color.map { $0.opacity(0.4) } ?? Color.secondary.opacity(0.25)
    }
}

/// Eine Fingerspitze, die auf etwas zeigt.
private struct Finger: View {
    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 30))
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

// MARK: - Willkommen: drei Flaschen auf einem Brett

struct WelcomeIllustration: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 22) {
                BottleIcon(color: WineType.red.color).frame(width: 34, height: 96)
                BottleIcon(color: WineType.white.color).frame(width: 34, height: 104)
                BottleIcon(color: WineType.rose.color).frame(width: 34, height: 92)
                BottleIcon(color: WineType.sparkling.color).frame(width: 34, height: 100)
            }
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 250, height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(.top, 2)
        }
    }
}

// MARK: - Scannen: Flasche mit Sucher, daneben das ausgefüllte Formular

struct ScanIllustration: View {
    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                BottleShape()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 62, height: 170)
                // Etikett auf dem Bauch
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemBackground))
                    .frame(width: 44, height: 46)
                    .overlay(
                        VStack(spacing: 5) {
                            TextLine(width: 26, height: 5)
                            TextLine(width: 30, height: 5)
                            TextLine(width: 20, height: 5)
                        }
                    )
                    .offset(y: 32)
                // Sucher-Ecken um das Etikett
                ViewfinderCorners()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 66, height: 68)
                    .offset(y: 32)
            }
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    TextLine(width: 60, height: 9, tone: .primary.opacity(0.7))
                }
                TextLine(width: 44)
                TextLine(width: 70)
                TextLine(width: 52)
                HStack(spacing: 5) {
                    Text("🇨🇭").font(.caption)
                    TextLine(width: 38)
                }
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Vier Ecken eines Suchers, wie bei der Kamera.
private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let l: CGFloat = 12
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

// MARK: - Bestand: eine Zeile der Kellerliste mit Minus

struct StockIllustration: View {
    var body: some View {
        VStack(spacing: 14) {
            row(color: WineType.red.color, count: 3, active: true)
            row(color: WineType.white.color, count: 1, active: false)
                .opacity(0.55)
        }
        .padding(.horizontal, 24)
    }

    private func row(color: Color, count: Int, active: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 40, height: 50)
                .overlay(BottleIcon(color: color).frame(width: 16, height: 34))
            VStack(alignment: .leading, spacing: 7) {
                TextLine(width: 96, height: 9, tone: .primary.opacity(0.7))
                HStack(spacing: 5) {
                    Text("🇮🇹").font(.caption2)
                    TextLine(width: 70, height: 7)
                }
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: Capsule())
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                if active {
                    Finger().offset(x: 14, y: 22)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Regal: Raster mit Flaschen, Wisch-Auswahl und pulsierendem Fach

struct RackIllustration: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let red = WineType.red.color
    private let white = WineType.white.color
    private let rose = WineType.rose.color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Cell(color: red); Cell(); Cell(color: white); Cell(); Cell(); Cell(color: red)
            }
            HStack(spacing: 5) {
                Cell(); Cell(selected: true); Cell(selected: true); Cell(selected: true); Cell(); Cell(color: rose)
            }
            HStack(spacing: 5) {
                Cell(color: white); Cell(); Cell(color: red, highlighted: true)
                    .scaleEffect(pulse && !reduceMotion ? 1.1 : 1)
                    .shadow(color: Color.accentColor.opacity(pulse ? 0.55 : 0.3), radius: 7)
                Cell(); Cell(color: red); Cell()
            }
        }
        .overlay(alignment: .topLeading) {
            // Der Finger wischt über die drei ausgewählten Fächer.
            Finger().offset(x: 118, y: 52)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Berater: vom Teller zur Flasche

struct AdvisorIllustration: View {
    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().fill(Color(.systemBackground)).frame(width: 96, height: 96)
                Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 2).frame(width: 96, height: 96)
                Circle().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1.5).frame(width: 64, height: 64)
                Image(systemName: "fork.knife")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 10) {
                    BottleIcon(color: WineType.red.color).frame(width: 26, height: 74)
                    BottleIcon(color: WineType.white.color).frame(width: 22, height: 62).opacity(0.6)
                }
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < 4 ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text("passt sehr gut")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Katalog: Eingabe „Brio“, darunter der Vorschlag mit seinen Jahrgängen

struct CatalogIllustration: View {

    @Environment(CatalogCenter.self) private var catalog
    /// Der Rahmen ist 220 pt hoch; bei sehr grosser Schrift bliebe für die Zeile kein Platz.
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Erst ab `CatalogOverview.minimumForDisplay` Weinen: Eine Zeile „12 Weine aus 3 Ländern“
    /// würde den Katalog kleiner machen, als er wirken soll.
    @State private var overview: CatalogOverview?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(verbatim: "Brio").font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 220)
            .background(Color(.tertiarySystemFill), in: Capsule())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Con Brio").font(.subheadline.weight(.semibold))
                        TextLine(width: 90)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(["2020", "2019", "2018"], id: \.self) { year in
                        Text(verbatim: year)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(year == "2019" ? Color(.systemBackground) : Color.primary)
                            .background {
                                if year == "2019" { Capsule().fill(Color.accentColor) }
                                else { Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1) }
                            }
                    }
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))

            if let overview, overview.isWorthShowing, !typeSize.isAccessibilitySize {
                HStack(spacing: 6) {
                    Image(systemName: "globe.europe.africa")
                    Text("\(overview.total) Weine")
                    Text(verbatim: "·")
                    Text("\(overview.countries.count) Länder")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .task(id: catalog.directory.count) {
            let entries = catalog.directory.entries
            let locale = AppLanguage.current.locale
            overview = await Task.detached { CatalogOverview(entries: entries, locale: locale) }.value
        }
    }
}

// MARK: - Teilen: zwei Geräte, dazwischen die Wolke

struct ShareIllustration: View {
    var body: some View {
        HStack(spacing: 18) {
            phone(name: "person.fill")
            VStack(spacing: 6) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            phone(name: "person.2.fill")
        }
    }

    private func phone(name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: name)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                HStack(spacing: 4) { Cell(color: WineType.red.color, size: 18); Cell(size: 18); Cell(color: WineType.white.color, size: 18) }
                HStack(spacing: 4) { Cell(size: 18); Cell(color: WineType.rose.color, size: 18); Cell(size: 18) }
                HStack(spacing: 4) { Cell(color: WineType.red.color, size: 18); Cell(color: WineType.red.color, size: 18); Cell(size: 18) }
            }
        }
        .frame(width: 92, height: 150)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 2)
        )
    }
}

#Preview("Bilder") {
    ScrollView {
        VStack(spacing: 20) {
            WelcomeIllustration()
            ScanIllustration()
            CatalogIllustration()
            StockIllustration()
            RackIllustration()
            AdvisorIllustration()
            ShareIllustration()
        }
        .padding()
    }
}
