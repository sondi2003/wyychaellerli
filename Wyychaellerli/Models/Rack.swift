import CoreData
import Foundation

/// Ein Weinregal als Raster aus Zeilen und Spalten.
///
/// Ein Fach ist genau eine Flasche tief. Regale mit mehreren Flaschen hintereinander
/// gäbe es zwar, dafür bräuchte es eine dritte Achse – das Raster ist bewusst so
/// aufgebaut, dass sich das später ergänzen liesse, ohne die Zuordnung zu verlieren.
///
/// Mehrere Regale sind vorgesehen, auch wenn hier zunächst nur eines gebraucht wird.
@objc(RackEntity)
final class Rack: NSManagedObject, Identifiable {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Rack> {
        NSFetchRequest<Rack>(entityName: "Rack")
    }

    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    @NSManaged var rows: Int64
    @NSManaged var columns: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var cellar: Cellar?
    /// Nur die **belegten** Fächer. Freie Fächer haben kein Objekt.
    @NSManaged var slots: NSSet?

    var id: NSManagedObjectID { objectID }

    /// Sinnvolle Grenzen für die Einrichtung. Grösser wird auf dem Bildschirm unlesbar.
    static let rowRange = 1...12
    static let columnRange = 1...20

    /// Mehr Regale werden im Umschalter unübersichtlich, und niemand hat sie im Kopf.
    static let maximumCount = 4

    var rowCount: Int { max(1, Int(rows)) }
    var columnCount: Int { max(1, Int(columns)) }
    var capacity: Int { rowCount * columnCount }

    var placedSlots: [Slot] {
        ((slots as? Set<Slot>) ?? []).filter { $0.wine != nil }
    }

    var usedCount: Int { placedSlots.count }
    var freeCount: Int { max(0, capacity - usedCount) }

    /// Belegung als Nachschlagewerk, damit die Ansicht nicht je Fach suchen muss.
    func occupancy() -> [Position: Slot] {
        Dictionary(placedSlots.map { (Position(row: Int($0.row), column: Int($0.column)), $0) }) { first, _ in first }
    }

    /// Erstes freies Fach, zeilenweise von oben links – für „einfach irgendwo hin“.
    func firstFreePosition() -> Position? {
        let taken = Set(placedSlots.map { Position(row: Int($0.row), column: Int($0.column)) })
        for row in 0..<rowCount {
            for column in 0..<columnCount where !taken.contains(Position(row: row, column: column)) {
                return Position(row: row, column: column)
            }
        }
        return nil
    }

    /// Fächer, die durch Verkleinern ausserhalb des Rasters liegen würden.
    func slotsOutsideGrid(rows newRows: Int, columns newColumns: Int) -> [Slot] {
        placedSlots.filter { Int($0.row) >= newRows || Int($0.column) >= newColumns }
    }

    /// Die Regale **dieses** Kellers aus einer bereits geholten Liste, ältestes zuerst.
    ///
    /// Wichtig auf dem Gerät des Gasts: Dort können ein leerer eigener Keller und der
    /// geteilte nebeneinander liegen. Ohne diese Zuordnung erschienen Regale, die gar
    /// nicht zum angezeigten Bestand gehören.
    static func inCurrentCellar(from racks: [Rack], in context: NSManagedObjectContext) -> [Rack] {
        guard let cellar = Cellar.current(in: context) else { return racks }
        let mine = racks.filter { $0.cellar == cellar }
        return mine.isEmpty ? racks.filter { $0.cellar == nil } : mine
    }

    /// Das Regal **dieses** Kellers aus einer bereits geholten Liste.
    static func preferred(from racks: [Rack], in context: NSManagedObjectContext) -> Rack? {
        inCurrentCellar(from: racks, in: context).first
    }

    /// Alle Regale dieses Kellers, ältestes zuerst.
    static func all(in context: NSManagedObjectContext, for cellar: Cellar) -> [Rack] {
        all(in: context).filter { $0.cellar == cellar }
    }

