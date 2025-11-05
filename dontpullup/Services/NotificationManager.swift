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
    
    private init() {
        // Request notification permissions on init
        requestNotificationPermissions()
    }
    
    /// Request notification permissions
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("[NotificationManager] Notification permissions granted")
            } else {
                print("[NotificationManager] Notification permissions denied: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    /// Sends notification to all users in the same zip code when a pin is dropped
    /// - Parameters:
    ///   - pin: The pin that was dropped
    ///   - zipCode: The zip code to notify users in
    func notifyUsersInZipCode(for pin: Pin, zipCode: String) async {
        print("[NotificationManager] Start notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
        
        // Immediately send a local notification to the current device for testing/dev feedback
        print("[NotificationManager] Sending immediate local notification for testing")
        let testNotification = createNotificationPayload(for: pin)
        await sendLocalNotification(title: testNotification.title, body: testNotification.body, data: testNotification.data)
        
        do {
            // Get all users in the same zip code
            let usersToNotify = try await getUsersInZipCode(zipCode, excludingUserId: pin.userId)
            
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
                // For testing: send a local notification even if no other users
                await sendLocalTestNotification(for: pin)
                print("[NotificationManager] Finished notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
                return
            }
            
            // Collect all valid FCM tokens for production push notification
            let recipientTokens = usersToNotify.compactMap { user -> String? in
                guard let token = user.fcmToken, !token.isEmpty else {
                    return nil
                }
                return token
            }
            
            print("[NotificationManager] Collected recipient FCM tokens: \(recipientTokens)")
            
            if recipientTokens.isEmpty {
                print("[NotificationManager] No valid FCM tokens found among users to notify in zip code: \(zipCode)")
                // No real push notifications can be sent, only local dev notifications on current device
                await sendLocalTestNotification(for: pin)
                print("[NotificationManager] Finished notifying users for pin ID: \(pin.id) in zip code: \(zipCode)")
                return
            }
            
            // Create notification payload
            let notificationData = createNotificationPayload(for: pin)
            
            // PRODUCTION PUSH NOTIFICATION: send via Cloud Function to all recipients
            await sendPushNotification(
                to: recipientTokens,
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
    private func sendPushNotification(to tokens: [String], title: String, body: String, data: [String: String]) async {
        // PRODUCTION PUSH: send notification via Cloud Function
        let payload: [String: Any] = [
            "tokens": tokens,
            "title": title,
            "body": body,
            "data": data
        ]
        
        do {
            let result = try await functions.httpsCallable("sendIncidentNotification").call(payload)
            // Ideally result.data would contain info about success/failure counts
            print("[NotificationManager] Cloud Function sendIncidentNotification called successfully. Attempted to send to \(tokens.count) tokens. Result: \(result.data)")
        } catch {
            print("[NotificationManager] Error calling Cloud Function sendIncidentNotification: \(error.localizedDescription)")
        }
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
        }
    }
} 
