import CoreLocation
import MapKit
import SwiftUI

/// Zeigt die Herkunft des Weins als kleinen Kartenausschnitt mit Stecknadel.
///
/// Die Koordinaten kommen aus der Region auf dem Etikett und werden beim ersten
/// Anzeigen einmalig ermittelt und am Wein gespeichert. Gibt es keine Region oder
/// findet der Geocoder nichts, wird die Karte einfach weggelassen.
struct WineOriginMapView: View {

    @ObservedObject var wine: Wine
    @State private var isLookingUp = false

    /// Ausschnitt so weit, dass das Land ringsum erkennbar bleibt.
    private static let placeSpanMeters: CLLocationDistance = 600_000
    /// Nur das Land bekannt: weiter herauszoomen, damit es ganz zu sehen ist.
    private static let countrySpanMeters: CLLocationDistance = 900_000

    var body: some View {
        // Bewusst kein leerer Group: an einer EmptyView wird `.task` nicht ausgeführt,
        // dann würde das Geocoding nie starten.
        VStack(spacing: 0) {
            if let coordinate {
                content(for: coordinate)
            } else if isLookingUp {
                placeholder
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: "\(wine.region)|\(wine.country)") { await lookupIfNeeded() }
    }

    private var coordinate: CLLocationCoordinate2D? { wine.coordinate }

    // MARK: Karte

    private func content(for coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Herkunft")
                    .font(.headline)
                Spacer()
                Button {
                    openInMaps(coordinate)
                } label: {
                    Label("In Karten öffnen", systemImage: "arrow.up.forward.app")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleOnly)
                }
            }

            Map(initialPosition: .region(region(for: coordinate)), interactionModes: []) {
                // Ohne genauen Treffer keine Stecknadel – sie würde einen Ort vortäuschen,
                // der so nicht belegt ist.
                if wine.hasPreciseOrigin {
                    Marker(wine.region.isEmpty ? wine.name : wine.region, systemImage: "wineglass.fill", coordinate: coordinate)
                        .tint(wine.type.color)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.medium, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel("Karte der Herkunft: \(wine.geocodedPlaceName.isEmpty ? wine.region : wine.geocodedPlaceName)")

            let place = wine.geocodedPlaceName
            if !place.isEmpty {
                Label {
                    if wine.hasPreciseOrigin {
                        Text(place)
                    } else {
                        Text("\(place) · Region nicht genau gefunden")
                    }
                } icon: {
                    Image(systemName: wine.hasPreciseOrigin ? "mappin.and.ellipse" : "globe.europe.africa")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture { openInMaps(coordinate) }
    }

    private var placeholder: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Herkunft wird gesucht …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .cardStyle()
    }

    private func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let span = wine.hasPreciseOrigin ? Self.placeSpanMeters : Self.countrySpanMeters
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = wine.geocodedPlaceName.isEmpty ? wine.region : wine.geocodedPlaceName
        item.openInMaps()
    }

    // MARK: Geocoding

    private func lookupIfNeeded() async {
        guard let query = RegionGeocoder.query(region: wine.region, country: wine.country) else {
            wine.applyGeocode(nil, for: "")
            return
        }
        // Deckt beides ab: noch nie gesucht und Region seither geändert.
        guard wine.needsGeocoding else { return }

        isLookingUp = true
        defer { isLookingUp = false }
        let result = await RegionGeocoder.shared.lookup(region: wine.region, country: wine.country)
        wine.applyGeocode(result, for: query)
    }
}

#Preview {
    ScrollView {
        WineOriginMapView(wine: PreviewData.sampleWines[2])
            .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environment(\.managedObjectContext, PreviewData.context)
}
