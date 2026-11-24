import Testing
@testable import Wyychaellerli

/// Wann ein Treffer des Geocoders als die gesuchte Weinregion gilt.
///
/// Die Fälle sind **gemessen**, nicht ausgedacht: am 24.11.2026 mit `MKGeocodingRequest`
/// auf iOS 27.2, Systemsprache Deutsch. Sie halten fest, was MapKit für typische
/// Regionen zurückgibt und wie die App darauf antwortet. Ändert Apple die Antworten,
/// stimmen diese Werte nicht mehr – dann neu messen, nicht die Regel aufweichen.
struct RegionGeocoderTests {

    private func hit(_ name: String, city: String?, full: String) -> RegionGeocoder.Hit {
        RegionGeocoder.Hit(name: name, cityName: city, fullAddress: full, regionName: nil, latitude: 0, longitude: 0)
    }

    @Test("Mosel ist nicht der Ortsteil von Zwickau")
    func moselIsNotZwickau() {
        let zwickau = hit("Mosel", city: "Zwickau", full: "Mosel, Zwickau, Sachsen, Deutschland")
        #expect(!RegionGeocoder.matches(zwickau, region: "Mosel"))
    }

    @Test("Wallis ist nicht der Weiler im Aargau")
    func wallisIsNotKoelliken() {
        let koelliken = hit("Wallis", city: "Kölliken", full: "Wallis, Kölliken, Schweiz")
        #expect(!RegionGeocoder.matches(koelliken, region: "Wallis"))
    }

    @Test("Provence und Douro: Ortsteile anderer Orte zählen nicht, auch mit Postleitzahl davor")
    func hamletsDoNotCount() {
        #expect(!RegionGeocoder.matches(hit("Provence", city: "Marchampt", full: "Provence, 69430 Marchampt, Frankreich"), region: "Provence"))
        #expect(!RegionGeocoder.matches(hit("Douro", city: "Figueiró dos Vinhos", full: "Douro, Figueiró dos Vinhos, Portugal"), region: "Douro"))
    }

    @Test("Elsass liefert Munster – kein Treffer")
    func alsaceGivesMunster() {
        #expect(!RegionGeocoder.matches(hit("Munster", city: "Munster", full: "68140 Munster, Frankreich"), region: "Elsass"))
    }

    @Test("Städte und Regionen, die MapKit als Ort nennt, zählen")
    func placesAndRegionsCount() {
        #expect(RegionGeocoder.matches(hit("Bordeaux", city: "Bordeaux", full: "33000 Bordeaux, Frankreich"), region: "Bordeaux"))
        #expect(RegionGeocoder.matches(hit("Collioure", city: "Collioure", full: "66190 Collioure, Frankreich"), region: "Collioure"))
        #expect(RegionGeocoder.matches(hit("Piemont", city: "Piemont", full: "Piemont, Italien"), region: "Piemont"))
        #expect(RegionGeocoder.matches(hit("Toskana", city: "Toskana", full: "Toskana, Italien"), region: "Toskana"))
    }

    @Test("Rioja trifft La Rioja, Graubünden den Kanton Graubünden")
    func partialNamesCount() {
        #expect(RegionGeocoder.matches(hit("La Rioja", city: "La Rioja", full: "La Rioja, Spanien"), region: "Rioja"))
        #expect(RegionGeocoder.matches(hit("Kanton Graubünden", city: "Kanton Graubünden", full: "Kanton Graubünden, Schweiz"), region: "Graubünden"))
    }

    @Test("Napa Valley zählt, obwohl MapKit „Kalifornien“ als Ort nennt")
    func napaValleyCounts() {
        let napa = hit("Napa Valley", city: "Kalifornien", full: "Napa Valley, CA, Vereinigte Staaten")
        #expect(RegionGeocoder.matches(napa, region: "Napa Valley"))
    }

    @Test("Leere Region trifft nie")
    func emptyRegion() {
        #expect(!RegionGeocoder.matches(hit("Schweiz", city: "Schweiz", full: "Schweiz"), region: "  "))
    }
}
