import CoreData
import Foundation

/// Eine Flasche an einem bestimmten Platz im Regal.
///
/// Es gibt **nur belegte** Plätze. Ein freies Fach ist schlicht eines, für das kein
/// `Slot` existiert. Das hält ein grosses Regal billig und macht das Ändern von Zeilen
/// und Spalten unkompliziert.
///
/// Ein Wein mit drei Flaschen kann null bis drei Plätze haben: Verorten ist freiwillig.
/// Die Stückzahl am Wein bleibt massgebend, sonst müssten Minus-Knopf, Wein-Berater und
/// Doppelerkennung alle umgebaut werden.
@objc(SlotEntity)
final class Slot: NSManagedObject, Identifiable {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Slot> {
        NSFetchRequest<Slot>(entityName: "Slot")
    }

    @NSManaged var uuid: UUID?
    @NSManaged var row: Int64
    @NSManaged var column: Int64
    @NSManaged var placedAt: Date?
    @NSManaged var rack: Rack?
    @NSManaged var wine: Wine?

    var id: NSManagedObjectID { objectID }

    var position: Position { Position(row: Int(row), column: Int(column)) }

    /// „B3“, und bei mehreren Regalen „Küche · B3“.
    ///
    /// Mit nur einem Regal wäre der Name überall nur Wiederholung; mit zweien ist „B3“
    /// allein mehrdeutig und schickt einen an den falschen Ort.
    var displayLabel: String {
        guard let rack, (rack.cellar?.rackCount ?? 1) > 1 else { return position.label }
        return "\(rack.name) · \(position.label)"
    }

    /// Stellt eine Flasche ins Fach.
    @discardableResult
    static func place(
        _ wine: Wine,
        at position: Position,
        in rack: Rack,
        context: NSManagedObjectContext
    ) -> Slot {
        let slot = Slot(context: context)
        if let store = rack.objectID.persistentStore {
            context.assign(slot, to: store)
        }
        slot.uuid = UUID()
        slot.row = Int64(position.row)
        slot.column = Int64(position.column)
        slot.rack = rack
        slot.wine = wine
        slot.placedAt = .now
        context.saveChanges()
        return slot
    }
}

// MARK: - Umräumen

extension Rack {

    enum MoveResult: Equatable {
        /// Die Flasche liegt jetzt im freien Zielfach.
        case moved
        /// Das Zielfach war belegt, beide Flaschen haben die Plätze getauscht.
        case swapped
        /// Nichts geändert: dasselbe Fach, ausserhalb des Rasters oder kein Fach am Start.
        case unchanged
    }

    /// Verschiebt die Flasche aus `source` nach `target`, innerhalb dieses Regals.
    ///
    /// Ein belegtes Ziel **tauscht** die beiden Flaschen, statt eine zu verdrängen: Beim
    /// Umräumen soll nie eine Flasche aus dem Regal fallen. Der Bestand am Wein ändert sich
    /// nie, es wandern nur Positionen.
    @discardableResult
    func moveSlot(from source: Position, to target: Position, context: NSManagedObjectContext) -> MoveResult {
        guard source != target,
              target.row >= 0, target.row < rowCount,
              target.column >= 0, target.column < columnCount,
              let moving = occupancy()[source] else { return .unchanged }

        let other = occupancy()[target]
        moving.row = Int64(target.row)
        moving.column = Int64(target.column)
        if let other {
            other.row = Int64(source.row)
            other.column = Int64(source.column)
        }
        context.saveChanges()
        return other == nil ? .moved : .swapped
    }
}

// MARK: - Verortung am Wein

extension Wine {

    /// Plätze dieses Weins, von oben links nach unten rechts.
    var placedSlots: [Slot] {
        ((slots as? Set<Slot>) ?? [])
            .filter { $0.rack != nil }
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    /// Wie viele Flaschen im Regal verortet sind.
    var placedCount: Int { placedSlots.count }

    /// Flaschen, die es laut Bestand gibt, aber ohne Platz im Regal.
    var unplacedCount: Int { max(0, Int(quantity) - placedCount) }

    /// `true`, solange noch eine Flasche eingeräumt werden kann.
    /// Mehr Plätze als Flaschen darf es nie geben.
    var canPlaceAnotherBottle: Bool { unplacedCount > 0 }

    /// Wo die Flaschen liegen: „Küche · B3, Keller · A1“. Leer, wenn nicht verortet.
    var storageSummary: String {
        placedSlots.map(\.displayLabel).joined(separator: ", ")
    }
}
