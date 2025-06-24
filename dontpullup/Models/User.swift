import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String
    let zipCode: String
    var fcmToken: String?
    var createdAt: Date
    var lastActive: Date
    
    // Coding keys for Firestore
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case zipCode
        case fcmToken
        case createdAt
        case lastActive
    }
    
    // Primary initializer
    init(id: String, email: String, zipCode: String, fcmToken: String? = nil) {
        self.id = id
        self.email = email
        self.zipCode = zipCode
        self.fcmToken = fcmToken
        self.createdAt = Date()
        self.lastActive = Date()
    }
    
    // Full initializer for Firestore reconstruction
    init(id: String, email: String, zipCode: String, fcmToken: String? = nil, createdAt: Date, lastActive: Date) {
        self.id = id
        self.email = email
        self.zipCode = zipCode
        self.fcmToken = fcmToken
        self.createdAt = createdAt
        self.lastActive = lastActive
    }
    
    // Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id,
            "email": email,
            "zipCode": zipCode,
            "fcmToken": fcmToken as Any,
            "createdAt": Timestamp(date: createdAt),
            "lastActive": Timestamp(date: lastActive)
        ]
    }
    
    // Create from Firestore data
    static func fromFirestoreData(id: String, data: [String: Any]) -> UserProfile? {
        guard let email = data["email"] as? String,
              let zipCode = data["zipCode"] as? String else {
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
        
        // Create UserProfile with full initializer
        let profile = UserProfile(
            id: id,
            email: email,
            zipCode: zipCode,
            fcmToken: fcmToken,
            createdAt: createdAt,
            lastActive: lastActive
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
} 