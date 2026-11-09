import Foundation

/// Die Felder des eigenen Weins, die sich mit dem Katalog vergleichen und übernehmen lassen.
/// Notizen, Bewertungen, Bestand, Regalplatz, Strichcode und Trinkfenster gehören dem Nutzer
/// und kommen hier nie vor. Der Jahrgang auch nicht: Er ist Teil des Schlüssels, über den der
/// Eintrag gefunden wurde.
enum CatalogField: CaseIterable, Identifiable, Sendable {
    case name, producer, grape, region, country, type, alcohol, food

    var id: Self { self }

    var title: String {
        switch self {
        case .name: tr("Name")
        case .producer: tr("Produzent")
        case .grape: tr("Rebsorte")
        case .region: tr("Region")
        case .country: tr("Land")
        case .type: tr("Weinart")
        case .alcohol: tr("Alkohol")
        case .food: tr("Passt zu")
        }
    }
}

/// Die Angaben aus dem Formular eines Weins, die der Katalog kennt.
struct WineDetails: Equatable, Sendable {
    var name = ""
    var producer = ""
    var grape = ""
    var region = ""
    var country = ""
    var type: WineType = .red
    var alcoholPercent = 0.0
    /// Kommaliste, wie im Formular.
    var foodPairings = ""
}

/// Eine Zeile der Gegenüberstellung: was der Nutzer hat, was der Katalog hat.
struct CatalogDifference: Equatable, Identifiable, Sendable {
    /// `fillable`: der Nutzer hat nichts, der Katalog schon – eine Ergänzung.
    /// `different`: beide haben etwas, aber Verschiedenes.
    enum Kind: Equatable, Sendable { case fillable, different }

    let field: CatalogField
    let mine: String
    let catalog: String
    let kind: Kind
    var id: CatalogField { field }
}

enum CatalogComparison {

    /// Was der Katalog anders oder zusätzlich weiss. Gleiches und Leeres im Katalog erscheint
    /// nicht: Der Katalog löscht nie etwas, und Schreibweisen, die sich nur durch Gross- und
    /// Kleinschreibung oder Akzente unterscheiden, gelten als gleich.
    static func differences(entry: CatalogWine, mine: WineDetails) -> [CatalogDifference] {
        var result: [CatalogDifference] = []
        func text(_ field: CatalogField, _ own: String, _ theirs: String) {
            let own = own.trimmingCharacters(in: .whitespacesAndNewlines)
            let theirs = theirs.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !theirs.isEmpty else { return }
            if own.isEmpty {
                result.append(CatalogDifference(field: field, mine: own, catalog: theirs, kind: .fillable))
            } else if DuplicateFinder.normalized(own) != DuplicateFinder.normalized(theirs) {
                result.append(CatalogDifference(field: field, mine: own, catalog: theirs, kind: .different))
            }
        }
        text(.name, mine.name, entry.name)
        text(.producer, mine.producer, entry.producer)
        text(.grape, mine.grape, entry.grape)
        text(.region, mine.region, entry.region)
        text(.country, mine.country, entry.country)

        if let type = entry.wineType, type != mine.type {
            result.append(CatalogDifference(
                field: .type, mine: mine.type.displayName, catalog: type.displayName, kind: .different))
        }
        if entry.alcoholPercent > 0 {
            let theirs = Self.alcoholText(entry.alcoholPercent)
            if mine.alcoholPercent <= 0 {
                result.append(CatalogDifference(field: .alcohol, mine: "", catalog: theirs, kind: .fillable))
            } else if abs(mine.alcoholPercent - entry.alcoholPercent) > 0.05 {
                result.append(CatalogDifference(
                    field: .alcohol, mine: Self.alcoholText(mine.alcoholPercent), catalog: theirs, kind: .different))
            }
        }
        if !entry.foodPairings.isEmpty {
            let own = pairings(mine.foodPairings)
            let theirs = entry.foodPairings.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if own.isEmpty {
                result.append(CatalogDifference(
                    field: .food, mine: "", catalog: theirs.joined(separator: ", "), kind: .fillable))
            } else if Set(own.map(DuplicateFinder.normalized)) != Set(theirs.map(DuplicateFinder.normalized)) {
                result.append(CatalogDifference(
                    field: .food, mine: own.joined(separator: ", "), catalog: theirs.joined(separator: ", "),
                    kind: .different))
            }
        }
        return result
    }

    /// Übernimmt ein Feld aus dem Katalog in die Angaben.
    static func apply(_ field: CatalogField, from entry: CatalogWine, to details: inout WineDetails) {
        switch field {
        case .name: details.name = entry.name
        case .producer: details.producer = entry.producer
        case .grape: details.grape = entry.grape
        case .region: details.region = entry.region
        case .country: details.country = entry.country
        case .type: if let type = entry.wineType { details.type = type }
        case .alcohol: details.alcoholPercent = entry.alcoholPercent
        case .food: details.foodPairings = entry.foodPairings.joined(separator: ", ")
        }
    }

    private static func pairings(_ text: String) -> [String] {
        text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func alcoholText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + " %"
    }
}

extension CatalogWine {

    /// Ein Fingerabdruck der Angaben, die der Nutzer übernehmen kann. Ändert der Admin etwas
    /// daran, ändert er sich – daran erkennt ein Wein, ob es seit seinem letzten Blick
    /// etwas Neues gibt (`Wine.catalogSeen`). Bewusst ohne Foto: Das Verzeichnis auf dem Gerät
    /// kennt nur Text.
    var fingerprint: String {
        let parts: [String] = [
            name, producer, grape, region, country, typeRaw,
            String(Int((alcoholPercent * 10).rounded())), foodPairings.joined(separator: ",")
        ]
        return parts.map(DuplicateFinder.normalized).joined(separator: "|")
    }
}
