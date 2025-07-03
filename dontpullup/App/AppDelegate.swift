import Firebase
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import UIKit
import UserNotifications

// Static flag to track Firebase initialization
private var isFirebaseConfigured = false

// Force Firebase initialization at module load time
private let firebaseLoadTime: Void = {
  // Only configure if not already configured
  if FirebaseApp.app() == nil && !isFirebaseConfigured {
    // Disable IPv6 for Firebase connections to avoid connectivity issues
    let firebaseSettings = FirestoreSettings()
    firebaseSettings.isPersistenceEnabled = true
    firebaseSettings.cacheSizeBytes = FirestoreCacheSizeUnlimited
    
    // Configure Firebase
    isFirebaseConfigured = true
    FirebaseApp.configure()
    
    // Apply Firestore settings
    Firestore.firestore().settings = firebaseSettings
    
    print("[AppDelegate] Firebase configured at module load time")
  }
}()

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate,
  UNUserNotificationCenterDelegate
{

  var window: UIWindow?

  // Static configuration to ensure Firebase is initialized before any other access
  static let shared = AppDelegate()

  static var isFirebaseConfigured = true

  override init() {
    // Make sure Firebase is already configured from the static initializer
    _ = firebaseLoadTime
    super.init()
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Firebase is already configured in the static initializer
    // No need to configure again here

    // Configure Firebase Messaging
    Messaging.messaging().delegate = self
    print("[AppDelegate] Firebase Messaging configured")

    // Request notification permissions
    UNUserNotificationCenter.current().delegate = self
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { granted, error in
        print("[AppDelegate] Notification permission granted: \(granted)")
        if let error = error {
          print("[AppDelegate] Notification permission error: \(error)")
        }
      })

    application.registerForRemoteNotifications()

    // Ensure resource files are properly loaded
    ensureResourceFilesExist()
    
    // Set network preferences to prefer IPv4
    setNetworkPreferences()

    return true
  }
  
  // Set network preferences to prefer IPv4 over IPv6
  private func setNetworkPreferences() {
    // This sets a hint to the system to prefer IPv4 connections
    let key = "Prefer IPv4" as CFString
    let value = true as CFBoolean
    
    // Set the global network preference
    let success = CFNetworkSetGlobalPreference(key, value)
    print("[AppDelegate] Set network preference to prefer IPv4: \(success)")
  }

  private func setupFirebaseMessaging(_ application: UIApplication) {
    // Set messaging delegate
    Messaging.messaging().delegate = self

    // Set notification delegate
    UNUserNotificationCenter.current().delegate = self

    // Request notification permissions
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { granted, _ in
        print("[AppDelegate] Notification permission granted: \(granted)")

        // Register for remote notifications if permission granted
        if granted {
          DispatchQueue.main.async {
            application.registerForRemoteNotifications()
          }
        }
      }
    )

    // Configure Firebase Messaging
    Messaging.messaging().isAutoInitEnabled = true

    print("[AppDelegate] Firebase Messaging configured")
  }

  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }

  func application(
    _ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>
  ) {
    // Handle discarded scenes if needed
  }

  // Add missing required methods for UIApplicationDelegate
  func applicationWillResignActive(_ application: UIApplication) {
    // Sent when the application is about to move from active to inactive state
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    // Use this method to release shared resources and save user data
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    // Called as part of the transition from the background to the active state
  }

  func applicationDidBecomeActive(_ application: UIApplication) {
    // Restart any tasks that were paused while the application was inactive
  }

  func applicationWillTerminate(_ application: UIApplication) {
    // Called when the application is about to terminate
  }

  // MARK: - Firebase Messaging Delegate

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken else { return }
    print("[AppDelegate] FCM registration token: \(token)")

    // Pass token to AuthenticationManager
    Task {
      await AuthenticationManager.shared.updateFCMToken(token)
      print("[AppDelegate] FCM token successfully passed to AuthenticationManager")
    }
  }

  // MARK: - Push Notification Handling

  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("[AppDelegate] APNs token received")
    Messaging.messaging().apnsToken = deviceToken
  }

  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[AppDelegate] Failed to register for remote notifications: \(error)")
  }

  // MARK: - UNUserNotificationCenter Delegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("[AppDelegate] Received notification while app in foreground: \(userInfo)")
    completionHandler([[.banner, .sound]])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("[AppDelegate] Handling notification response: \(userInfo)")
    completionHandler()
  }

  // MARK: - Resource File Management

  /// Ensures that all required resource files exist and are in the correct locations
  private func ensureResourceFilesExist() {
    // Check and fix the default.csv file
    ensureDefaultCSVExists()
  }

  /// Ensures the default.csv file exists in the MapStyles directory
  private func ensureDefaultCSVExists() {
    let fileManager = FileManager.default
    let bundle = Bundle.main

    // Check if the file exists in the MapStyles directory
    if bundle.path(forResource: "default", ofType: "csv", inDirectory: "MapStyles") != nil {
      // File exists in MapStyles directory
      print("[AppDelegate] default.csv already exists in MapStyles directory")
      return
    }

    // File doesn't exist in MapStyles directory, copy it from the main bundle
    if let mainBundlePath = bundle.path(forResource: "default", ofType: "csv") {
      do {
        // Create MapStyles directory if it doesn't exist
        let mapStylesDir = bundle.bundlePath.appending("/MapStyles")
        if !fileManager.fileExists(atPath: mapStylesDir) {
          try fileManager.createDirectory(atPath: mapStylesDir, withIntermediateDirectories: true)
        }

        // Copy the file
        let destPath = mapStylesDir.appending("/default.csv")
        try fileManager.copyItem(atPath: mainBundlePath, toPath: destPath)
        print("[AppDelegate] Successfully copied default.csv to MapStyles directory")
      } catch {
        print("[AppDelegate] Error copying default.csv: \(error.localizedDescription)")
      }
    } else {
      print("[AppDelegate] Warning: default.csv not found in main bundle")
    }
  }
}
