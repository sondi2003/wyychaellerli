import SwiftUI
import UIKit

// MARK: - Markenfarben

/// Das Erscheinungsbild der App: tiefes Weinrot, Rosé als Rahmen- und Akzentton,
/// Grün nur für die Hauptaktion. Angelehnt an Vivino, aber nicht deckungsgleich.
/// Jede feste Farbe steht hier und hat eine Dunkelvariante (siehe `Color.adaptive`).
enum Brand {
    /// Akzent der ganzen App (Knöpfe, gewählte Reiter, Chips). Wird an der Wurzel als `tint` gesetzt,
    /// weil der Katalogeintrag `AccentColor` im Simulator nicht griff und die App blau blieb.
    static let accent = Color.adaptive(light: (0.60, 0.09, 0.20), dark: (0.94, 0.47, 0.52))
    /// Starke Flächen.
    static let burgundy = Color.adaptive(light: (0.45, 0.07, 0.14), dark: (0.30, 0.05, 0.10))
    /// Dunkelster Ton des Verlaufs.
    static let deep = Color(red: 0.17, green: 0.02, blue: 0.05)
    /// Rosé für Rahmen, Hervorhebungen und gewählte Symbole.
    static let rose = Color(red: 0.94, green: 0.47, blue: 0.52)
    /// Text auf Akzentflächen: weiss auf Weinrot, im Dunkelmodus dunkel auf Rosé
    /// (weiss auf Rosé wäre zu schwach).
    static let onAccent = Color.adaptive(light: (1, 1, 1), dark: (0.17, 0.02, 0.05))
    /// Zarter Grund hinter Etiketten, wie der helle Bühnenhintergrund der Vorlage.
    static let blush = Color.adaptive(light: (0.98, 0.94, 0.95), dark: (0.19, 0.10, 0.12))
    /// Hauptaktion (Trinken, Übernehmen).
    static let action = Color.adaptive(light: (0.00, 0.50, 0.36), dark: (0.15, 0.68, 0.50))

    /// Verlauf wie auf den Startseiten: oben fast schwarz-rot, unten Rosé.
    static let gradient = LinearGradient(
        colors: [deep, Color(red: 0.33, green: 0.04, blue: 0.10), Color(red: 0.62, green: 0.16, blue: 0.27), rose],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Für Flächen mit weisser Schrift: bleibt durchgehend dunkel genug.
    static let heroGradient = LinearGradient(
        colors: [deep, Color(red: 0.36, green: 0.05, blue: 0.12), Color(red: 0.58, green: 0.13, blue: 0.24)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Navigationsleisten einmal beim Start einrichten.
    @MainActor
    static func applyAppearance() {
        // Die Tableiste bleibt dem System überlassen: Seit iOS 26 schwebt sie als Glas und
        // ignoriert eigene Hintergründe; der gewählte Reiter nimmt die Akzentfarbe an.

        // Titel in der Schrift der Marke: fett, ohne Serifen.
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .heavy)]
        nav.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}

// MARK: - Farben pro Weintyp

extension WineType {
    /// Charakterfarbe für Badges, Icons und Akzente.
    ///
    /// Zwei Fassungen je Typ: Die hellen Töne sind für weissen Grund gewählt und wirken
    /// auf dunklem Grund matt bis unlesbar – Bordeaux besonders. Deshalb im Dunkelmodus
    /// jeweils die aufgehellte Variante.
    var color: Color {
        switch self {
        case .red:       return .adaptive(light: (0.48, 0.11, 0.20), dark: (0.80, 0.34, 0.42))   // Bordeaux
        case .white:     return .adaptive(light: (0.80, 0.66, 0.24), dark: (0.92, 0.80, 0.38))   // Strohgelb
        case .sparkling: return .adaptive(light: (0.33, 0.58, 0.64), dark: (0.48, 0.76, 0.83))   // kühles Petrol
        case .rose:      return .adaptive(light: (0.89, 0.45, 0.56), dark: (0.95, 0.58, 0.68))   // Rosé
        case .mulled:    return .adaptive(light: (0.78, 0.36, 0.13), dark: (0.92, 0.53, 0.25))   // Zimt-Orange
        }
    }
}

extension Color {
    /// Farbe, die dem Hell-/Dunkelmodus folgt.
    static func adaptive(
        light: (red: CGFloat, green: CGFloat, blue: CGFloat),
        dark: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let tone = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: tone.red, green: tone.green, blue: tone.blue, alpha: 1)
        })
    }
}

