import Foundation
import MapKit
import CoreLocation
import FirebaseAuth

struct PinDraft {
    var coordinate: CLLocationCoordinate2D
    var incidentType: IncidentType
    var videoURL: URL?
    var zipCode: String = ""
    
    init(coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0),
         incidentType: IncidentType = .verbal,
         videoURL: URL? = nil,
         zipCode: String = "") {
        self.coordinate = coordinate
        self.incidentType = incidentType
        self.videoURL = videoURL
        self.zipCode = zipCode
    }
    
    func makePin(id: String, remote: String) -> Pin {
        return Pin(
            id: id,
            coordinate: coordinate,
            incidentType: incidentType,
            videoURL: remote,
            userId: Auth.auth().currentUser?.uid ?? "",
            zipCode: zipCode
        )
    }
} 