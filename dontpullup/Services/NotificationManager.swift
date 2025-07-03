import FirebaseAuth
import FirebaseFirestore
import Foundation
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
  static let shared = NotificationManager()

  private let db = Firestore.firestore()

  // Track which incident types have been notified in each zip code
  // Format: [zipCode: [incidentType: lastNotificationTimestamp]]
  private var recentNotifications: [String: [String: Date]] = [:]

  // Time window to prevent duplicate notifications (in hours)
  private let notificationCooldown: TimeInterval = 3600 * 4  // 4 hours

  private init() {
    // Request notification permissions on init
    requestNotificationPermissions()
  }

  /// Request notification permissions
  private func requestNotificationPermissions() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      granted, error in
      if granted {
        print("[NotificationManager] Notification permissions granted")
      } else {
        print(
          "[NotificationManager] Notification permissions denied: \(error?.localizedDescription ?? "Unknown error")"
        )
      }
    }
  }

  /// Sends notification to all users in the same zip code when a pin is dropped
  /// - Parameters:
  ///   - pin: The pin that was dropped
  ///   - zipCode: The zip code to notify users in
  func notifyUsersInZipCode(for pin: Pin, zipCode: String) async {
    print(
      "[NotificationManager] Checking if notification should be sent for \(pin.incidentType.rawValue) in zip code: \(zipCode)"
    )

    // Skip notifications if the zip code is empty
    guard !zipCode.isEmpty else {
      print("[NotificationManager] Cannot send notification - empty zip code")
      return
    }

    // Check if we've recently sent a notification for this incident type in this zip code
    let incidentTypeKey = pin.incidentType.rawValue
    let now = Date()

    if let zipNotifications = recentNotifications[zipCode],
      let lastNotificationTime = zipNotifications[incidentTypeKey],
      now.timeIntervalSince(lastNotificationTime) < notificationCooldown
    {

      // Calculate how long ago the last notification was sent
      let minutesAgo = now.timeIntervalSince(lastNotificationTime) / 60
      print(
        "[NotificationManager] Skipping notification - already sent a \(pin.incidentType.title) notification in zip code \(zipCode) \(Int(minutesAgo)) minutes ago"
      )
      return
    }

    // Update the notification timestamp for this incident type in this zip code
    if recentNotifications[zipCode] == nil {
      recentNotifications[zipCode] = [:]
    }
    recentNotifications[zipCode]?[incidentTypeKey] = now

    print(
      "[NotificationManager] Sending notifications for \(pin.incidentType.title) in zip code: \(zipCode)"
    )

    do {
      // Get all users in the same zip code with valid FCM tokens
      let usersToNotify = try await getUsersInZipCode(zipCode, excludingUserId: pin.userId)

      if usersToNotify.isEmpty {
        print("[NotificationManager] No users to notify in zip code: \(zipCode)")
        return
      }

      // Create notification payload
      let notificationData = createNotificationPayload(for: pin)

      // Send batch notification through backend
      await sendBatchNotification(
        users: usersToNotify,
        title: notificationData.title,
        body: notificationData.body,
        data: notificationData.data,
        zipCode: zipCode
      )

    } catch {
      print("[NotificationManager] Error sending notifications: \(error.localizedDescription)")
    }
  }

  /// Sends notifications to users
  private func sendBatchNotification(
    users: [UserProfile],
    title: String,
    body: String,
    data: [String: String],
    zipCode: String
  ) async {
    // Extract FCM tokens from users
    let fcmTokens = users.compactMap { $0.fcmToken }.filter { !$0.isEmpty }

    guard !fcmTokens.isEmpty else {
      print("[NotificationManager] No valid FCM tokens to send notifications")
      return
    }

    // Variables to track notification attempts
    var notificationsSent = 0
    var localNotificationsSent = 0

    // Send notifications to all users
    for user in users {
      if let fcmToken = user.fcmToken, !fcmToken.isEmpty {
        // In production, Firebase will handle FCM notifications automatically
        // through Firebase Cloud Messaging when the pin is added to Firestore
        // We're just logging here for debugging purposes
        print(
          "[NotificationManager] FCM notification will be sent to token: \(fcmToken.prefix(10))...")
        print("  Title: \(title)")
        print("  Body: \(body)")
        notificationsSent += 1

        // Send local notification to ALL users in the same zip code for immediate feedback
        print("[NotificationManager] Sending local notification for user \(user.id)")
        await sendLocalNotification(title: title, body: body, data: data)
        localNotificationsSent += 1
      } else {
        // No FCM token, but still deliver a local notification
        print(
          "[NotificationManager] User \(user.id) has no FCM token - sending local notification as fallback"
        )
        await sendLocalNotification(title: title, body: body, data: data)
        localNotificationsSent += 1
      }
    }

    print(
      "[NotificationManager] Notification summary: \(notificationsSent) FCM, \(localNotificationsSent) local notifications sent to \(users.count) users in zip code: \(zipCode)"
    )
  }

  /// Gets all users in a specific zip code with valid FCM tokens
  private func getUsersInZipCode(_ zipCode: String, excludingUserId: String) async throws
    -> [UserProfile]
  {
    print(
      "[NotificationManager] Searching for users in zip code: \(zipCode), excluding user: \(excludingUserId)"
    )

    // Simplified query - only filter by zipCode, handle fcmToken in app logic
    let snapshot = try await db.collection("users")
      .whereField("zipCode", isEqualTo: zipCode)
      .getDocuments()

    print(
      "[NotificationManager] Found \(snapshot.documents.count) total users in zip code \(zipCode)")
    print("[NotificationManager] Raw query result: \(snapshot.documents.map { $0.documentID })")

    var users: [UserProfile] = []

    for document in snapshot.documents {
      let data = document.data()
      let userId = document.documentID

      // Skip the user who dropped the pin
      if document.documentID == excludingUserId {
        print("[NotificationManager] Skipping user \(userId) - is the pin creator")
        continue
      }

      // Only include users with valid FCM tokens for production
      let fcmToken = data["fcmToken"] as? String
      if fcmToken == nil || fcmToken?.isEmpty == true {
        print("[NotificationManager] Skipping user \(userId) - no valid FCM token")
        continue
      }

      if let userProfile = UserProfile.fromFirestoreData(id: document.documentID, data: data) {
        users.append(userProfile)
        print("[NotificationManager] Added user \(userId) to notification list")
        print(
          "[NotificationManager] User details - Email: \(userProfile.email), FCM Token: \(userProfile.fcmToken?.prefix(10) ?? "none")..."
        )
      } else {
        print("[NotificationManager] Failed to create UserProfile for user \(userId)")
      }
    }

    print("[NotificationManager] Final notification list: \(users.count) users")
    return users
  }

  /// Creates notification payload for a pin
  private func createNotificationPayload(for pin: Pin) -> (
    title: String, body: String, data: [String: String]
  ) {
    let title = "Incident Nearby"
    let body = "\(pin.incidentType.title) reported nearby in your area."

    let data = [
      "pinId": pin.id,
      "incidentType": pin.incidentType.rawValue,
      "latitude": String(pin.coordinate.latitude),
      "longitude": String(pin.coordinate.longitude),
      "type": "new_pin",
    ]

    return (title: title, body: body, data: data)
  }

  /// Sends an actual local notification to this device (fallback)
  private func sendLocalNotification(title: String, body: String, data: [String: String]) async {
    // First check current notification permission status
    let settings = await UNUserNotificationCenter.current().notificationSettings()

    if settings.authorizationStatus != .authorized {
      print(
        "[NotificationManager] Cannot send notification - permission not granted (status: \(settings.authorizationStatus.rawValue))"
      )
      return
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
    } catch {
      print(
        "[NotificationManager] Error scheduling local notification: \(error.localizedDescription)")
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