// MARK: - Etikett-Bild

extension Wine {
    /// Dekodiertes Etikett-Foto, falls eines gespeichert ist.
    var labelImage: UIImage? {
        labelImageData.flatMap(UIImage.init(data:))
    }

    /// Dekodiertes Rückseiten-Etikett, falls eines gespeichert ist.
    var backLabelImage: UIImage? {
        backLabelImageData.flatMap(UIImage.init(data:))
    }
}

/// Kleines Vorschaubild für Listen und Cards; fällt auf das Typ-Icon zurück.
struct LabelThumbnail: View {
    let wine: Wine
    var size: CGFloat = 44

    var body: some View {
        if let image = wine.labelImage {
            AdaptiveLabelImage(image: image, width: size, height: size * 1.25)
        } else {
            WineTypeIcon(type: wine.type, size: size)
        }
    }
}

extension View {

    /// Legt den Namen der App („Wyychällerli“, Weinrot, im Dunkeln Rosé) unten über ein
    /// **Flaschenfoto** – dorthin, wo das Wasserzeichen war und der Verlauf ausblendet
    /// (`CatalogPhotoFade`). Etikettfotos bleiben unberührt. Eine Ebene über dem Bild, nicht
    /// im Bild: Das gespeicherte Foto und alles, was geteilt wird, bleiben frei von Beschriftung.
    @ViewBuilder
    func bottleSignature(for image: UIImage) -> some View {
        if CatalogPhotoFade.isBottle(width: Int(image.size.width), height: Int(image.size.height)) {
            overlay(alignment: .bottom) {
                Text(verbatim: "Wyychällerli")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            self
        }
    }
}

/// Ein Foto in einem kleinen Rahmen – **Etikett füllt, Flasche steht ganz da**.
///
/// Ein Etikettfoto (annähernd quadratisch bis hoch) füllt den Rahmen und wird beschnitten.
/// Ein Flaschenfoto aus dem Katalog ist schmal und hoch (Seitenverhältnis unter 0,55): Würde es
/// gefüllt, bliebe vom Hals nur ein Ausschnitt in der Mitte. Es wird deshalb ganz gezeigt, in
/// einem doppelt so hohen Rahmen, damit die Flasche nicht zum Strich schrumpft.
struct AdaptiveLabelImage: View {
    let image: UIImage
    let width: CGFloat
    let height: CGFloat

    /// Schmaler als das gilt als Flasche.
    static let bottleAspectLimit: CGFloat = 0.55

    private var isBottle: Bool {
        image.size.height > 0 && image.size.width / image.size.height < Self.bottleAspectLimit
    }

