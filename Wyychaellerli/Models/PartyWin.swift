import CoreData
import Foundation
import UIKit

/// Die Siegerflasche einer Party-Abstimmung – als Erinnerung, nicht als Verweis.
///
/// Name und Etikettfoto stehen als Kopie drin: Der Wein wird an diesem Abend getrunken
/// und irgendwann gelöscht, „Silvester 2026: der Barolo“ soll trotzdem bleiben.
@objc(PartyWinEntity)
final class PartyWin: NSManagedObject, Identifiable {

    @nonobjc class func fetchRequest() -> NSFetchRequest<PartyWin> {
        NSFetchRequest<PartyWin>(entityName: "PartyWin")
    }

    @NSManaged var uuid: UUID?
    /// Anlass, wie ihn der Gastgeber eingetippt hat: „Silvester“, „Grillabend“.
    @NSManaged var title: String
    @NSManaged var date: Date?
    @NSManaged var wineName: String
    /// Jahrgang, Rebsorte, Region – die Kurzform aus der Liste.
    @NSManaged var wineSubtitle: String
    /// Kennung des Weins, solange es ihn noch gibt.
    @NSManaged var wineUUID: UUID?
    @NSManaged var labelImageData: Data?
    @NSManaged var votes: Int64
    @NSManaged var totalVotes: Int64
    @NSManaged var guestCount: Int64
    @NSManaged var candidateCount: Int64
    /// `true`, wenn es einen Gleichstand gab und das Los entschieden hat.
    @NSManaged var wasDrawn: Bool
    @NSManaged var cellar: Cellar?

    var id: NSManagedObjectID { objectID }

    var labelImage: UIImage? { labelImageData.flatMap(UIImage.init(data:)) }

    /// „7 von 12 Stimmen“ – oder der Hinweis aufs Los.
    var resultText: String {
        let base = "\(votes) " + tr("von \(totalVotes) Stimmen")
        return wasDrawn ? base + tr(", per Los entschieden") : base
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return date.map { $0.appShortDate } ?? tr("Party")
    }

    // MARK: Anlegen und Lesen

    @discardableResult
    static func record(
        title: String,
        wine: Wine,
        votes: Int,
        totalVotes: Int,
        guestCount: Int,
        candidateCount: Int,
        wasDrawn: Bool,
        in context: NSManagedObjectContext
    ) -> PartyWin {
        let cellar = Cellar.active(in: context)
        let win = PartyWin(context: context)
        // In denselben Speicher wie der Keller, sonst sieht die andere Seite es nie.
        if let store = cellar.objectID.persistentStore {
            context.assign(win, to: store)
        }
        win.uuid = UUID()
        win.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        win.date = .now
        win.wineName = wine.name
        win.wineSubtitle = wine.subtitle
        win.wineUUID = wine.uuid
        // Verkleinertes Etikett: Die Erinnerung soll die Datenbank nicht aufblähen.
        win.labelImageData = wine.labelImage
            .flatMap { $0.resizedForRecognition(maxDimension: 600).jpegData(compressionQuality: 0.7) }
        win.votes = Int64(votes)
        win.totalVotes = Int64(totalVotes)
        win.guestCount = Int64(guestCount)
        win.candidateCount = Int64(candidateCount)
        win.wasDrawn = wasDrawn
        win.cellar = cellar
        context.saveChanges()
        return win
    }

    static func all(in context: NSManagedObjectContext) -> [PartyWin] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
}
