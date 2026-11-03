import SwiftUI
import TipKit

/// Kurze Tipps am Ort des Geschehens, je einmal – die Ergänzung zur Einführung.
///
/// Die Einführung wischt man beim ersten Start durch und hat sie drei Tage später
/// vergessen. Diese Tipps erscheinen erst dort, wo man sie braucht: im Regal, beim
/// Scannen, an der Liste. Ein Tipp verschwindet, sobald man die Sache einmal gemacht
/// oder ihn weggetippt hat.
enum QuickTips {

    /// Jede Runde bekommt eine eigene Kennung. „Tipps nochmals zeigen“ zählt hoch, und
    /// TipKit hält die Tipps damit für neu – ohne Neustart und ohne den Speicher zu leeren.
    private static let generationKey = "tips.generation"

    static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }

    static func showAgain() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
    }

    /// Einmal beim App-Start. `.immediate`, weil die Tipps auf verschiedenen Seiten liegen
    /// und sich nie gegenseitig ins Bild drängen.
    static func configure() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }
}

/// Im Regal, über der Liste der noch nicht verorteten Weine.
struct RackSwipeTip: Tip {
    var id: String { "rack.swipe.\(QuickTips.generation)" }
    var title: Text { Text("Alle Flaschen auf einmal einräumen") }
    var message: Text? {
        Text("Tippe auf einen Wein in dieser Liste und wisch dann über die freien Fächer – so viele, wie er Flaschen hat.")
    }
    var image: Image? { Image(systemName: "hand.draw") }
}

/// Beim Scannen, über den beiden Fotoflächen.
struct ScanWholeBottleTip: Tip {
    var id: String { "scan.whole.\(QuickTips.generation)" }
    var title: Text { Text("Die Flasche einfach ganz fotografieren") }
    var message: Text? {
        Text("Kein Ausrichten nötig: Die App findet das Etikett selbst und schneidet es zu. Die Rückseite dazu, dann kommen die Notizen mit.")
    }
    var image: Image? { Image(systemName: "camera.viewfinder") }
}

/// In der Kellerliste: Ohne Foto und aus der Mediathek liegen hinter langem Drücken auf
/// den Scan-Knopf. Als Karte, nicht als Blase am Knopf – siehe `ScanButton`.
struct ScanOptionsTip: Tip {
    var id: String { "scan.options.\(QuickTips.generation)" }
    var title: Text { Text("Kamera unten lange drücken") }
    var message: Text? {
        Text("Ein Foto aus der Mediathek nehmen oder einen Wein ganz ohne Foto erfassen.")
    }
    var image: Image? { Image(systemName: "hand.tap") }

    /// Erst wenn schon Weine da sind: Den Grundweg (einfach tippen) soll man zuerst kennen.
    @Parameter static var hasWines: Bool = false
    var rules: [Rule] { #Rule(Self.$hasWines) { $0 } }
}

/// In der Kellerliste, sobald Weine da sind.
struct ConsumeTip: Tip {
    var id: String { "consume.\(QuickTips.generation)" }
    var title: Text { Text("Getrunken? Minus tippen") }
    var message: Text? {
        Text("Bucht eine Flasche ab. Liegt sie im Regal, fragt die App, aus welchem Fach. Bei der letzten Flasche fragt sie, ob der Wein ins Archiv soll.")
    }
    var image: Image? { Image(systemName: "minus.circle") }
}

/// Auf der Detailseite am Etikett, wenn es eine Rückseite gibt.
struct BackLabelTip: Tip {
    var id: String { "backlabel.\(QuickTips.generation)" }
    var title: Text { Text("Wisch nach links") }
    var message: Text? { Text("Dahinter liegt die Rückseite mit Terroir, Ausbau und Speiseempfehlung.") }
    var image: Image? { Image(systemName: "hand.point.left") }
}
