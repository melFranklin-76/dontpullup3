import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import FirebaseFunctions

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let baseURL = "https://fcm.googleapis.com/fcm/send"
    private let presenceFreshnessInterval: TimeInterval = 10 * 60  // 10 minutes window for live presence
    
    private init() {}
    
    /// Sends notification to all users in the same zip code when a pin is dropped
    /// - Parameters:
    ///   - pin: The pin that was dropped
    ///   - zipCode: The zip code to notify users in
    func notifyUsersInZipCode(for pin: Pin, zipCode: String) async {
        print("[NotificationManager] Start notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
        
        do {
            // Get users whose home zip matches and users currently present in the area
            async let homeUsersTask = getUsersInZipCode(zipCode, excludingUserId: pin.userId)
            async let presenceUsersTask = getUsersCurrentlyInZipCode(zipCode, excludingUserId: pin.userId)
            let (homeUsers, presenceUsers) = try await (homeUsersTask, presenceUsersTask)
            
            var combinedUsers: [String: UserProfile] = [:]
            homeUsers.forEach { combinedUsers[$0.id] = $0 }
            presenceUsers.forEach { combinedUsers[$0.id] = $0 }
            let allUsers = Array(combinedUsers.values)

            // Filter users based on their notification preferences for this zip code
            var usersToNotify = [UserProfile]()
            for user in allUsers {
                guard user.notificationsEnabled(for: zipCode) else {
                    print("[NotificationManager] User \(user.id) has notifications disabled for zip code \(zipCode) - skipping")
                    continue
                }
                
                if user.hasAccessToZipCode(zipCode) || user.currentZipCode == zipCode {
                    usersToNotify.append(user)
                    print("[NotificationManager] User \(user.id) eligible for zip \(zipCode) (access: \(user.hasAccessToZipCode(zipCode)), currentZip: \(user.currentZipCode ?? "nil"))")
                } else {
                    print("[NotificationManager] User \(user.id) does not have access or presence in zip \(zipCode) - skipping")
                }
            }
            
            // Detailed log of users and their FCM token status
            print("[NotificationManager] Users fetched for notification:")
            for user in usersToNotify {
                if let token = user.fcmToken, !token.isEmpty {
                    print("  - User ID: \(user.id), Email: \(user.email), FCM Token: valid")
                } else {
                    print("  - User ID: \(user.id), Email: \(user.email), FCM Token: MISSING or EMPTY - user will be skipped for push notification")
                }
            }
            
            if usersToNotify.isEmpty {
                print("[NotificationManager] No users to notify in zip code: \(zipCode)")
                print("[NotificationManager] Finished notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
                return
            }
            
            // Collect all valid FCM tokens for production push notification
            var tokenToUserId: [String: String] = [:]
            for user in usersToNotify {
                if let token = user.fcmToken, !token.isEmpty {
                    tokenToUserId[token] = user.id
                }
            }
            let recipientTokens = Array(tokenToUserId.keys)
            
            print("[NotificationManager] Collected recipient FCM tokens: \(recipientTokens)")
            
            if recipientTokens.isEmpty {
                print("[NotificationManager] No valid FCM tokens found among users to notify in zip code: \(zipCode)")
                print("[NotificationManager] Finished notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
                return
            }
            
            // Create notification payload
            let notificationData = createNotificationPayload(for: pin)
            
            // PRODUCTION PUSH NOTIFICATION: send via Cloud Function to all recipients
            await sendPushNotification(
                to: recipientTokens,
                tokenToUserId: tokenToUserId,
                title: notificationData.title,
                body: notificationData.body,
                data: notificationData.data
            )
            
            print("[NotificationManager] Finished notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
            
        } catch {
            print("[NotificationManager] Error sending notifications for pin ID: \(pin.id) in zip code: \(zipCode): \(error.localizedDescription)")
        }
    }
    
    /// Gets all users in a specific zip code with valid FCM tokens
    private func getUsersInZipCode(_ zipCode: String, excludingUserId: String) async throws -> [UserProfile] {
        print("[NotificationManager] Searching for users in zip code: \(zipCode), excluding user: \(excludingUserId)")
        
        var snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("users")
                .whereField("zipCode", isEqualTo: zipCode)
                .getDocuments()
        } catch {
            print("[NotificationManager] Firestore error fetching users in zip code \(zipCode): \(error.localizedDescription)")
            throw error
        }
        
        print("[NotificationManager] Found \(snapshot.documents.count) total users in zip code \(zipCode)")
        
        var users: [UserProfile] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let userId = document.documentID
            
            // Skip the user who dropped the pin
            if userId == excludingUserId {
                print("[NotificationManager] Skipped user \(userId) - is the pin creator")
                continue
            }
            
            // Check FCM token presence
            let fcmToken = data["fcmToken"] as? String
            if fcmToken == nil || fcmToken?.isEmpty == true {
                print("[NotificationManager] Skipped user \(userId) - missing or empty FCM token")
                continue
            }
            
            if let userProfile = UserProfile.fromFirestoreData(id: userId, data: data) {
                users.append(userProfile)
                print("[NotificationManager] Added user \(userId) to notification list (valid FCM token)")
            } else {
                print("[NotificationManager] Failed to create UserProfile for user \(userId)")
            }
        }
        
        print("[NotificationManager] Final notification list: \(users.count) users")
        for user in users {
            print("  - User: \(user.id), Email: \(user.email), ZipCode: \(user.zipCode), FCM Token valid")
        }
        
        return users
    }
  
  /// Gets users who are currently within a specific zip code based on live location updates
  private func getUsersCurrentlyInZipCode(_ zipCode: String, excludingUserId: String) async throws -> [UserProfile] {
    print("[NotificationManager] Searching for users currently in zip code: \(zipCode), excluding user: \(excludingUserId)")
    
    let snapshot = try await db.collection("users")
      .whereField("currentZipCode", isEqualTo: zipCode)
      .getDocuments()
    
    let freshnessCutoff = Date().addingTimeInterval(-presenceFreshnessInterval)
    var users: [UserProfile] = []
    
    for document in snapshot.documents {
      let data = document.data()
      let userId = document.documentID
      
      if userId == excludingUserId {
        continue
      }
      
      guard let fcmToken = data["fcmToken"] as? String, !fcmToken.isEmpty else {
        continue
      }
      
      if let timestamp = data["currentZipUpdatedAt"] as? Timestamp {
        let updatedAt = timestamp.dateValue()
        if updatedAt < freshnessCutoff {
          continue
        }
      } else {
        continue
      }
      
      if let userProfile = UserProfile.fromFirestoreData(id: userId, data: data) {
        users.append(userProfile)
      }
    }
    
    print("[NotificationManager] Found \(users.count) presence-based users in zip code \(zipCode)")
    return users
  }
    
    /// Creates notification payload for a pin
    private func createNotificationPayload(for pin: Pin) -> (title: String, body: String, data: [String: String]) {
        let title = "Incident Nearby"
        let body = "\(pin.incidentType.title) reported nearby in your area."
        
        let data = [
            "pinId": pin.id,
            "incidentType": pin.incidentType.rawValue,
            "latitude": String(pin.coordinate.latitude),
            "longitude": String(pin.coordinate.longitude),
            "type": "new_pin"
        ]
        
        return (title: title, body: body, data: data)
    }
    
    /// Sends a push notification using Firebase Cloud Functions
    /// - Parameters:
    ///   - tokens: The array of FCM tokens to send the notification to
    ///   - title: Notification title
    ///   - body: Notification body
    ///   - data: Additional data payload
    private func sendPushNotification(
        to tokens: [String],
        tokenToUserId: [String: String],
        title: String,
        body: String,
        data: [String: String]
    ) async {
        print("[NotificationManager] 🚀 Calling Cloud Function to notify \(tokens.count) OTHER users")
        print("[NotificationManager] 📝 Title: \(title)")
        print("[NotificationManager] 📝 Body: \(body)")
        
        let payloadDict: [String: Any] = [
            "tokens": tokens,
            "title": title,
            "body": body,
            "data": data,
            "tokenOwners": tokenToUserId
        ]
        
        do {
            print("[NotificationManager] 🔄 Calling 'sendIncidentNotification'...")
            let result = try await functions.httpsCallable("sendIncidentNotification").call(payloadDict)
            print("[NotificationManager] ✅ SUCCESS! Cloud Function returned")
            print("[NotificationManager] 📊 Result: \(result.data)")
            
            if let resultDict = result.data as? [String: Any] {
                if let successCount = resultDict["successCount"] as? Int {
                    print("[NotificationManager] 📤 Sent to \(successCount) device(s)")
                }
                if let failureCount = resultDict["failureCount"] as? Int,
                   failureCount > 0,
                   let responses = resultDict["responses"] as? [[String: Any]] {
                    print("[NotificationManager] ⚠️ Failed: \(failureCount) device(s)")
                    await handleFailedTokens(responses: responses, tokenToUserId: tokenToUserId)
                    
                    if failureCount == tokens.count {
                        await sendLocalTestNotification(forFailedPushWithTitle: title, body: body, data: data)
                    }
                }
            }
        } catch let error as NSError {
            print("[NotificationManager] ❌ Cloud Function ERROR:")
            print("[NotificationManager]   Code: \(error.code)")
            print("[NotificationManager]   Domain: \(error.domain)")
            print("[NotificationManager]   Description: \(error.localizedDescription)")
        } catch {
            print("[NotificationManager] ❌ Unknown error: \(error.localizedDescription)")
        }
    }

    private func handleFailedTokens(responses: [[String: Any]], tokenToUserId: [String: String]) async {
        var tokensToRemove: [(token: String, userId: String)] = []
        
        for (index, response) in responses.enumerated() {
            guard index < tokenToUserId.keys.count else { continue }

            if let success = response["success"] as? Int, success == 1 {
                continue
            }
            
            if let errorMessage = response["error"] as? String,
               errorMessage == "Requested entity was not found." {
                let token = Array(tokenToUserId.keys)[index]
                if let userId = tokenToUserId[token] {
                    tokensToRemove.append((token, userId))
                }
            }
        }
        
        guard !tokensToRemove.isEmpty else { return }
        
        do {
            for entry in tokensToRemove {
                try await db.collection("users").document(entry.userId).updateData([
                    "fcmToken": FieldValue.delete()
                ])
                print("[NotificationManager] Removed stale FCM token for user \(entry.userId)")
            }
        } catch {
            print("[NotificationManager] Error removing stale tokens: \(error.localizedDescription)")
        }
    }
    
    private func sendLocalTestNotification(forFailedPushWithTitle title: String, body: String, data: [String: String]) async {
        print("[NotificationManager] All push attempts failed. Sending fallback local notification.")
        await sendLocalNotification(title: title, body: body, data: data)
    }
    
    /// Sends a local notification for testing when no other users exist
    private func sendLocalTestNotification(for pin: Pin) async {
        let title = "Test: Pin Created"
        let body = "Your \(pin.incidentType.title) pin was created successfully. (This is a test notification since no other users are in your zip code)"
        
        await sendLocalNotification(title: title, body: body, data: [
            "pinId": pin.id,
            "incidentType": pin.incidentType.rawValue,
            "type": "test_notification"
        ])
        
        print("[NotificationManager] Sent test notification for pin \(pin.id)")
    }
    
    /// Sends an actual local notification to this device
    private func sendLocalNotification(title: String, body: String, data: [String: String]) async {
        // First check current notification permission status
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        if settings.authorizationStatus != .authorized {
            print("[NotificationManager] Cannot send notification - permission not granted (status: \(settings.authorizationStatus.rawValue))")
            
            // Try to request permissions again
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                print("[NotificationManager] Re-requested notification permissions: \(granted ? "granted" : "denied")")
                
                if !granted {
                    return // Exit if permissions still denied
                }
            } catch {
                print("[NotificationManager] Error requesting notification permissions: \(error.localizedDescription)")
                return
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = data
        
        // Create trigger to fire immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create request
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add the request
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[NotificationManager] Local notification scheduled: \(title)")
            
            // Schedule a second notification in 3 seconds if this is a testing notification
            // to help verify that notifications are working properly
            if data["type"] == "test_notification" {
                let followUpContent = UNMutableNotificationContent()
                followUpContent.title = "Notification Test Confirmation"
                followUpContent.body = "This follow-up confirms notifications are working on your device."
                followUpContent.sound = .default
                
                let followUpTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
                let followUpRequest = UNNotificationRequest(identifier: UUID().uuidString, content: followUpContent, trigger: followUpTrigger)
                
                try await UNUserNotificationCenter.current().add(followUpRequest)
                print("[NotificationManager] Follow-up test notification scheduled")
            }
        } catch {
            print("[NotificationManager] Error scheduling local notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Payload Model
struct NotificationPayload {
    let to: String
    let notification: NotificationContent
    let data: [String: String]
    
    struct NotificationContent {
        let title: String
        let body: String
        let sound: String = "default"
    }
}

// MARK: - Helper Extensions
extension IncidentType {
    var notificationTitle: String {
        switch self {
        case .verbal:
            return "Verbal Incident"
        case .physical:
            return "Physical Incident"
        case .emergency:
            return "Emergency"
        case .ice:
            return "ICE Agents Reported"
        }
    }
} 
