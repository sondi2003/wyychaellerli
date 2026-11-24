import SwiftUI

/// „Der Katalog in Zahlen“: grosse Zahl oben, darunter ein Raster mit einer gleich grossen
/// Kachel je Land. Kleine Länder gehen nicht in einem Sammelstreifen unter; wie gross ein Land
/// im Verhältnis ist, zeigt der schmale Balken unter der Weinzahl (Chile = voll).
struct CatalogCountryGrid: View {

    let overview: CatalogOverview
    /// Die gewählte Kachel: Sie bleibt kräftig, die anderen treten zurück.
    var selectedID: String?
    /// Tipp auf eine Kachel; ohne Angabe bleibt das Raster reine Anzeige (Vorschau).
    var onSelect: ((CatalogSelection) -> Void)?

    /// Weinrot der Kacheln, fest und nicht an den Hell- und Dunkelmodus gebunden: Fläche und
    /// weisse Schrift sind zusammen entworfen (Kontrast über 12 : 1).
    private static let tileColor = Color(red: 0.42, green: 0.08, blue: 0.17)

    /// Mindestanteil des Balkens, damit auch das kleinste Land einen sichtbaren Strich hat.
    private static let minimumBar = 0.04

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 140), spacing: 8)]

    var body: some View {
        VStack(spacing: 12) {
            hero
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(overview.countries) { country in
                    tile(country)
                        .id(country.id)
                }
            }
            .animation(.smooth(duration: 0.5), value: overview.countries.map(\.id))
        }
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Der Katalog in Zahlen")
                .font(.footnote)
                .foregroundStyle(Brand.rose)
            Text("\(overview.total) Weine")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("aus \(overview.countries.count) Ländern")
                .font(.subheadline)
                .foregroundStyle(Brand.rose)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tile(_ country: CatalogOverview.Country) -> some View {
        let chosen = selectedID == country.id
        let dimmed = selectedID != nil && !chosen
        let share = max(Self.minimumBar, Double(country.count) / Double(max(1, overview.countries.first?.count ?? 1)))
        return Button {
            onSelect?(CatalogSelection(country: country))
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: country.flag ?? String(country.name.prefix(2)))
                    .font(.system(size: 28))
                Text(verbatim: country.name)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Feste Höhe: Ein langer Name wird kleiner gesetzt, die Kachel soll deshalb nicht niedriger werden.
                    .frame(height: 16)
                Text(verbatim: "\(country.count)")
                    .font(.headline)
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { bar in
                            Capsule().fill(.white).frame(width: bar.size.width * share)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(Self.tileColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Brand.rose, lineWidth: chosen ? 2 : 0)
            }
            .opacity(dimmed ? 0.45 : 1)
            .animation(.default, value: selectedID)
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(country.name), \(tr("\(country.count) Weine"))"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

#Preview {
    let entries: [(String, Int)] = [
        ("Chile", 193), ("Italien", 110), ("Argentinien", 97), ("USA", 96), ("Neuseeland", 96),
        ("Frankreich", 8), ("Schweiz", 8), ("Deutschland", 4), ("Portugal", 3), ("Spanien", 3),
        ("Südafrika", 2), ("Nordmazedonien", 1)
    ]
    let wines = entries.flatMap { country, count in
        (0..<count).map { index in
            CatalogWine(id: "\(country)\(index)", name: "Wein \(index)", producer: "", vintage: 2020, grape: "",
                        region: "", country: country, typeRaw: "red", alcoholPercent: 0, source: "")
        }
    }
    return CatalogCountryGrid(overview: CatalogOverview(entries: wines, locale: Locale(identifier: "de")))
        .padding()
}
