import CoreData
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Ein Wein zum Weitergeben – als Nachricht **und** als Datei.
///
/// Zwei Empfänger, ein Format: Wer die App nicht hat, sieht Etikett und Text in
/// WhatsApp oder Mail. Wer sie hat, tippt die angehängte Datei an und übernimmt die
/// Flasche mit allen Feldern in den eigenen Keller.
struct WineShare: Codable, Equatable, Sendable, Identifiable {

    /// Für `sheet(item:)` – jede Empfehlung ist für sich.
    var id: String { "\(name)-\(vintage)-\(sharedAt.timeIntervalSince1970)" }


    /// Dateiendung und Typ, unter dem iOS die Datei dieser App zuordnet.
    static let fileExtension = "wyy"
    static let contentType = UTType(exportedAs: "ch.sondinetwork.wyychaellerli.wine")

    /// Fassung des Formats. Ändert sich das Feld-Set, kann eine ältere App das erkennen.
    var version = 1

    var name: String
    var producer: String
    var vintage: Int
    var grape: String
    var region: String
    var country: String
    /// `WineType.rawValue`.
    var type: String
    var notes: String
    /// Volumenprozent; 0 heisst unbekannt.
    var alcoholPercent: Double = 0
    var foodPairings: [String]
    var drinkFrom: Int
    var drinkTo: Int
    var drinkWindowFromLabel: Bool
    /// Etikettfotos, verkleinert – eine Nachricht soll nicht megabyteschwer werden.
    var labelImageData: Data?
    var backLabelImageData: Data?

    /// Was der Absender dazuschreibt: „Gibt's bei Denner für 12.90“.
    var comment: String
    /// Name des Absenders, damit beim Empfänger nicht nur ein Wein auftaucht.
    var senderName: String
    var sharedAt: Date

    var wineType: WineType { WineType(rawValue: type) ?? .red }
    var hasVintage: Bool { vintage > 0 }

    // MARK: Aus einem Wein

    @MainActor
    init(wine: Wine, comment: String = "", senderName: String = "") {
        name = wine.name
        producer = wine.producer
        vintage = Int(wine.vintage)
        grape = wine.grape
        region = wine.region
        country = wine.country
        type = wine.type.rawValue
        notes = wine.notes
        alcoholPercent = wine.alcoholPercent
        foodPairings = wine.foodPairings
        drinkFrom = Int(wine.drinkFrom)
        drinkTo = Int(wine.drinkTo)
        drinkWindowFromLabel = wine.drinkWindowFromLabel
        // Auf 1000 px verkleinert: gut lesbar, aber die Datei bleibt unter einem Megabyte.
        labelImageData = wine.labelImage.flatMap(Self.shrink)
        backLabelImageData = wine.backLabelImage.flatMap(Self.shrink)
        self.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        self.senderName = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        sharedAt = .now
    }

    private static func shrink(_ image: UIImage) -> Data? {
        image.resizedForRecognition(maxDimension: 1000).jpegData(compressionQuality: 0.7)
    }

    // MARK: Darstellung

    var labelImage: UIImage? { labelImageData.flatMap(UIImage.init(data:)) }

    /// Erste Zeile: „Barolo Riserva 2018“ – ohne Jahrgang nur der Name.
    var title: String {
        hasVintage ? "\(name) \(vintage)" : name
    }

    /// Zweite Zeile: Produzent, Rebsorte, Herkunft – was davon bekannt ist.
    var subtitle: String {
        let origin = region.isEmpty ? country : region
        let flag = CountryFlag.emoji(for: country).map { " \($0)" } ?? ""
        return [producer, grape, origin.isEmpty ? "" : origin + flag]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Der Text, der in der Nachricht steht.
    ///
    /// Bewusst kurz und ohne Werbeformeln: Was drinsteht, soll man auf einen Blick
    /// lesen können, auch in einer Vorschau.
    var messageText: String {
        var lines = [title]
        if !subtitle.isEmpty { lines.append(subtitle) }
        lines.append(wineType.displayName)
        if !comment.isEmpty {
            lines.append("")
            lines.append(comment)
        }
        lines.append("")
        lines.append(senderName.isEmpty
                     ? "Geteilt aus Wyychällerli"
                     : "Von \(senderName), geteilt aus Wyychällerli")
        return lines.joined(separator: "\n")
    }

    // MARK: Datei

    /// Dateiname ohne Sonderzeichen, damit ihn jedes Ziel annimmt.
    var fileName: String {
        let base = title
            .folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return (base.isEmpty ? "Wein" : base) + "." + Self.fileExtension
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> WineShare {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WineShare.self, from: data)
    }

    /// Schreibt die Datei in den temporären Ordner und gibt ihren Ort zurück.
    func writeToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try encoded().write(to: url, options: .atomic)
        return url
    }

    // MARK: In den eigenen Keller

    /// Legt den Wein beim Empfänger an. Bestand 1 – wie viele Flaschen er kauft,
    /// weiss nur er selbst.
    @MainActor
    @discardableResult
    func importing(into context: NSManagedObjectContext) -> Wine {
        let wine = Wine.create(
            in: context,
            cellar: Cellar.active(in: context),
            name: name,
            producer: producer,
            vintage: vintage,
            grape: grape,
            region: region,
            country: country,
            type: wineType,
            quantity: 1,
            notes: notes,
            alcoholPercent: alcoholPercent,
            foodPairings: foodPairings,
            labelImageData: labelImageData,
            backLabelImageData: backLabelImageData,
            drinkFrom: drinkFrom,
            drinkTo: drinkTo,
            drinkWindowFromLabel: drinkWindowFromLabel
        )
        context.saveChanges()
        return wine
    }

    /// Passt zur Doppelerkennung, damit der Empfänger merkt, wenn er ihn schon hat.
    var duplicateCandidate: DuplicateFinder.Candidate {
        DuplicateFinder.Candidate(name: name, producer: producer, vintage: vintage)
    }
}
