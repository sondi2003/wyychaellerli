import Foundation
import Testing
@testable import Wyychaellerli

/// Die Suche im Browser: Sie darf nicht davon abhängen, ob die Abfrage über den Webhook etwas
/// findet. Die Adresse ist vorgegeben und in den Einstellungen änderbar.
@Suite(.serialized)
struct ReferenceBrowserSearchTests {

    /// Stellt die gemerkte Adresse nach dem Test wieder her.
    private func withBrowserAddress(_ value: String, _ body: () -> Void) {
        let old = ReferenceLookupSettings.browserSearchString
        ReferenceLookupSettings.browserSearchString = value
        defer { ReferenceLookupSettings.browserSearchString = old }
        body()
    }

    @Test("Ohne eigene Adresse gilt die Vorgabe")
    func defaultAddress() {
        withBrowserAddress("") {
            #expect(ReferenceLookupSettings.browserURL(for: "Donatsch")?.scheme == "https")
        }
    }

    @Test("Der Begriff ersetzt {q} und wird für die Adresse kodiert")
    func replacesPlaceholder() {
        withBrowserAddress("https://example.test/search/wines?q={q}") {
            let url = ReferenceLookupSettings.browserURL(for: "Villa Antinori & Co 2021")
            #expect(url?.absoluteString == "https://example.test/search/wines?q=Villa%20Antinori%20%26%20Co%202021")
        }
    }

    @Test("Ohne {q} hängt die App den Begriff an; nur https gilt")
    func appendsAndRequiresHTTPS() {
        withBrowserAddress("https://example.test/search") {
            #expect(ReferenceLookupSettings.browserURL(for: "Unique")?.absoluteString == "https://example.test/search?q=Unique")
        }
        withBrowserAddress("http://example.test/search?q={q}") {
            #expect(ReferenceLookupSettings.browserURL(for: "Unique") == nil)
        }
    }

    @Test("Der Begriff aus dem Vorschlag: Produzent, Name, Jahrgang")
    func termFromEntry() {
        let wine = CatalogWine(
            id: "x", name: "Unique Pinot Noir", producer: "Donatsch", vintage: 2021, grape: "", region: "",
            country: "", typeRaw: "red", alcoholPercent: 0, source: "nutzer")
        #expect(ReferenceLookupSettings.browserTerm(for: wine) == "Donatsch Unique Pinot Noir 2021")
    }
}
