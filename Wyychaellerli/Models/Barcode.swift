import Foundation

/// Strichcodes auf Weinflaschen: EAN-13 und EAN-8.
///
/// Ein Strichcode ist hier ein **Suchmerkmal, kein Schlüssel**. Viele Weingüter behalten
/// denselben Code über alle Jahrgänge; der Jahrgang entscheidet deshalb weiter, welcher
/// Katalogeintrag gemeint ist (siehe `CatalogMatcher.match(barcode:…)`).
///
/// Gespeichert wird nur, was die Prüfziffer besteht. Eine falsch gelesene Ziffer – im
/// Foto verrutscht, beim Tippen vertauscht – ergäbe sonst einen Code, der nie trifft oder
/// schlimmer: den falschen Wein.
enum Barcode {

    /// Die Ziffern eines gültigen Strichcodes, sonst leer.
    ///
    /// UPC-A (12 Ziffern, in Amerika üblich) wird mit einer vorangestellten Null zum
    /// EAN-13 – genau so liefert ihn auch die Kamera.
    static func normalized(_ raw: String) -> String {
        var digits = raw.filter { $0.isASCII && $0.isNumber }
        if digits.count == 12 { digits = "0" + digits }
        guard digits.count == 13 || digits.count == 8, hasValidCheckDigit(digits) else { return "" }
        return digits
    }

    /// Die Prüfziffer nach GS1: von rechts abwechselnd mit 3 und 1 gewichtet.
    static func hasValidCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 2 else { return false }
        let body = values.dropLast().reversed()
        let sum = body.enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10 == values.last
    }

    /// Mehrere Codes aus einer Eingabe, getrennt durch Komma, Leerzeichen oder Strichpunkt.
    /// Ungültige fallen weg, Doppelte auch, die Reihenfolge bleibt.
    static func list(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map(normalized)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Ist in der Eingabe etwas, das nach einem Code aussieht, aber nicht besteht?
    /// Für den Hinweis im Formular, damit Tippfehler nicht still verschwinden.
    static func hasInvalidEntry(in text: String) -> Bool {
        text.components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .filter { !$0.isEmpty }
            .contains { normalized($0).isEmpty }
    }
}
