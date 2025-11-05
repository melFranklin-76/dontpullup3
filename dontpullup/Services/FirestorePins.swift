import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit

/// Utility class for Firestore pin operations
enum FirestorePins {

  private static let db = Firestore.firestore()

  /// Adds a pin to Firestore
  /// - Parameters:
  ///   - id: The pin ID
  ///   - coord: The coordinates of the pin
  ///   - type: The incident type
  ///   - videoURL: The remote video URL (if any)
  /// - Throws: Error if the operation fails
  static func addPin(
    id: String, coord: CLLocationCoordinate2D, type: IncidentType, videoURL: String
  ) async throws {
    // Accessing Auth and UIDevice is MainActor-isolated in recent SDKs, so grab
    // those values explicitly on the main thread to avoid the
    // "Expression is 'async' but is not marked with 'await'" error.
    let uid: String = await MainActor.run {
      Auth.auth().currentUser?.uid ?? ""
    }
    let deviceID: String = await MainActor.run {
      UIDevice.current.identifierForVendor?.uuidString ?? ""
    }

    let data: [String: Any] = [
      "latitude": coord.latitude,
      "longitude": coord.longitude,
      "type": type.firestoreType,  // Ensures we use Verbal, Physical, 911
      "videoURL": videoURL,
      "userId": uid,
      "timestamp": Timestamp(),
      "deviceID": deviceID,
    ]

    try await db.collection("pins").document(id).setData(data)
  }

  /// Deletes a pin from Firestore
  /// - Parameter id: The ID of the pin to delete
  /// - Throws: Error if the operation fails
  static func deletePin(id: String) async throws {
    try await db.collection("pins").document(id).delete()
  }

  /// Retrieves all pins from Firestore
  /// - Returns: Array of Pin objects
  /// - Throws: Error if the operation fails
  /// - Note: Deprecated - use getPinsInRegion instead for better performance
  static func getAllPins() async throws -> [Pin] {
    let snapshot = try await db.collection("pins")
      .limit(to: 1000)  // Add limit to prevent loading too many pins
      .getDocuments()

    return snapshot.documents.compactMap { document in
      guard let latitude = document.data()["latitude"] as? Double,
        let longitude = document.data()["longitude"] as? Double,
        let typeString = document.data()["type"] as? String,
        let videoURL = document.data()["videoURL"] as? String,
        let userId = document.data()["userId"] as? String
      else {
        return nil
      }

      let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      let incidentType = IncidentType.fromFirestoreType(typeString)  // Use correct method

      return Pin(
        id: document.documentID,
        coordinate: coordinate,
        incidentType: incidentType,
        videoURL: videoURL,
        userId: userId
      )
    }
  }
  
  /// Retrieves pins within a geographic region
  /// - Parameters:
  ///   - center: Center coordinate of the region
  ///   - radiusKm: Radius in kilometers (default: 50km = ~31 miles)
  ///   - limit: Maximum number of pins to return (default: 500)
  /// - Returns: Array of Pin objects within the region
  /// - Throws: Error if the operation fails
  /// 
  /// Note: Firestore doesn't support direct bounding box queries, so we use latitude/longitude ranges.
  /// For better geographic queries, consider using GeoFirestore library.
  static func getPinsInRegion(
    center: CLLocationCoordinate2D,
    radiusKm: Double = 50.0,
    limit: Int = 500
  ) async throws -> [Pin] {
    // Calculate approximate bounds (1 degree latitude ≈ 111 km)
    let latDelta = radiusKm / 111.0
    let lonDelta = radiusKm / (111.0 * cos(center.latitude * .pi / 180.0))
    
    let minLat = center.latitude - latDelta
    let maxLat = center.latitude + latDelta
    let minLon = center.longitude - lonDelta
    let maxLon = center.longitude + lonDelta
    
    print("[FirestorePins] Querying pins in region: lat [\(minLat), \(maxLat)], lon [\(minLon), \(maxLon)]")
    
    // Firestore compound queries - query by latitude range first
    // Note: We can't query both lat AND lon in one query efficiently, so we:
    // 1. Query by latitude range (most efficient)
    // 2. Filter by longitude client-side (small performance cost, but necessary)
    
    let query = db.collection("pins")
      .whereField("latitude", isGreaterThan: minLat)
      .whereField("latitude", isLessThan: maxLat)
      .limit(to: limit)
    
    let snapshot = try await query.getDocuments()
    
    // Filter by longitude client-side and calculate distance
    let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
    
    return snapshot.documents.compactMap { document -> Pin? in
      let data = document.data()
      
      guard let latitude = data["latitude"] as? Double,
        let longitude = data["longitude"] as? Double,
        let typeString = data["type"] as? String,
        let videoURL = data["videoURL"] as? String,
        let userId = data["userId"] as? String
      else {
        return nil
      }
      
      // Filter by longitude bounds
      guard longitude >= minLon && longitude <= maxLon else {
        return nil
      }
      
      // Calculate actual distance to filter by radius
      let pinLocation = CLLocation(latitude: latitude, longitude: longitude)
      let distanceKm = centerLocation.distance(from: pinLocation) / 1000.0
      
      guard distanceKm <= radiusKm else {
        return nil
      }
      
      let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      let incidentType = IncidentType.fromFirestoreType(typeString)
      let zipCode = data["zipCode"] as? String ?? ""
      
      return Pin(
        id: document.documentID,
        coordinate: coordinate,
        incidentType: incidentType,
        videoURL: videoURL,
        userId: userId,
        zipCode: zipCode
      )
    }
  }

  /// Method to update a pin's video URL
  static func updatePinVideoURL(pinId: String, videoURL: String) async throws {
    let db = Firestore.firestore()
    try await db.collection("pins").document(pinId).updateData([
      "videoURL": videoURL
    ])
    print("[FirestorePins] Updated pin \(pinId) with video URL: \(videoURL)")
  }
}
