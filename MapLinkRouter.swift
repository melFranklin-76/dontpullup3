import Foundation
import CoreLocation

enum MapLinkRouter {
    struct ParsedLocation {
        let coordinate: CLLocationCoordinate2D
        let source: String // e.g., "apple-maps", "geo", "custom"
    }

    static func parse(_ url: URL) async -> ParsedLocation? {
        // Accept Apple Maps hosts
        if let host = url.host?.lowercased() {
            if host == "maps.apple.com" || (host == "apple.com" && url.path.lowercased().hasPrefix("/maps")) {
                if let coord = coordinateFromAppleMapsURL(url) {
                    return ParsedLocation(coordinate: coord, source: "apple-maps")
                }
                // Geocode fallback for address-only queries
                if let q = queryValue(named: "q", in: url), let coord = await geocodeIfNeeded(q) {
                    return ParsedLocation(coordinate: coord, source: "apple-maps-geocode")
                }
                if let addr = queryValue(named: "address", in: url), let coord = await geocodeIfNeeded(addr) {
                    return ParsedLocation(coordinate: coord, source: "apple-maps-geocode")
                }
                return nil
            }
        }

        // Accept custom scheme: dontpullup://map?ll=lat,lon
        if url.scheme?.lowercased() == "dontpullup" {
            if let coordString = queryValue(named: "ll", in: url), let coord = parseLatLongString(coordString) {
                return ParsedLocation(coordinate: coord, source: "custom")
            }
            // Also accept center=lat,lon
            if let center = queryValue(named: "center", in: url), let coord = parseLatLongString(center) {
                return ParsedLocation(coordinate: coord, source: "custom")
            }
        }

        // Accept geo:lat,lon?...
        if url.scheme?.lowercased() == "geo" {
            // geo:lat,lon or geo:lat,lon?q=label
            if let coord = coordinateFromGeoURL(url) {
                return ParsedLocation(coordinate: coord, source: "geo")
            }
        }

        return nil
    }

    // MARK: - Apple Maps parsing
    private static func coordinateFromAppleMapsURL(_ url: URL) -> CLLocationCoordinate2D? {
        // Priority order: ll, center, q (if numeric), sll
        if let ll = queryValue(named: "ll", in: url), let c = parseLatLongString(ll) { return c }
        if let center = queryValue(named: "center", in: url), let c = parseLatLongString(center) { return c }
        if let q = queryValue(named: "q", in: url), let c = parseLatLongString(q) { return c }
        if let sll = queryValue(named: "sll", in: url), let c = parseLatLongString(sll) { return c }
        return nil
    }

    // MARK: - geo: parsing
    private static func coordinateFromGeoURL(_ url: URL) -> CLLocationCoordinate2D? {
        // URL like geo:37.3317,-122.0301
        // The absoluteString after "geo:" is the payload
        let absolute = url.absoluteString
        guard let range = absolute.range(of: ":") else { return nil }
        let payload = String(absolute[range.upperBound...])
        // payload might contain ";" or "?" after coords
        let separators: [Character] = ["?", ";"]
        let prefix = payload.split(whereSeparator: { separators.contains($0) }).first.map(String.init) ?? payload
        return parseLatLongString(prefix)
    }

    // MARK: - Helpers
    private static func parseLatLongString(_ s: String) -> CLLocationCoordinate2D? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              abs(lat) <= 90, abs(lon) <= 180
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func queryValue(named name: String, in url: URL) -> String? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name.lowercased() == name.lowercased() })?.value
    }

    private static func geocodeIfNeeded(_ query: String) async -> CLLocationCoordinate2D? {
        // If query looks numeric (lat,lon), we already handled it.
        if parseLatLongString(query) != nil { return nil }
        return await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { placemarks, _ in
                if let loc = placemarks?.first?.location?.coordinate {
                    continuation.resume(returning: loc)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
