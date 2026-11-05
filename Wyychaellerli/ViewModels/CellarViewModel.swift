import CoreData
import Foundation
import Observation

/// UI-Zustand und Aktionen für den Tab „Wyychällerli“ (die Bestandsliste).
///
/// Die Weine selbst kommen per `@FetchRequest` in die View; dieses ViewModel kümmert
/// sich um Filter, Suche, Sheets und die Bestandsaktionen.
@Observable
@MainActor
final class CellarViewModel {

    // MARK: Filter & Suche

    /// `nil` = alle Typen.
    var typeFilter: WineType?
    var searchText = ""
    var showArchived = false
    /// Zeigt nur Flaschen, deren Trinkfenster dieses Jahr endet oder schon vorbei ist.
    var showOnlyDrinkSoon = false
    /// `nil` = alle Stärken. Flaschen ohne Angabe fallen bei gesetztem Filter heraus –
    /// „leicht“ zu behaupten, wo nichts bekannt ist, wäre geraten.
    var strengthFilter: Wine.Strength?
    /// Schlüssel des gewählten Landes (`Wine.countryKey`), `nil` = alle Länder. Weine ohne
    /// Landesangabe fallen bei gesetztem Filter heraus.
    var countryFilter: String?

    /// Ist im Filterblatt etwas eingeschaltet? Die Weinart zählt nicht dazu, die steht
    /// ohnehin sichtbar in der Chip-Reihe.
    var isFiltering: Bool { activeFilterCount > 0 }

    /// Für die Zahl am Filter-Chip.
    var activeFilterCount: Int {
        [showArchived, showOnlyDrinkSoon, strengthFilter != nil, countryFilter != nil].filter { $0 }.count
    }

    /// „Filter zurücksetzen“ im Filterblatt. Die Weinart bleibt, wie sie ist.
    func resetFilters() {
        showArchived = false
        showOnlyDrinkSoon = false
        strengthFilter = nil
        countryFilter = nil
    }

    /// Ein Land im Filterblatt: Schlüssel, Name, Flagge und Zahl der Weine.
    struct CountryOption: Identifiable, Equatable {
        let key: String
        let name: String
        let flag: String?
        let count: Int
        var id: String { key }
        var label: String { [flag, name].compactMap { $0 }.joined(separator: " ") }
    }

    /// Die Länder der Weine, die gerade in der Liste stehen (Bestand oder Archiv), mit ihrer
    /// Weinzahl, alphabetisch. „Schweiz“, „Suisse“ und „Switzerland“ zählen als ein Land.
    func countryOptions(in wines: [Wine]) -> [CountryOption] {
        let visible = wines.filter { $0.isArchived == showArchived }
        let groups = Dictionary(grouping: visible.filter { !$0.country.isEmpty }, by: \.countryKey)
        return groups
            .map { key, wines in
                let raw = wines.first?.country ?? key
                return CountryOption(
                    key: key,
                    name: CountryFlag.displayName(for: raw, locale: AppLanguage.current.locale) ?? raw,
                    flag: CountryFlag.emoji(for: raw),
                    count: wines.count
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Sheet- und Dialog-Zustand

    /// Wie ein neuer Wein angelegt wird – manuell oder per Etikett-Scan.
    enum AddMode: String, Identifiable {
        case manual, scan
        var id: String { rawValue }
    }

    var addMode: AddMode?
    var wineToEdit: Wine?

    /// Wird gesetzt, wenn durch „Flasche trinken“ die letzte Flasche abgebucht wurde.
    var justEmptiedWine: Wine?

    /// Wein, für den das Fach zu wählen ist, weil alle Flaschen verortet sind.
    var wineToTakeFromRack: Wine?

    /// Trigger für haptisches Feedback beim Abbuchen.
    var consumeCount = 0

    // MARK: Abgeleitete Daten

    /// Wendet Archiv-, Typ- und Suchfilter auf die Ergebnisse an.
    func filtered(_ wines: [Wine]) -> [Wine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return wines.filter { wine in
            guard wine.isArchived == showArchived else { return false }
            if showOnlyDrinkSoon, !wine.needsDrinkingSoon { return false }
            if let typeFilter, wine.type != typeFilter { return false }
            if let strengthFilter, wine.strength != strengthFilter { return false }
            if let countryFilter, wine.countryKey != countryFilter { return false }
            guard !query.isEmpty else { return true }
            return wine.name.lowercased().contains(query)
                || wine.producer.lowercased().contains(query)
                || wine.grape.lowercased().contains(query)
                || wine.region.lowercased().contains(query)
                || String(wine.vintage).contains(query)
        }
    }

    /// Gruppiert nach Typ in der Reihenfolge von `WineType.allCases`.
    func grouped(_ wines: [Wine]) -> [(type: WineType, wines: [Wine])] {
        WineType.allCases.compactMap { type in
            let matching = wines
                .filter { $0.type == type }
                .sorted { ($0.name, $0.vintage) < ($1.name, $1.vintage) }
            return matching.isEmpty ? nil : (type, matching)
        }
    }

    /// "12 Flaschen · 7 Weine" für die Kopfzeile.
    func summary(for wines: [Wine]) -> String {
        let active = wines.filter { !$0.isArchived }
        let bottles = active.reduce(0) { $0 + Int($1.quantity) }
        return tr("\(bottles) Flaschen") + " · " + tr("\(active.count) Weine")
    }

    // MARK: Bestandsaktionen

    func consume(_ wine: Wine) {
        guard wine.quantity > 0 else { return }
        // Liegen alle Flaschen im Regal, wird das Fach gewählt statt blind abgebucht.
        guard !(wine.placedCount > 0 && wine.unplacedCount == 0) else {
            wineToTakeFromRack = wine
            return
        }
        wine.consumeBottle()
        consumeCount += 1
        if wine.isOutOfStock {
            justEmptiedWine = wine
        }
    }

    func addBottle(_ wine: Wine) {
        wine.addBottle()
    }

    func archive(_ wine: Wine) {
        wine.isArchived = true
        wine.managedObjectContext?.saveChanges()
    }

    func unarchive(_ wine: Wine) {
        wine.isArchived = false
        wine.managedObjectContext?.saveChanges()
    }

    func delete(_ wine: Wine, in context: NSManagedObjectContext) {
        context.delete(wine)
        context.saveChanges()
    }
}
