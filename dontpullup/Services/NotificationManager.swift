import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private let db = Firestore.firestore()
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
        print("[NotificationManager] Sending notifications for new pin in zip code: \(zipCode)")
        
        // Immediately send a local notification to the current device for testing
        // This ensures notifications work regardless of FCM status
        print("[NotificationManager] Sending immediate local notification for testing")
        let testNotification = createNotificationPayload(for: pin)
        await sendLocalNotification(title: testNotification.title, body: testNotification.body, data: testNotification.data)
        
        do {
            // Get all users in the same zip code with valid FCM tokens
            let usersToNotify = try await getUsersInZipCode(zipCode, excludingUserId: pin.userId)
            
            if usersToNotify.isEmpty {
                print("[NotificationManager] No users to notify in zip code: \(zipCode)")
                // For testing: send a local notification even if no other users
                await sendLocalTestNotification(for: pin)
                return
            }
            
            // Create notification payload
            let notificationData = createNotificationPayload(for: pin)
            
            // Variables to track notification attempts
            var notificationsSent = 0
            var localNotificationsSent = 0
            
            // Send notifications to all users
            for user in usersToNotify {
                if let fcmToken = user.fcmToken, !fcmToken.isEmpty {
                await sendPushNotification(
                    to: fcmToken,
                    title: notificationData.title,
                    body: notificationData.body,
                    data: notificationData.data
                )
                    notificationsSent += 1
                } else {
                    // No FCM token, but still deliver a local notification if this is the current device
                    print("[NotificationManager] User \(user.id) has no FCM token - using local notification as fallback")
                    if Auth.auth().currentUser?.uid == user.id {
                        await sendLocalNotification(
                            title: notificationData.title,
                            body: notificationData.body,
                            data: notificationData.data
                        )
                        localNotificationsSent += 1
                    }
                }
            }
            
            print("[NotificationManager] Notification summary: \(notificationsSent) FCM, \(localNotificationsSent) local notifications sent to \(usersToNotify.count) users in zip code: \(zipCode)")
            
        } catch {
            print("[NotificationManager] Error sending notifications: \(error.localizedDescription)")
        }
    }
    
    /// Gets all users in a specific zip code with valid FCM tokens
    private func getUsersInZipCode(_ zipCode: String, excludingUserId: String) async throws -> [UserProfile] {
        print("[NotificationManager] Searching for users in zip code: \(zipCode), excluding user: \(excludingUserId)")
        
        // Simplified query - only filter by zipCode, handle fcmToken in app logic
        let snapshot = try await db.collection("users")
            .whereField("zipCode", isEqualTo: zipCode)
            .getDocuments()
        
        print("[NotificationManager] Found \(snapshot.documents.count) total users in zip code \(zipCode)")
        
        var users: [UserProfile] = []
        
        for document in snapshot.documents {
            let data = document.data()
            let userId = document.documentID
            
            print("[NotificationManager] Checking user \(userId):")
            print("  - zipCode: \(data["zipCode"] ?? "missing")")
            print("  - email: \(data["email"] ?? "missing")")
            print("  - fcmToken: \(data["fcmToken"] ?? "missing")")
            
            // Skip the user who dropped the pin
            if document.documentID == excludingUserId {
                print("[NotificationManager] Skipping user \(userId) - is the pin creator")
                continue
            }
            
            // TEMPORARY: Allow users without FCM tokens for debugging
            let fcmToken = data["fcmToken"] as? String
            if fcmToken == nil || fcmToken?.isEmpty == true {
                print("[NotificationManager] User \(userId) has no FCM token - but including for debugging")
                // Continue anyway for debugging
            }
            
            if let userProfile = UserProfile.fromFirestoreData(id: document.documentID, data: data) {
                users.append(userProfile)
                print("[NotificationManager] Added user \(userId) to notification list")
            } else {
                print("[NotificationManager] Failed to create UserProfile for user \(userId)")
            }
        }
        
        print("[NotificationManager] Final notification list: \(users.count) users")
        for user in users {
            print("  - User: \(user.id), Email: \(user.email), ZipCode: \(user.zipCode)")
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
    
    /// Sends a push notification using Firebase Cloud Messaging
    private func sendPushNotification(to fcmToken: String, title: String, body: String, data: [String: String]) async {
        // For testing: also send local notification to current device
        await sendLocalNotification(title: title, body: body, data: data)
        
        print("[NotificationManager] Sent local notification instead of FCM:")
        print("  Token: \(fcmToken.prefix(10))...")
        print("  Title: \(title)")
        print("  Body: \(body)")
        print("  Data: \(data)")
        
        // TODO: Implement actual FCM API call through your backend
        // This requires a server key which should never be stored in client code
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