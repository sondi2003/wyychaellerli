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

    /// Für das Symbol in der Toolbar: Ist gerade irgendein Filter aktiv?
    var isFiltering: Bool { showArchived || showOnlyDrinkSoon || strengthFilter != nil }

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
        return "\(bottles) \(bottles == 1 ? "Flasche" : "Flaschen") · \(active.count) \(active.count == 1 ? "Wein" : "Weine")"
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
