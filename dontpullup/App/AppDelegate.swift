import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure Firebase FIRST before any Firebase service is accessed
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            #if DEBUG
            print("[AppDelegate] Firebase configured")
            #endif
        }
        
        // Configure FCM after Firebase is initialized
        setupFirebaseMessaging(application)
        
        return true
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
                #if DEBUG
                print("[AppDelegate] Notification permission granted: \(granted)")
                #endif
            }
        )
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        #if DEBUG
        print("[AppDelegate] Firebase Messaging configured")
        #endif
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
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

        // Force refresh FCM token when app becomes active to ensure it's current
        Task {
            await refreshFCMTokenIfNeeded()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate
    }
    
    // MARK: - Firebase Messaging Delegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        #if DEBUG
        print("[AppDelegate] FCM registration token: \(fcmToken ?? "none")")
        #endif
        
        // Update the FCM token in user profile
        if let token = fcmToken {
            Task {
                await updateUserFCMToken(token)
            }
        }
    }
    
    private func updateUserFCMToken(_ token: String) async {
        // Update FCM token in AuthenticationManager
        await AuthenticationManager.shared.updateFCMToken(token)
    }

    private func refreshFCMTokenIfNeeded() async {
        #if DEBUG
        print("[AppDelegate] Refreshing FCM token on app activation")
        #endif
        
        do {
            let token = try await Messaging.messaging().token()
            #if DEBUG
            print("[AppDelegate] Refreshed FCM token: \(token.prefix(8))...")
            #endif
            await updateUserFCMToken(token)
        } catch {
            #if DEBUG
            print("[AppDelegate] Failed to refresh FCM token: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Push Notification Handling
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        print("[AppDelegate] APNs token received")
        #endif
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
    }
    
    // MARK: - UNUserNotificationCenter Delegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        #if DEBUG
        print("[AppDelegate] 📱 Notification received in foreground: \(notification.request.content.title)")
        print("[AppDelegate] 📱 Notification body: \(notification.request.content.body)")
        print("[AppDelegate] 📱 Notification userInfo: \(notification.request.content.userInfo)")
        #endif
        
        // Use modern notification presentation options (iOS 14+)
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .badge, .sound])
            #if DEBUG
            print("[AppDelegate] ✅ Showing notification with banner, list, badge, and sound")
            #endif
        } else {
            completionHandler([.alert, .badge, .sound])
            #if DEBUG
            print("[AppDelegate] ✅ Showing notification with alert, badge, and sound")
            #endif
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        #if DEBUG
        print("[AppDelegate] 👆 Notification tapped: \(response.notification.request.content.title)")
        print("[AppDelegate] 👆 Notification body: \(response.notification.request.content.body)")
        print("[AppDelegate] 👆 Notification userInfo: \(response.notification.request.content.userInfo)")
        #endif
        
        // Handle notification action based on type
        let userInfo = response.notification.request.content.userInfo
        if let pinId = userInfo["pinId"] as? String {
            #if DEBUG
            print("[AppDelegate] 📍 Opening pin: \(pinId)")
            #endif
            // Post notification to open pin on map
            NotificationCenter.default.post(
                name: .openPinOnMap,
                object: nil,
                userInfo: ["pinId": pinId]
            )
        }
        
        completionHandler()
    }
}

