import CoreLocation
import Foundation
import MapKit
import OSLog

/// Aufgelöste Herkunft: Koordinate plus lesbarer Ortsname.
struct GeocodedRegion: Sendable, Equatable {

    /// Wie genau der Treffer ist.
    enum Precision: String, Sendable {
        /// Die Region selbst wurde gefunden – Stecknadel ist sinnvoll.
        case place
        /// Nur das Land ist gesichert – Karte zeigt das Land ohne Nadel.
        case country
    }

    let latitude: Double
    let longitude: Double
    /// Zum Anzeigen, z. B. „Collioure, Frankreich“.
    let placeName: String
    let precision: Precision
}

/// Schlägt zu einer Weinregion die Koordinaten nach – über Apples Geocoder in MapKit
/// (`MKGeocodingRequest`; `CLGeocoder` ist seit iOS 26 abgekündigt).
///
/// Braucht keinen API-Key und keine Standortfreigabe, weil nur eine Adresse in
/// Koordinaten übersetzt wird (Forward Geocoding).
///
/// Wichtig: Regionsnamen sind mehrdeutig. „Mosel, Deutschland“ liefert einen Ortsteil
/// von Zwickau in Sachsen, „Wallis, Schweiz“ einen Weiler im Aargau. Deshalb wird jeder
/// Treffer geprüft: Passt er nicht zur genannten Region, wird lieber nur das Land
/// gezeigt als eine falsche Stecknadel gesetzt.
actor RegionGeocoder {

    /// Was vom Treffer gebraucht wird, als reine Werte: `MKMapItem` ist nicht `Sendable`
    /// und bliebe sonst am Hauptthread hängen. So lässt sich die Prüfung auch testen.
    struct Hit: Sendable, Equatable {
        /// Name des Treffers, z. B. „Mosel“ oder „La Rioja“.
        var name: String?
        /// Ort laut MapKit. Bei einer Region ist das die Region selbst („Piemont“), bei
        /// einem Ortsteil der Ort, in dem er liegt („Zwickau“).
        var cityName: String?
        /// Ganze Adresse, kommagetrennt: „Mosel, Zwickau, Sachsen, Deutschland“.
        var fullAddress: String?
        /// Land.
        var regionName: String?
        var latitude: Double
        var longitude: Double
    }

    static let shared = RegionGeocoder()

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Geocoder")
    /// Anfragen, die schon erfolglos waren – nicht endlos wiederholen.
    private var failed: Set<String> = []

    /// Schlüssel, an dem erkannt wird, ob ein gespeichertes Ergebnis noch zur Eingabe passt.
    nonisolated static func query(region: String, country: String) -> String? {
        let parts = [region, country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: ", ")
        return joined.count >= 2 ? joined : nil
    }

    /// Sucht zuerst die Region, fällt bei unplausiblem Treffer auf das Land zurück.
    func lookup(region: String, country: String) async -> GeocodedRegion? {
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = country.trimmingCharacters(in: .whitespacesAndNewlines)

        if !region.isEmpty {
            let full = country.isEmpty ? region : "\(region), \(country)"
            if let hit = await geocode(full), Self.matches(hit, region: region) {
                return Self.result(from: hit, precision: .place, region: region, fallbackName: full)
            }
            Self.logger.info("Kein plausibler Treffer für Region „\(region)“ – zeige nur das Land")
        }

        guard !country.isEmpty, let hit = await geocode(country) else { return nil }
        return Self.result(from: hit, precision: .country, region: region, fallbackName: country)
    }

    // MARK: Geocoding

    private func geocode(_ query: String) async -> Hit? {
        let key = query.lowercased()
        if failed.contains(key) { return nil }
        do {
            guard let hit = try await Self.fetch(query) else {
                failed.insert(key)
                return nil
            }
            return hit
        } catch {
            Self.logger.info("Geocoding für „\(query)“ fehlgeschlagen: \(error.localizedDescription)")
            failed.insert(key)
            return nil
        }
    }

    /// Fragt MapKit und nimmt vom ersten Treffer nur die Werte mit.
    @MainActor
    private static func fetch(_ query: String) async throws -> Hit? {
        guard let request = MKGeocodingRequest(addressString: query),
              let item = try await request.mapItems.first else { return nil }
        let representations = item.addressRepresentations
        return Hit(
            name: item.name,
            cityName: representations?.cityName,
            fullAddress: item.address?.fullAddress,
            regionName: representations?.regionName,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude
        )
    }

    private static func result(
        from hit: Hit,
        precision: GeocodedRegion.Precision,
        region: String,
        fallbackName: String
    ) -> GeocodedRegion? {
        let name: String
        switch precision {
        case .place:
            // Passt der Ort zur Region, heisst die Stelle wie der Ort („La Rioja“),
            // sonst wie der Treffer selbst („Napa Valley“).
            let place = cityMatches(hit.cityName, region: region) ? hit.cityName : (hit.name ?? hit.cityName)
            name = [place, hit.regionName].compactMap { $0 }.joined(separator: ", ")
        case .country:
            name = hit.regionName ?? fallbackName
        }
        return GeocodedRegion(
            latitude: hit.latitude,
            longitude: hit.longitude,
            placeName: name.isEmpty ? fallbackName : name,
            precision: precision
        )
    }

    // MARK: Plausibilitätsprüfung

    /// Der Treffer zählt in zwei Fällen. Die Regeln sind am 24.11.2026 an 14 Weinregionen
    /// gemessen (siehe `RegionGeocoderTests`), nicht aus der Dokumentation abgeleitet:
    ///
    /// 1. **Der Ort ist die Region**: MapKit nennt bei einer Region sie selbst als Ort
    ///    („Piemont“, „La Rioja“, „Kanton Graubünden“), bei einer Stadt die Stadt („Bordeaux“).
    /// 2. **Der Name ist die Region und liegt in keinem anderen Ort**: „Napa Valley“ hat als
    ///    Ort „Kalifornien“, der in der Adresse gar nicht vorkommt.
    ///
    /// Der Name allein reicht nicht: Bei „Mosel“ heisst der Ortsteil von Zwickau ebenfalls
    /// „Mosel“, liegt aber 400 km vom Weinbaugebiet entfernt – erkennbar daran, dass der Ort
    /// „Zwickau“ in der Adresse steht.
    nonisolated static func matches(_ hit: Hit, region: String) -> Bool {
        let target = normalized(region)
        guard !target.isEmpty else { return false }
        if cityMatches(hit.cityName, region: region) { return true }

        guard let name = hit.name, normalized(name) == target else { return false }
        guard let city = hit.cityName.map(normalized), !city.isEmpty else { return true }
        // Steht der Ort als eigener Teil in der Adresse, ist der Treffer ein Ortsteil davon.
        let parts = (hit.fullAddress ?? "").split(separator: ",").dropFirst().map { normalized(String($0)) }
        return !parts.contains { $0.contains(city) }
    }

    /// „Rioja“ soll auch „La Rioja“ treffen und „Graubünden“ den „Kanton Graubünden“ –
    /// aber nur bei aussagekräftiger Länge.
    private nonisolated static func cityMatches(_ cityName: String?, region: String) -> Bool {
        let target = normalized(region)
        guard let city = cityName.map(normalized), !city.isEmpty, !target.isEmpty else { return false }
        if city == target { return true }
        return target.count >= 4 && (city.contains(target) || (city.count >= 4 && target.contains(city)))
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
