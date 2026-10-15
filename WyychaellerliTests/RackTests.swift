import Testing
@testable import Wyychaellerli

/// Regal und Fächer: Raster, Belegung, mehrere Regale, Zusammenführen.
@MainActor
struct RackTests {

    @Test("Fachbezeichnung für Menschen")
    func positionLabel() {
        #expect(Position(row: 0, column: 0).label == "A1")
        #expect(Position(row: 1, column: 2).label == "B3")
        #expect(Position(row: 3, column: 11).label == "D12")
    }

    @Test("Erstes freies Fach zeilenweise von oben links")
    func firstFree() throws {
        let context = TestStack.makeContext()
        let rack = Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
        rack.rows = 2
        rack.columns = 3

        #expect(rack.firstFreePosition() == Position(row: 0, column: 0))

        let wine = TestStack.makeWine(in: context, quantity: 3)
        Slot.place(wine, at: Position(row: 0, column: 0), in: rack, context: context)
        #expect(rack.firstFreePosition() == Position(row: 0, column: 1))

        Slot.place(wine, at: Position(row: 0, column: 1), in: rack, context: context)
        Slot.place(wine, at: Position(row: 0, column: 2), in: rack, context: context)
        #expect(rack.firstFreePosition() == Position(row: 1, column: 0))
    }

    @Test("Belegung, freie Fächer und Kapazität")
    func occupancy() {
        let context = TestStack.makeContext()
        let rack = Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
        rack.rows = 2
        rack.columns = 4
        let wine = TestStack.makeWine(in: context, quantity: 2)
        Slot.place(wine, at: Position(row: 1, column: 2), in: rack, context: context)

        #expect(rack.capacity == 8)
        #expect(rack.usedCount == 1)
        #expect(rack.freeCount == 7)
        #expect(rack.occupancy()[Position(row: 1, column: 2)]?.wine == wine)
        #expect(rack.occupancy()[Position(row: 0, column: 0)] == nil)
    }

    @Test("Verkleinern nennt die Fächer ausserhalb des Rasters")
    func outsideGrid() {
        let context = TestStack.makeContext()
        let rack = Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
        rack.rows = 3
        rack.columns = 4
        let wine = TestStack.makeWine(in: context, quantity: 2)
        Slot.place(wine, at: Position(row: 2, column: 3), in: rack, context: context)
        Slot.place(wine, at: Position(row: 0, column: 0), in: rack, context: context)

        // Beim Verkleinern auf 1×2 fällt nur das hintere Fach weg.
        #expect(rack.slotsOutsideGrid(rows: 1, columns: 2).count == 1)
        #expect(rack.slotsOutsideGrid(rows: 3, columns: 4).isEmpty)
    }

    @Test("Abbuchen räumt das zuletzt eingeräumte Fach mit")
    func consumeFreesSlot() {
        let context = TestStack.makeContext()
        let rack = Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
        let wine = TestStack.makeWine(in: context, quantity: 2)
        Slot.place(wine, at: Position(row: 0, column: 0), in: rack, context: context)
        Slot.place(wine, at: Position(row: 0, column: 1), in: rack, context: context)

        wine.consumeBottle()
        // Sonst zeigte das Regal eine Flasche, die es nicht mehr gibt.
        #expect(wine.quantity == 1)
        #expect(wine.placedCount == 1)
    }

    @Test("Umräumen: freies Fach verschiebt, belegtes tauscht, Bestand bleibt")
    func moveSlot() {
        let context = TestStack.makeContext()
        let rack = Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
        rack.rows = 2
        rack.columns = 3
        let red = TestStack.makeWine(in: context, name: "Rot", quantity: 1)
        let white = TestStack.makeWine(in: context, name: "Weiss", type: .white, quantity: 1)
        let a1 = Position(row: 0, column: 0)
        let a2 = Position(row: 0, column: 1)
        let b3 = Position(row: 1, column: 2)
        Slot.place(red, at: a1, in: rack, context: context)
        Slot.place(white, at: a2, in: rack, context: context)

        // Frei: die Flasche wandert, das alte Fach ist leer.
        #expect(rack.moveSlot(from: a1, to: b3, context: context) == .moved)
        #expect(rack.occupancy()[b3]?.wine == red)
        #expect(rack.occupancy()[a1] == nil)

        // Belegt: beide tauschen, keine fällt heraus.
        #expect(rack.moveSlot(from: b3, to: a2, context: context) == .swapped)
        #expect(rack.occupancy()[a2]?.wine == red)
        #expect(rack.occupancy()[b3]?.wine == white)
        #expect(rack.usedCount == 2)

        // Nichts zu tun: dasselbe Fach, leerer Start, Ziel ausserhalb des Rasters.
        #expect(rack.moveSlot(from: a2, to: a2, context: context) == .unchanged)
        #expect(rack.moveSlot(from: a1, to: b3, context: context) == .unchanged)
        #expect(rack.moveSlot(from: a2, to: Position(row: 5, column: 0), context: context) == .unchanged)

        #expect(red.quantity == 1)
        #expect(white.quantity == 1)
    }

