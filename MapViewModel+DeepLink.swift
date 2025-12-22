import MapKit

extension MapViewModel {
    @MainActor
    func centerOn(coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance = 61) {
        // ~200 ft = ~61 meters; convert meters to a small span
        var spanDelta = (radiusMeters * 1.5) / 111_000.0
        if spanDelta.isNaN || spanDelta.isInfinite || spanDelta <= 0 { spanDelta = 0.001 }

        let region = MKCoordinateRegion(
            center: sanitizeCoordinate(coordinate),
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )
        self.region = region
        self.mapRegion = region
        self.refreshPinsForCurrentRegion()
    }
}
