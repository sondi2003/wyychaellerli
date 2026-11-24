import Charts
import CoreData
import SwiftUI

/// Das Blatt „Statistik“: zuerst der eigene Keller, daneben der gemeinsame Katalog.
///
/// Früher zeigte der Statistik-Knopf im Keller nur den Katalog – wer zwölf Flaschen hatte,
/// las dort „Der Katalog wächst“ und nichts über den eigenen Bestand.
struct StatisticsView: View {

    enum Scope: Hashable { case cellar, catalog }

    /// Schliesst das Blatt und schaltet in der Kellerliste den Filter „Bald trinken“ ein.
    var onShowDrinkSoon: () -> Void = {}

    @State private var scope: Scope = .cellar

    var body: some View {
        // Beide Ansichten bringen ihren eigenen Navigationsstapel mit; der Umschalter
        // wandert als Kopf in die jeweils gezeigte.
        switch scope {
        case .cellar:
            CellarStatisticsView(header: AnyView(scopePicker), onShowDrinkSoon: onShowDrinkSoon)
        case .catalog:
            CatalogStatisticsView(header: AnyView(scopePicker))
        }
    }

    private var scopePicker: some View {
        Picker("Statistik", selection: $scope) {
            Text("Mein Keller").tag(Scope.cellar)
            Text("Katalog").tag(Scope.catalog)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Der eigene Keller in Zahlen (`CellarStatistics`): Kennzahlen, Weinarten, Trinkreife,
/// Länder, Jahrgänge. Abschnitte ohne Daten fehlen, statt Nullen zu zeigen.
struct CellarStatisticsView: View {

    var header: AnyView? = nil
    var onShowDrinkSoon: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)])
    private var wines: FetchedResults<Wine>

    var body: some View {
        let statistics = CellarStatistics(wines: Array(wines), locale: language.locale)
        NavigationStack {
            VStack(spacing: 0) {
                if let header { header }
                if statistics.isEmpty {
                    EmptyState(title: "Der Keller ist leer", symbol: "wineglass",
                               message: "Lege deine erste Flasche an, damit der Wein-Berater etwas empfehlen kann.")
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            keyFigures(statistics)
                            typesCard(statistics)
                            if statistics.hasMaturity { maturityCard(statistics) }
                            if !statistics.countries.isEmpty { countriesCard(statistics) }
                            if statistics.vintages.count > 1 { vintagesCard(statistics) }
                        }
                        .padding([.horizontal, .bottom])
                        .padding(.top, 4)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .appTitle(tr("Statistik"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    // MARK: Kennzahlen

    private func keyFigures(_ statistics: CellarStatistics) -> some View {
        // Ohne Bewertung drei Kacheln in einer Reihe – zu zweit bliebe unten rechts ein Loch.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                            count: statistics.averageRating == nil ? 3 : 2)
        return LazyVGrid(columns: columns, spacing: 10) {
            figure(String(statistics.bottles), "Flaschen")
            figure(String(statistics.wineCount), "Weine")
            figure(String(statistics.countries.count), "Länder")
            if let rating = statistics.averageRating {
                figure(rating.formatted(.number.precision(.fractionLength(1))), "Bewertung im Schnitt")
            }
        }
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Weinarten

    private func typesCard(_ statistics: CellarStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weinarten").font(.headline)
            // Ein gestapelter Balken in den Farben der Weinarten.
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let usable = proxy.size.width - gap * CGFloat(max(statistics.types.count - 1, 0))
                HStack(spacing: gap) {
                    ForEach(statistics.types) { share in
                        Rectangle()
                            .fill(share.type.color)
                            .frame(width: max(4, usable * CGFloat(share.bottles) / CGFloat(statistics.bottles)))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .accessibilityHidden(true)

            FlowLayout(spacing: 14) {
                ForEach(statistics.types) { share in
                    HStack(spacing: 5) {
                        Image(systemName: share.type.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(share.type.color)
                        Text(verbatim: "\(share.type.displayName) \(share.bottles)")
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Trinkreife

    private func maturityCard(_ statistics: CellarStatistics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trinkreife").font(.headline)
            if statistics.drinkSoon > 0 {
                HStack(spacing: 10) {
                    Image(systemName: Wine.Maturity.drinkSoon.symbolName)
                        .foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Bald trinken").font(.subheadline.weight(.semibold))
                        Text(verbatim: tr("\(statistics.drinkSoon) Flaschen"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Zeigen") {
                        onShowDrinkSoon()
                        dismiss()
                    }
                    .buttonStyle(.brandOutline)
                }
                .padding(12)
                .background(Brand.warning.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
            }
            let rows: [(title: String, bottles: Int, color: Color)] = [
                (Wine.Maturity.ready.title, statistics.ready, Brand.success),
                (tr("Noch lagern"), statistics.tooYoung, Color(.systemGray)),
                (tr("Ohne Angabe"), statistics.withoutWindow, Color(.systemGray3))
            ]
            ForEach(rows.filter { $0.bottles > 0 }, id: \.title) { row in
                shareRow(title: row.title, bottles: row.bottles, of: statistics.bottles, color: row.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Länder

    private func countriesCard(_ statistics: CellarStatistics) -> some View {
        let top = statistics.countries.prefix(6)
        let most = top.first?.bottles ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("Länder").font(.headline)
            ForEach(top) { country in
                shareRow(title: [country.flag, country.name].compactMap { $0 }.joined(separator: " "),
                         bottles: country.bottles, of: most, color: Brand.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Beschriftung, Balken, Zahl – der Balken zeigt den Anteil an `total`.
    private func shareRow(title: String, bottles: Int, of total: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 118, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(color)
                        .frame(width: max(6, proxy.size.width * CGFloat(bottles) / CGFloat(max(total, 1))))
                }
            }
            .frame(height: 8)
            Text(verbatim: String(bottles))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title + ", " + tr("\(bottles) Flaschen")))
    }

    // MARK: Jahrgänge

    private func vintagesCard(_ statistics: CellarStatistics) -> some View {
        // Höchstens fünf Jahre beschriften, sonst stossen die Zahlen aneinander.
        let years = statistics.vintages.map(\.year)
        let step = max(1, Int((Double(years.count) / 5).rounded(.up)))
        let labelled = years.enumerated().filter { $0.offset % step == 0 }.map { String($0.element) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Jahrgänge").font(.headline)
            Chart(statistics.vintages) { share in
                BarMark(
                    x: .value(tr("Jahrgang"), String(share.year)),
                    y: .value(tr("Flaschen"), share.bottles)
                )
                .foregroundStyle(Brand.accent)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: labelled) { _ in
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    StatisticsView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(CatalogCenter())
}
