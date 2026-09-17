import CoreData
import Foundation
import OSLog

/// Holt den Alkoholgehalt aus den Notizen ins eigene Feld – einmalig.
///
/// Bis September 2026 schrieb der Scan „Alkohol: 13,5 % vol.“ als Zeile in die Notizen,
/// und die Detailseite klaubte die Zahl per Mustersuche wieder heraus. Seit es ein
/// richtiges Feld gibt, wandern bestehende Angaben dorthin und die Zeile verschwindet
/// aus dem Freitext.
///
/// Läuft bei jedem Start, kostet aber nichts: Sie findet nur Weine mit leerem Feld und
/// passender Zeile. Auf dem zweiten Gerät ist deshalb nichts mehr zu tun – und wenn doch
/// beide gleichzeitig laufen, schreiben sie denselben Wert.
enum AlcoholNoteMigration {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Migration")

    /// „Alkohol: 13,5 % vol.“ – mit oder ohne „vol.“, Komma oder Punkt.
    private static let pattern = #"(?i)\s*Alkohol:\s*\d{1,2}(?:[.,]\d)?\s*%(?:\s*vol\.?)?\s*"#

    @MainActor
    static func run(in context: NSManagedObjectContext) {
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "alcoholPercent == 0 AND notes CONTAINS[c] %@", "Alkohol:")
        guard let wines = try? context.fetch(request), !wines.isEmpty else { return }

        var moved = 0
        for wine in wines {
            guard let percent = percent(in: wine.notes) else { continue }
            wine.alcoholPercent = percent
            wine.notes = cleaned(wine.notes)
            moved += 1
        }
        guard moved > 0 else { return }
        context.saveChanges()
        logger.info("Alkoholgehalt bei \(moved) Weinen aus den Notizen übernommen.")
    }

    /// Die Zahl aus der Notiz, oder `nil`.
    static func percent(in notes: String) -> Double? {
        guard let range = notes.range(of: pattern, options: .regularExpression) else { return nil }
        let line = String(notes[range])
        guard let numberRange = line.range(of: #"\d{1,2}(?:[.,]\d)?"#, options: .regularExpression) else { return nil }
        let number = line[numberRange].replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value > 0, value <= 25 else { return nil }
        return value
    }

    /// Notiz ohne die Alkoholzeile, ohne Leerzeilen am Rand.
    static func cleaned(_ notes: String) -> String {
        notes
            .replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
