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
  var purchasedZipCodes: [String]  // Individual zip code purchases
  var currentZipCode: String?
  var currentZipUpdatedAt: Date?
  var zipCodeNotifications: [String: Bool]  // Notification preferences per zip code

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
    case purchasedZipCodes
    case currentZipCode
    case currentZipUpdatedAt
    case zipCodeNotifications
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
    self.purchasedZipCodes = []  // Empty array initially
    self.currentZipCode = zipCode
    self.currentZipUpdatedAt = Date()
    self.zipCodeNotifications = [:]  // Start with empty preferences (all enabled by default)
  }

  // Full initializer for Firestore reconstruction
  init(
    id: String, email: String, zipCode: String, fcmToken: String? = nil, createdAt: Date,
    lastActive: Date, isPremium: Bool = false, originalZipCode: String? = nil,
    purchasedZipCodes: [String] = [], currentZipCode: String? = nil,
    currentZipUpdatedAt: Date? = nil, zipCodeNotifications: [String: Bool] = [:]
  ) {
    self.id = id
    self.email = email
    self.zipCode = zipCode
    self.fcmToken = fcmToken
    self.createdAt = createdAt
    self.lastActive = lastActive
    self.isPremium = isPremium
    self.originalZipCode = originalZipCode ?? zipCode
    self.purchasedZipCodes = purchasedZipCodes
    self.currentZipCode = currentZipCode ?? zipCode
    self.currentZipUpdatedAt = currentZipUpdatedAt ?? Date()
    self.zipCodeNotifications = zipCodeNotifications
  }

  // Convert to Firestore data
  func toFirestoreData() -> [String: Any] {
    var data: [String: Any] = [
      "id": id,
      "email": email,
      "zipCode": zipCode,
      "fcmToken": fcmToken as Any,
      "createdAt": Timestamp(date: createdAt),
      "lastActive": Timestamp(date: lastActive),
      "isPremium": isPremium,
      "originalZipCode": originalZipCode,
      "purchasedZipCodes": purchasedZipCodes,
      "zipCodeNotifications": zipCodeNotifications,
    ]
    
    if let currentZipCode = currentZipCode {
      data["currentZipCode"] = currentZipCode
    }
    
    if let currentZipUpdatedAt = currentZipUpdatedAt {
      data["currentZipUpdatedAt"] = Timestamp(date: currentZipUpdatedAt)
    }
    
    return data
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

    // Get premium status, original zip code, and purchased zip codes
    let isPremium = data["isPremium"] as? Bool ?? false
    let originalZipCode = data["originalZipCode"] as? String ?? zipCode
    let purchasedZipCodes = data["purchasedZipCodes"] as? [String] ?? []

    let currentZipCode = data["currentZipCode"] as? String
    let currentZipUpdatedAt: Date?
    if let timestamp = data["currentZipUpdatedAt"] as? Timestamp {
      currentZipUpdatedAt = timestamp.dateValue()
    } else {
      currentZipUpdatedAt = nil
    }

    // Get notification preferences per zip code
    let zipCodeNotifications = data["zipCodeNotifications"] as? [String: Bool] ?? [:]

    print(
      "[UserProfile] Loading from Firestore - isPremium: \(isPremium), originalZipCode: \(originalZipCode), purchasedZipCodes: \(purchasedZipCodes.count)"
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
      originalZipCode: originalZipCode,
      purchasedZipCodes: purchasedZipCodes,
      currentZipCode: currentZipCode,
      currentZipUpdatedAt: currentZipUpdatedAt,
      zipCodeNotifications: zipCodeNotifications
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

  /// Updates the user's current (real-time) zip code based on location
  mutating func updateCurrentZip(_ zip: String) {
    self.currentZipCode = zip
    self.currentZipUpdatedAt = Date()
  }

  /// Checks if notifications are enabled for a specific zip code
  func notificationsEnabled(for zipCode: String) -> Bool {
    return zipCodeNotifications[zipCode] ?? true  // Default to enabled
  }

  /// Sets notification preference for a specific zip code
  mutating func setNotifications(_ enabled: Bool, for zipCode: String) {
    zipCodeNotifications[zipCode] = enabled
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
  
  /// Checks if user has access to a specific zip code
  /// Access is granted if: premium, original zip code, or purchased zip code
  func hasAccessToZipCode(_ zipCode: String) -> Bool {
    // Premium users have access to all zip codes
    if isPremium {
      return true
    }
    
    // Check if it's the original/home zip code
    if zipCode == originalZipCode {
      return true
    }
    
    // Check if user purchased this zip code
    return purchasedZipCodes.contains(zipCode)
  }
  
  /// Returns all zip codes the user has access to (excluding current location)
  var accessibleZipCodes: [String] {
    let zips = [originalZipCode] + purchasedZipCodes
    return Array(Set(zips)).sorted()  // Remove duplicates and sort
  }
}