    /// Regale desselben Kellers, die **denselben Namen** tragen.
    ///
    /// Seit es mehrere Regale geben darf, ist „zwei Regale“ kein Fehler mehr. Der echte
    /// Doppelanlage-Fall – zwei Geräte legen gleichzeitig eines an, bevor das erste über
    /// iCloud eintrifft – erkennt man daran, dass beide gleich heissen.
    static func duplicatesByName(in context: NSManagedObjectContext, for cellar: Cellar) -> [[Rack]] {
        Dictionary(grouping: all(in: context, for: cellar), by: \.name)
            .values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
    }

    /// Führt gleichnamige Regale desselben Kellers zusammen.
    ///
    /// Behalten wird das **älteste** je Name; die Fächer der übrigen wandern hinüber.
    /// Ist ein Fach dort schon belegt, wird die Flasche nur aus dem Regal genommen –
    /// der Bestand bleibt in jedem Fall unangetastet.
    ///
    /// Waren die Regale unterschiedlich gross, wächst das behaltene so weit mit, dass jedes
    /// übernommene Fach im Raster liegt. Ohne das läge eine Flasche zwar als verortet in der
    /// Datenbank, wäre aber in keinem Fach zu sehen.
    @discardableResult
    static func mergeDuplicates(in context: NSManagedObjectContext, for cellar: Cellar) -> (moved: Int, released: Int) {
        var moved = 0
        var released = 0

        for group in duplicatesByName(in: context, for: cellar) {
            guard let keeper = group.first else { continue }
            var taken = Set(keeper.placedSlots.map(\.position))
            var neededRows = keeper.rowCount
            var neededColumns = keeper.columnCount

            for extra in group.dropFirst() {
                for slot in extra.placedSlots {
                    let position = slot.position
                    let fits = position.row < rowRange.upperBound && position.column < columnRange.upperBound
                    if taken.contains(position) || !fits {
                        context.delete(slot)
                        released += 1
                    } else {
                        slot.rack = keeper
                        taken.insert(position)
                        neededRows = max(neededRows, position.row + 1)
                        neededColumns = max(neededColumns, position.column + 1)
                        moved += 1
                    }
                }
                context.delete(extra)
            }
            keeper.rows = Int64(neededRows)
            keeper.columns = Int64(neededColumns)
        }

        context.saveChanges()
        return (moved, released)
    }

    /// Ein weiteres Regal anlegen – bis zur Höchstzahl.
    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        cellar: Cellar,
        name: String,
        rows: Int = 1,
        columns: Int = 12
    ) -> Rack? {
        guard all(in: context, for: cellar).count < maximumCount else { return nil }
        let rack = Rack(context: context)
        // Muss in denselben Speicher wie der Keller, sonst sieht die andere Seite es nie.
        if let store = cellar.objectID.persistentStore {
            context.assign(rack, to: store)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rack.uuid = UUID()
        rack.cellar = cellar
        rack.name = trimmed.isEmpty ? tr("Regal") : trimmed
        rack.rows = Int64(rows)
        rack.columns = Int64(columns)
        rack.createdAt = .now
        context.saveChanges()
        return rack
    }

    /// Das Regal des Kellers, angelegt falls noch keines da ist.
    @discardableResult
    static func findOrCreate(in context: NSManagedObjectContext, cellar: Cellar) -> Rack {
        // Am Keller festgemacht, damit der Gast nicht ein zweites Regal anlegt, während
        // das des Eigentümers noch unterwegs ist.
        if let existing = all(in: context).first(where: { $0.cellar == cellar }) { return existing }
        let rack = Rack(context: context)
        // Muss in denselben Speicher wie der Keller, sonst sieht die andere Seite es nie.
        if let store = cellar.objectID.persistentStore {
            context.assign(rack, to: store)
        }
        rack.uuid = UUID()
        rack.cellar = cellar
        rack.name = "Regal"
        rack.rows = 1
        rack.columns = 12
        rack.createdAt = .now
        context.saveChanges()
        return rack
    }

    static func all(in context: NSManagedObjectContext) -> [Rack] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
}

/// Ein Fach im Raster. Zeile und Spalte zählen ab 0.
struct Position: Hashable {
    let row: Int
    let column: Int

    /// Für Menschen: Zeile als Buchstabe, Spalte als Zahl ab 1 – „B3“.
    var label: String {
        let letter = String(UnicodeScalar(UInt8(65 + min(row, 25))))
        return "\(letter)\(column + 1)"
    }
}
