import CoreData
import Foundation
import Testing
@testable import Wyychaellerli

/// Weine weiterempfehlen: Nachricht, Datei und Übernehmen.
@MainActor
struct WineShareTests {

    private func makeShare(in context: NSManagedObjectContext, comment: String = "", sender: String = "") -> WineShare {
        let wine = TestStack.makeWine(
            in: context,
            name: "Barolo Riserva",
            producer: "Giacomo Conterno",
            vintage: 2018,
            grape: "Nebbiolo",
            country: "Italien",
            type: .red,
            drinkFrom: 2024,
            drinkTo: 2032,
            foodPairings: ["Lamm", "Käse"]
        )
        return WineShare(wine: wine, comment: comment, senderName: sender)
    }

    @Test("Die Nachricht enthält Name, Jahrgang und Herkunft")
    func messageText() {
        let context = TestStack.makeContext()
        let share = makeShare(in: context)

        #expect(share.title == "Barolo Riserva 2018")
        #expect(share.messageText.contains("Barolo Riserva 2018"))
        #expect(share.messageText.contains("Giacomo Conterno"))
        #expect(share.messageText.contains("Nebbiolo"))
        #expect(share.messageText.contains("Rotwein"))
        #expect(share.messageText.contains("Wyychällerli"))
    }

    @Test("Der eigene Hinweis und der Absender stehen dabei")
    func commentAndSender() {
        let context = TestStack.makeContext()
        let share = makeShare(in: context, comment: "Gibt's bei Denner für 12.90", sender: "Richard")

        #expect(share.messageText.contains("Gibt's bei Denner für 12.90"))
        #expect(share.messageText.contains("Von Richard"))
    }

    @Test("Ohne Jahrgang steht keine Null in der Nachricht")
    func withoutVintage() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Hauswein", vintage: 0, grape: "Merlot")
        let share = WineShare(wine: wine)

        #expect(share.title == "Hauswein")
        #expect(!share.messageText.contains("0"))
    }

    @Test("Die Datei übersteht Schreiben und Lesen")
    func roundTrip() throws {
        let context = TestStack.makeContext()
        let share = makeShare(in: context, comment: "Sehr gut", sender: "Richard")

        let data = try share.encoded()
        let back = try WineShare.decoded(from: data)

        #expect(back.name == "Barolo Riserva")
        #expect(back.vintage == 2018)
        #expect(back.grape == "Nebbiolo")
        #expect(back.foodPairings == ["Lamm", "Käse"])
        #expect(back.drinkFrom == 2024)
        #expect(back.comment == "Sehr gut")
        #expect(back.senderName == "Richard")
    }

    @Test("Der Dateiname enthält keine Sonderzeichen")
    func fileName() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Château d'Yquem", vintage: 2015)
        let share = WineShare(wine: wine)

        // Manche Ziele stolpern über Akzente und Apostrophe im Dateinamen.
        #expect(share.fileName == "Chateau-d-Yquem-2015.wyy")
        #expect(share.fileName.hasSuffix(".wyy"))
    }

    @Test("Eine geschriebene Datei lässt sich wieder einlesen")
    func writeAndRead() throws {
        let context = TestStack.makeContext()
        let share = makeShare(in: context, sender: "Ines")

        let url = try share.writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try #require(ContentView.readShare(at: url))
        #expect(read.name == share.name)
        #expect(read.senderName == "Ines")
    }

    @Test("Andere Dateiendungen werden nicht angefasst")
    func ignoresOtherFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
        try Data("kein Wein".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ContentView.readShare(at: url) == nil)
    }

    @Test("Übernehmen legt den Wein mit Bestand 1 an")
    func importing() {
        let sender = TestStack.makeContext()
        let share = makeShare(in: sender)

        // Empfänger ist ein eigener Keller.
        let receiver = TestStack.makeContext()
        let wine = share.importing(into: receiver)

        #expect(wine.name == "Barolo Riserva")
        #expect(wine.vintage == 2018)
        #expect(wine.grape == "Nebbiolo")
        #expect(wine.foodPairings == ["Lamm", "Käse"])
        #expect(wine.drinkFrom == 2024)
        // Wie viele Flaschen der Empfänger kauft, weiss nur er.
        #expect(wine.quantity == 1)
    }

    @Test("Beim Übernehmen wird erkannt, wenn die Flasche schon da ist")
    func detectsDuplicate() {
        let context = TestStack.makeContext()
        let share = makeShare(in: context)

        // Derselbe Keller hat den Wein bereits – der Test spiegelt, was die
        // Import-Ansicht prüft, bevor sie etwas anlegt.
        let matches = DuplicateFinder.findDuplicates(of: share.duplicateCandidate, in: context)
        #expect(matches.count == 1)
        #expect(matches.first?.wine.name == "Barolo Riserva")
    }
}
