import FirebaseFirestore
import Foundation

struct UserProfile: Codable, Identifiable {
  let id: String
  let email: String
  let zipCode: String
  var fcmToken: String?
  var createdAt: Date
  var lastActive: Date
  var isPremium: Bool
  var originalZipCode: String

  // Coding keys for Firestore
  enum CodingKeys: String, CodingKey {
    case id
    case email
    case zipCode
    case fcmToken
    case createdAt
    case lastActive
    case isPremium
    case originalZipCode
  }

  // Primary initializer
  init(id: String, email: String, zipCode: String, fcmToken: String? = nil) {
    self.id = id
    self.email = email
    self.zipCode = zipCode
    self.originalZipCode = zipCode
    self.fcmToken = fcmToken
    self.createdAt = Date()
    self.lastActive = Date()
    self.isPremium = false
  }

  // Full initializer for Firestore reconstruction
  init(
    id: String, email: String, zipCode: String, fcmToken: String? = nil, createdAt: Date,
    lastActive: Date, isPremium: Bool = false, originalZipCode: String? = nil
  ) {
    self.id = id
    self.email = email
    self.zipCode = zipCode
    self.fcmToken = fcmToken
    self.createdAt = createdAt
    self.lastActive = lastActive
    self.isPremium = isPremium
    self.originalZipCode = originalZipCode ?? zipCode
  }

  // Convert to Firestore data
  func toFirestoreData() -> [String: Any] {
    return [
      "id": id,
      "email": email,
      "zipCode": zipCode,
      "fcmToken": fcmToken as Any,
      "createdAt": Timestamp(date: createdAt),
      "lastActive": Timestamp(date: lastActive),
      "isPremium": isPremium,
      "originalZipCode": originalZipCode,
    ]
  }

  // Create from Firestore data
  static func fromFirestoreData(id: String, data: [String: Any]) -> UserProfile? {
    guard let email = data["email"] as? String,
      let zipCode = data["zipCode"] as? String
    else {
      print("[UserProfile] Missing required fields in Firestore data")
      return nil
    }

    let fcmToken = data["fcmToken"] as? String

    let createdAt: Date
    if let timestamp = data["createdAt"] as? Timestamp {
      createdAt = timestamp.dateValue()
    } else {
      createdAt = Date()
    }

    let lastActive: Date
    if let timestamp = data["lastActive"] as? Timestamp {
      lastActive = timestamp.dateValue()
    } else {
      lastActive = Date()
    }

    // Get premium status and original zip code
    let isPremium = data["isPremium"] as? Bool ?? false
    let originalZipCode = data["originalZipCode"] as? String ?? zipCode

    print(
      "[UserProfile] Loading from Firestore - isPremium: \(isPremium), originalZipCode: \(originalZipCode)"
    )

    // Create UserProfile with full initializer
    let profile = UserProfile(
      id: id,
      email: email,
      zipCode: zipCode,
      fcmToken: fcmToken,
      createdAt: createdAt,
      lastActive: lastActive,
      isPremium: isPremium,
      originalZipCode: originalZipCode
    )
    return profile
  }
}

// Helper extension for UserProfile
extension UserProfile {
  /// Updates the FCM token for push notifications
  mutating func updateFCMToken(_ token: String) {
    self.fcmToken = token
  }

  /// Updates the last active timestamp
  mutating func updateLastActive() {
    self.lastActive = Date()
  }

  /// Checks if user can change to a specific zip code based on premium status
  func canChangeToZipCode(_ newZipCode: String) -> Bool {
    // Premium users can change to any zip code
    if isPremium {
      return true
    }

    // Non-premium users can only use their original zip code
    return newZipCode == originalZipCode
  }
}
