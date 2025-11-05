import Foundation
import CoreLocation
import FirebaseFirestore

class PinUploader: ObservableObject {
    @Published var showAlert = false
    @Published var alertMessage = ""

    private let store = Firestore.firestore()

    func dropPin(id: String?, latitude: Double?, longitude: Double?, type: String?, userId: String?, deviceID: String?, zipCode: String?) {
        guard let id = id, !id.isEmpty else {
            showValidationAlert(message: "Pin ID is missing or invalid.")
            return
        }
        guard let lat = latitude, lat >= -90, lat <= 90 else {
            showValidationAlert(message: "Latitude must be a number between -90 and 90.")
            return
        }
        guard let lon = longitude, lon >= -180, lon <= 180 else {
            showValidationAlert(message: "Longitude must be a number between -180 and 180.")
            return
        }
        guard let type = type, ["Verbal", "Physical", "911"].contains(type) else {
            showValidationAlert(message: "Your pin type was invalid. Please select one of: Verbal, Physical, or 911.")
            return
        }
        guard let userId = userId, !userId.isEmpty else {
            showValidationAlert(message: "User ID is missing or invalid.")
            return
        }
        guard let deviceID = deviceID, !deviceID.isEmpty else {
            showValidationAlert(message: "Device ID is missing or invalid.")
            return
        }
        guard let zipCode = zipCode, !zipCode.isEmpty else {
            showValidationAlert(message: "Zip code is missing or invalid.")
            return
        }

        let data: [String: Any] = [
            "id": id,
            "latitude": lat,
            "longitude": lon,
            "type": type,
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp(),
            "deviceID": deviceID,
            "zipCode": zipCode
        ]

        store.collection("pins").document(id).setData(data) { [weak self] error in
            if let error = error as NSError? {
                self?.handleFirestoreError(error)
                return
            }
        }
    }

    func dropPinWithVideo(id: String?, latitude: Double?, longitude: Double?, type: String?, videoURL: String?, userId: String?, deviceID: String?, zipCode: String?) {
        guard let id = id, !id.isEmpty else {
            showValidationAlert(message: "Pin ID is missing or invalid.")
            return
        }
        guard let lat = latitude, lat >= -90, lat <= 90 else {
            showValidationAlert(message: "Latitude must be a number between -90 and 90.")
            return
        }
        guard let lon = longitude, lon >= -180, lon <= 180 else {
            showValidationAlert(message: "Longitude must be a number between -180 and 180.")
            return
        }
        guard let type = type, ["Verbal", "Physical", "911"].contains(type) else {
            showValidationAlert(message: "Your pin type was invalid. Please select one of: Verbal, Physical, or 911.")
            return
        }
        guard let videoURL = videoURL, !videoURL.isEmpty else {
            showValidationAlert(message: "Video URL is missing or invalid.")
            return
        }
        guard let userId = userId, !userId.isEmpty else {
            showValidationAlert(message: "User ID is missing or invalid.")
            return
        }
        guard let deviceID = deviceID, !deviceID.isEmpty else {
            showValidationAlert(message: "Device ID is missing or invalid.")
            return
        }
        guard let zipCode = zipCode, !zipCode.isEmpty else {
            showValidationAlert(message: "Zip code is missing or invalid.")
            return
        }

        let data: [String: Any] = [
            "id": id,
            "latitude": lat,
            "longitude": lon,
            "type": type,
            "videoURL": videoURL,
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp(),
            "deviceID": deviceID,
            "zipCode": zipCode
        ]

        store.collection("pins").document(id).setData(data) { [weak self] error in
            if let error = error as NSError? {
                self?.handleFirestoreError(error)
                return
            }
        }
    }

    func upload(pin: [String: Any]) {
        guard let id = pin["id"] as? String, !id.isEmpty else {
            showValidationAlert(message: "Pin ID is missing or invalid.")
            return
        }
        guard let latitude = pin["latitude"] as? Double, latitude >= -90, latitude <= 90 else {
            showValidationAlert(message: "Latitude must be a number between -90 and 90.")
            return
        }
        guard let longitude = pin["longitude"] as? Double, longitude >= -180, longitude <= 180 else {
            showValidationAlert(message: "Longitude must be a number between -180 and 180.")
            return
        }
        guard let type = pin["type"] as? String, ["Verbal", "Physical", "911"].contains(type) else {
            showValidationAlert(message: "Your pin type was invalid. Please select one of: Verbal, Physical, or 911.")
            return
        }
        guard let userId = pin["userId"] as? String, !userId.isEmpty else {
            showValidationAlert(message: "User ID is missing or invalid.")
            return
        }
        guard let deviceID = pin["deviceID"] as? String, !deviceID.isEmpty else {
            showValidationAlert(message: "Device ID is missing or invalid.")
            return
        }
        guard let zipCode = pin["zipCode"] as? String, !zipCode.isEmpty else {
            showValidationAlert(message: "Zip code is missing or invalid.")
            return
        }
        if let videoURL = pin["videoURL"] {
            guard let videoURLStr = videoURL as? String, !videoURLStr.isEmpty else {
                showValidationAlert(message: "Video URL is invalid.")
                return
            }
        }

        var data = pin
        data["timestamp"] = FieldValue.serverTimestamp()

        store.collection("pins").document(id).setData(data) { [weak self] error in
            if let error = error as NSError? {
                self?.handleFirestoreError(error)
                return
            }
        }
    }

    private func showValidationAlert(message: String) {
        alertMessage = message
        showAlert = true
    }

    private func handleFirestoreError(_ error: NSError) {
        if error.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode(rawValue: error.code) {
            case .permissionDenied:
                alertMessage = "You do not have permission to perform this action."
            case .invalidArgument:
                alertMessage = "Invalid data was provided. Please check all fields and try again."
            case .failedPrecondition:
                alertMessage = "Failed precondition error. Please check your network connection and try again."
            default:
                alertMessage = "An unknown error occurred. Please try again."
            }
        } else {
            alertMessage = "An error occurred: \(error.localizedDescription)"
        }
        showAlert = true
    }
}
