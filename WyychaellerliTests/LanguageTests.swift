import Foundation
import Testing
@testable import Wyychaellerli

/// Serbische Übersetzung: Pluralformen, Wortstellung und die Zuordnung der Gründe.
///
/// Die Texte werden mit einer ausdrücklich gesetzten Locale aufgelöst und nicht über die
/// gespeicherte App-Sprache – sonst stünden diese Tests in Konkurrenz zu allen anderen,
/// die deutsche Texte erwarten.
struct LanguageTests {

    private func serbian(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = Locale(identifier: "sr-Latn")
        return String(localized: resource)
    }

    private func german(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = Locale(identifier: "de")
        return String(localized: resource)
    }

    @Test("Serbisch kennt drei Pluralformen: 1, 2 bis 4 und der Rest")
    func serbianPlurals() {
        #expect(serbian("\(1) Flaschen") == "1 flaša")
        #expect(serbian("\(2) Flaschen") == "2 flaše")
        #expect(serbian("\(4) Flaschen") == "4 flaše")
        #expect(serbian("\(5) Flaschen") == "5 flaša")
        #expect(serbian("\(11) Flaschen") == "11 flaša")
        #expect(serbian("\(21) Flaschen") == "21 flaša")
        #expect(serbian("\(22) Flaschen") == "22 flaše")
    }

    @Test("Deutsch trennt nur Einzahl und Mehrzahl")
    func germanPlurals() {
        #expect(german("\(1) Flaschen") == "1 Flasche")
        #expect(german("\(2) Flaschen") == "2 Flaschen")
        #expect(german("\(1) Stimmen") == "1 Stimme")
    }

    @Test("Der Satzteil „von … Stimmen“ richtet sich nach der Gesamtzahl")
    func votesOfTotal() {
        #expect(serbian("von \(1) Stimmen") == "od 1 glasa")
        #expect(serbian("von \(12) Stimmen") == "od 12 glasova")
        #expect(german("von \(1) Stimmen") == "von 1 Stimme")
    }

    @Test("Mehrere Platzhalter dürfen die Reihenfolge wechseln")
    func reorderedPlaceholders() {
        #expect(serbian("\(3) von \(12) Fächern belegt · \(9) frei") == "3 od 12 mesta zauzeto · 9 slobodno")
        #expect(serbian("Zu \("Lasagne") empfehle ich \("Barolo"), Jahrgang \("2018").") == "Uz Lasagne preporučujem Barolo, berba 2018.")
    }

    @Test("Ein unbekannter Text bleibt, wie er ist")
    func unknownKeyStaysGerman() {
        #expect(serbian("Dieser Satz steht in keinem Katalog") == "Dieser Satz steht in keinem Katalog")
    }

    @Test("Die Sprache „System“ wählt Serbisch nur bei serbischem Gerät")
    func resolvedIdentifier() {
        #expect(AppLanguage.german.resolvedIdentifier == "de")
        #expect(AppLanguage.serbian.resolvedIdentifier == "sr-Latn")
        #expect(AppLanguage.serbian.isSerbian)
        #expect(!AppLanguage.german.isSerbian)
    }

    @Test("Jeder Bewertungsgrund hat einen Anzeigetext; gespeichert bleibt der deutsche Rohwert")
    func ratingTags() {
        for tag in RatingTag.allCases {
            #expect(!tag.title.isEmpty)
        }
        #expect(RatingTag.title(forStored: "Gerne wieder") == RatingTag.wantAgain.title)
        #expect(RatingTag.title(forStored: "Etwas Altes") == "Etwas Altes")
    }

    @Test("Kroatisch und Bosnisch zählen beim Serbischen als Zielsprache, Deutsch nicht")
    func notesTargetLanguage() {
        let croatian = "Vinogradi leže na strmim padinama iznad mora, a tlo je bogato škriljcem i vapnencem."
        #expect(LabelNotesTranslator.foreignLanguage(in: croatian, target: .serbian) == nil)
        let german = "Die Reben wachsen auf Schieferterrassen direkt über dem Meer, der Wein reift im Fass."
        #expect(LabelNotesTranslator.foreignLanguage(in: german, target: .serbian) != nil)
        #expect(LabelNotesTranslator.foreignLanguage(in: german, target: .german) == nil)
    }
}