    var body: some View {
        if isBottle {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height * 1.7)
                .accessibilityHidden(true)
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Wiederverwendbare Bausteine

/// Rundes Icon mit Typfarbe – in Listen, Cards und Detailansichten.
struct WineTypeIcon: View {
    let type: WineType
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(type.color.opacity(0.15))
            Image(systemName: type.symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(type.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Bestandsanzeige: "3" in einer Kapsel, bei 0 rot "Leer".
struct StockBadge: View {
    let quantity: Int

    var body: some View {
        Group {
            if quantity > 0 {
                Text("\(quantity)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            } else {
                Text("Leer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(quantity > 0 ? Color(.tertiarySystemFill) : Color.red)
        )
        // Eine Zahl, die sich zusammendrücken lässt, verschwindet in der Kapsel.
        // In einer Zeile mit langem Namen gewinnt sonst der Text den Platz.
        .fixedSize()
        .accessibilityLabel(quantity > 0 ? Text("\(quantity) Flaschen") : Text("Keine Flaschen"))
    }
}

/// Hinweisbox (Info, Warnung, Fehler) mit Icon.
struct CalloutBox: View {
    enum Kind {
        case info, warning, error

        var color: Color {
            switch self {
            case .info:    return .accentColor
            case .warning: return .orange
            case .error:   return .red
            }
        }

        var symbol: String {
            switch self {
            case .info:    return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.octagon.fill"
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Karten-Hintergrund für Cards ausserhalb von Listen.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Brand.deep.opacity(0.08), radius: 8, y: 2)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

// MARK: - Bausteine im Markenstil

/// Filter-Kapsel: gewählt schwarz gefüllt (im Dunkelmodus weiss), sonst nur umrandet.
struct PillChip: View {
    let title: String
    var symbol: String? = nil
    /// Farbe des Symbols im nicht gewählten Zustand, z. B. die Weinart.
    var symbolColor: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : (symbolColor ?? .primary))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary)
                } else {
                    Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Öffnet das Filterblatt. Weinrot umrandet, damit er sich von den Weinart-Chips abhebt;
/// sind Filter eingeschaltet, steht ihre Zahl daneben.
struct FilterButtonChip: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.caption.weight(.bold))
                Text("Filter")
                    .font(.subheadline.weight(.semibold))
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.onAccent)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(Brand.accent))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(Brand.accent)
            .background(Capsule().strokeBorder(Brand.accent, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? tr("Filter, \(count) aktiv") : tr("Filter"))
    }
}

/// Ein eingeschalteter Filter als rosa Chip; ein Tipp nimmt ihn wieder heraus.
struct RemovableChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(Brand.accent)
            .background(Capsule().fill(Brand.blush))
            .overlay(Capsule().strokeBorder(Brand.accent.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("\(title) entfernen"))
    }
}

/// Kapsel-Knöpfe der Marke: gefüllt (Weinrot), Hauptaktion (Grün) oder umrandet.
struct BrandButtonStyle: ButtonStyle {
    /// `destructive` ist rot umrandet, nicht gefüllt: neben einem gefüllten Hauptknopf
    /// soll der heikle Schritt nicht gleich laut sein.
    enum Kind { case filled, action, outline, destructive }

    var kind: Kind = .filled
    /// Volle Breite und grössere Schrift für den einen Hauptknopf einer Seite.
    var isLarge = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isLarge ? .headline : .subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, isLarge ? 20 : 14)
            .padding(.vertical, isLarge ? 14 : 8)
            .frame(maxWidth: isLarge ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if kind == .outline {
                    Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                } else if kind == .destructive {
                    Capsule().strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .filled:  return Brand.onAccent
        case .action:  return .white
        case .outline: return .primary
        case .destructive: return .red
        }
    }

    private var background: Color {
        switch kind {
        case .filled:  return Brand.accent
        case .action:  return Brand.action
        case .outline, .destructive: return .clear
        }
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brandFilled: BrandButtonStyle { BrandButtonStyle(kind: .filled) }
    static var brandAction: BrandButtonStyle { BrandButtonStyle(kind: .action) }
    static var brandOutline: BrandButtonStyle { BrandButtonStyle(kind: .outline) }
    static func brand(_ kind: BrandButtonStyle.Kind, large: Bool = false) -> BrandButtonStyle {
        BrandButtonStyle(kind: kind, isLarge: large)
    }
}

/// Dunkle Kopfkarte mit Verlauf und Rosé-Rand – der Auftritt der Vorlage im Kleinen.
struct BrandHero: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var symbol: String = "wineglass"

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white.opacity(0.9), Brand.rose)
                .accessibilityHidden(true)
        }
        .padding(20)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Brand.rose.opacity(0.7), lineWidth: 1.5)
        )
    }
}