    @Test("Bis zu vier Regale, dann ist Schluss")
    func maximumRacks() {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        Rack.findOrCreate(in: context, cellar: cellar)

        #expect(Rack.create(in: context, cellar: cellar, name: "Küche") != nil)
        #expect(Rack.create(in: context, cellar: cellar, name: "Garage") != nil)
        #expect(Rack.create(in: context, cellar: cellar, name: "Vorrat") != nil)
        // Das fünfte darf nicht mehr entstehen.
        #expect(Rack.create(in: context, cellar: cellar, name: "Zuviel") == nil)
        #expect(Rack.all(in: context, for: cellar).count == Rack.maximumCount)
    }

    @Test("Verschieden benannte Regale gelten nicht als Doppelanlage")
    func differentNamesAreNoDuplicates() {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        Rack.findOrCreate(in: context, cellar: cellar)
        Rack.create(in: context, cellar: cellar, name: "Küche")

        #expect(Rack.duplicatesByName(in: context, for: cellar).isEmpty)
    }

    @Test("Gleichnamige Regale werden zusammengeführt")
    func mergeSameName() {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        let first = Rack.findOrCreate(in: context, cellar: cellar)
        let second = Rack.create(in: context, cellar: cellar, name: first.name)!
        let wine = TestStack.makeWine(in: context, quantity: 2)

        Slot.place(wine, at: Position(row: 0, column: 0), in: first, context: context)
        Slot.place(wine, at: Position(row: 0, column: 5), in: second, context: context)
        #expect(Rack.duplicatesByName(in: context, for: cellar).count == 1)

        let result = Rack.mergeDuplicates(in: context, for: cellar)
        #expect(result.moved == 1)
        #expect(result.released == 0)
        #expect(Rack.all(in: context, for: cellar).count == 1)
        // Der Bestand darf sich beim Zusammenführen nie ändern.
        #expect(wine.quantity == 2)
        #expect(wine.placedCount == 2)
    }

    @Test("Beim Zusammenführen belegte Fächer werden nur geräumt, nie überschrieben")
    func mergeConflict() {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        let first = Rack.findOrCreate(in: context, cellar: cellar)
        let second = Rack.create(in: context, cellar: cellar, name: first.name)!
        let wine = TestStack.makeWine(in: context, quantity: 2)

        // Beide Regale haben A1 belegt – eine der Flaschen muss weichen.
        Slot.place(wine, at: Position(row: 0, column: 0), in: first, context: context)
        Slot.place(wine, at: Position(row: 0, column: 0), in: second, context: context)

        let result = Rack.mergeDuplicates(in: context, for: cellar)
        #expect(result.moved == 0)
        #expect(result.released == 1)
        #expect(wine.quantity == 2)
        #expect(wine.placedCount == 1)
    }

    @Test("Das behaltene Regal wächst mit, damit kein Fach ausserhalb liegt")
    func mergeGrowsKeeper() {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        let first = Rack.findOrCreate(in: context, cellar: cellar)
        first.rows = 1
        first.columns = 4
        let second = Rack.create(in: context, cellar: cellar, name: first.name, rows: 3, columns: 6)!
        let wine = TestStack.makeWine(in: context, quantity: 1)
        Slot.place(wine, at: Position(row: 2, column: 5), in: second, context: context)

        Rack.mergeDuplicates(in: context, for: cellar)
        // Sonst wäre die Flasche verortet, aber in keinem Fach zu sehen.
        #expect(first.rowCount >= 3)
        #expect(first.columnCount >= 6)
        #expect(wine.placedCount == 1)
    }

    @Test("Fachbezeichnung trägt den Regalnamen erst bei mehreren Regalen")
    func slotLabel() throws {
        let context = TestStack.makeContext()
        let cellar = Cellar.active(in: context)
        let first = Rack.findOrCreate(in: context, cellar: cellar)
        let wine = TestStack.makeWine(in: context, quantity: 2)
        let slot = Slot.place(wine, at: Position(row: 1, column: 2), in: first, context: context)

        #expect(slot.displayLabel == "B3")

        // Sobald es zwei gibt, ist „B3“ mehrdeutig.
        let second = try #require(Rack.create(in: context, cellar: cellar, name: "Küche"))
        let other = Slot.place(wine, at: Position(row: 0, column: 0), in: second, context: context)
        #expect(slot.displayLabel == "\(first.name) · B3")
        #expect(other.displayLabel == "Küche · A1")
    }
}
