import CoreData
import Testing
@testable import Wyychaellerli

/// Alkoholgehalt: eigenes Feld, Einordnung, Filter und die Übernahme aus den Notizen.
struct AlcoholTests {

    // MARK: Einordnung

    @Test("Leicht, mittel, kräftig", arguments: [
        (10.5, Wine.Strength.light), (11.9, .light),
        (12.0, .medium), (13.0, .medium), (13.5, .medium),
        (13.6, .strong), (15.0, .strong)
    ])
    func strength(percent: Double, expected: Wine.Strength) {
        #expect(Wine.Strength.from(percent: percent) == expected)
    }

    @Test("Null heisst unbekannt, nicht alkoholfrei")
    func zeroIsUnknown() {
        // Sonst stünde bei jedem nicht erfassten Wein „leicht“ – geraten.
        #expect(Wine.Strength.from(percent: 0) == nil)
        #expect(Wine.Strength.from(percent: -1) == nil)
    }

    @Test("Anzeige mit und ohne Angabe")
    @MainActor
    func display() {
        let context = TestStack.makeContext()
        let known = TestStack.makeWine(in: context, name: "Kräftig", alcoholPercent: 14)
        let unknown = TestStack.makeWine(in: context, name: "Unbekannt")

        #expect(known.hasAlcohol)
        #expect(known.alcoholText == "14 %")
        #expect(known.strength == .strong)

        #expect(!unknown.hasAlcohol)
        #expect(unknown.alcoholText.isEmpty)
        #expect(unknown.strength == nil)
    }

    @Test("Halbe Prozente bleiben erhalten")
    @MainActor
    func halfPercent() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, alcoholPercent: 13.5)

        // Der Dezimaltrenner hängt an der Ländereinstellung – in der Schweiz ein Punkt,
        // in Deutschland ein Komma. Geprüft wird deshalb der Inhalt, nicht das Zeichen.
        #expect(wine.alcoholText.hasSuffix(" %"))
        #expect(wine.alcoholText.contains("13"))
        #expect(wine.alcoholText.contains("5"))
        #expect(wine.strength == .medium)
    }

    // MARK: Erkennung vom Etikett

    @Test("Alkoholgehalt wird vom Etikett gelesen", arguments: [
        ("14.5%", 14.5), ("13,5 %", 13.5), ("ALC. 12.5% BY VOL", 12.5), ("13% vol", 13.0)
    ])
    func detectsFromLabel(text: String, expected: Double) {
        let parsed = HeuristicLabelParser.parse(recognizedText: "Weingut Test\n\(text)")
        #expect(parsed.alcoholPercent == expected)
    }

    @Test("Prozentangaben ausserhalb des sinnvollen Bereichs zählen nicht")
    func ignoresOtherPercentages() {
        // „100 % handgelesen“ ist kein Alkoholgehalt.
        #expect(HeuristicLabelParser.parse(recognizedText: "Weingut Test\n100 % manuell gelesen").alcoholPercent == 0)
    }

    // MARK: Übernahme aus den Notizen

    @Test("Zahl aus der alten Notizzeile", arguments: [
        ("Alkohol: 13,5 % vol.", 13.5),
        ("Alkohol: 14 %", 14.0),
        ("Terroir Kalk.\nAlkohol: 12.5 % vol.", 12.5)
    ])
    func migrationReadsPercent(notes: String, expected: Double) {
        #expect(AlcoholNoteMigration.percent(in: notes) == expected)
    }

    @Test("Notizen ohne Alkoholzeile bleiben unberührt")
    func migrationIgnoresOther() {
        #expect(AlcoholNoteMigration.percent(in: "Terroir Kalk, 18 Monate Barrique.") == nil)
    }

    @Test("Die Zeile verschwindet aus den Notizen, der Rest bleibt")
    func migrationCleansNotes() {
        let notes = "Terroir Kalk.\nAlkohol: 13,5 % vol.\n18 Monate Barrique."
        #expect(AlcoholNoteMigration.cleaned(notes) == "Terroir Kalk.\n18 Monate Barrique.")
    }

    @Test("Steht nur die Alkoholzeile drin, sind die Notizen danach leer")
    func migrationEmptiesNotes() {
        #expect(AlcoholNoteMigration.cleaned("Alkohol: 13,5 % vol.").isEmpty)
    }

    @Test("Die Übernahme füllt das Feld und räumt die Notiz")
    @MainActor
    func migrationRuns() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Alt")
        wine.notes = "Terroir Kalk.\nAlkohol: 13,5 % vol."
        context.saveChanges()

        AlcoholNoteMigration.run(in: context)

        #expect(wine.alcoholPercent == 13.5)
        #expect(wine.notes == "Terroir Kalk.")
    }

    @Test("Ein zweiter Durchlauf ändert nichts mehr")
    @MainActor
    func migrationIsIdempotent() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Alt")
        wine.notes = "Alkohol: 13,5 % vol."
        context.saveChanges()

        AlcoholNoteMigration.run(in: context)
        let afterFirst = wine.alcoholPercent
        AlcoholNoteMigration.run(in: context)

        // Wichtig, weil sie bei jedem Start läuft – auch auf dem zweiten Gerät.
        #expect(wine.alcoholPercent == afterFirst)
        #expect(wine.notes.isEmpty)
    }

    // MARK: Filter

    @Test("Der Filter zeigt nur die passende Schwere")
    @MainActor
    func filter() {
        let context = TestStack.makeContext()
        let light = TestStack.makeWine(in: context, name: "Leicht", alcoholPercent: 11)
        let strong = TestStack.makeWine(in: context, name: "Kräftig", alcoholPercent: 14.5)
        let unknown = TestStack.makeWine(in: context, name: "Unbekannt")
        let all = [light, strong, unknown]

        let model = CellarViewModel()
        #expect(model.filtered(all).count == 3)

        model.strengthFilter = .light
        #expect(model.filtered(all).map(\.name) == ["Leicht"])

        model.strengthFilter = .strong
        #expect(model.filtered(all).map(\.name) == ["Kräftig"])

        // Flaschen ohne Angabe fallen bei gesetztem Filter heraus – „leicht“ zu
        // behaupten, wo nichts bekannt ist, wäre geraten.
        model.strengthFilter = .medium
        #expect(model.filtered(all).isEmpty)
    }

    @Test("Der Filter zählt als aktiver Filter")
    @MainActor
    func filterCountsAsActive() {
        let model = CellarViewModel()
        #expect(!model.isFiltering)
        model.strengthFilter = .strong
        #expect(model.isFiltering)
    }

    // MARK: Weitergeben

    @Test("Beim Empfehlen kommt der Alkoholgehalt mit")
    @MainActor
    func sharing() throws {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Barolo", alcoholPercent: 14.5)
        let share = WineShare(wine: wine)

        let back = try WineShare.decoded(from: share.encoded())
        #expect(back.alcoholPercent == 14.5)

        let receiver = TestStack.makeContext()
        let imported = back.importing(into: receiver)
        #expect(imported.alcoholPercent == 14.5)
        #expect(imported.strength == .strong)
    }
}
