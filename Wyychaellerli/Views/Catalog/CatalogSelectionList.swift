import SwiftUI

/// Das gewählte Land der Statistik: eine grosse Kachel oder eine Flagge im Streifen „weitere Länder“.
struct CatalogSelection: Hashable {
    let country: CatalogOverview.Country
    var id: String { country.id }
}

/// Die Weine der gewählten Kachel, unter dem Mosaik der Statistik im freien Platz.
///
/// Eine eigene Liste, die für sich scrollt: Das Mosaik oben bleibt stehen. Nur Anzeige und nur
/// Text, aus der Liste, die ohnehin auf dem Gerät liegt. Wer die Weine geliefert hat, steht wie
/// in der Statistik nirgends.
struct CatalogSelectionList: View {

    let selection: CatalogSelection
    let entries: [CatalogWine]

    var body: some View {
        List {
            Section {
                ForEach(CatalogOverview.wines(inCountry: selection.country.id, from: entries)) { wine in
                    row(wine)
                }
            } header: {
                HStack(spacing: 6) {
                    if let flag = selection.country.flag { Text(verbatim: flag) }
                    Text(verbatim: selection.country.name)
                    Spacer()
                    Text("\(selection.country.count) Weine")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Neue Wahl, neue Liste: oben beginnen statt dort, wo die vorige stand.
        .id(selection)
    }

    private func row(_ wine: CatalogWine) -> some View {
        let type = wine.wineType ?? .red
        return HStack(spacing: 12) {
            Image(systemName: type.symbolName)
                .foregroundStyle(type.color)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: wine.vintage > 0 ? "\(wine.name) \(String(wine.vintage))" : wine.name)
                let detail = [wine.producer, wine.grape, wine.region].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
