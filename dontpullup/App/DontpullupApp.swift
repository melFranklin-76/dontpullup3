import FirebaseCore
import SwiftUI

// import FirebaseCore // Assuming AppDelegate handles this sufficiently

@main
struct DontpullupApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var networkMonitor = NetworkMonitor()
  @StateObject private var authState: AuthState  // Declare as @StateObject, initialize in init

  init() {
    // Ensure Firebase is configured - this is a safety measure in case AppDelegate initialization hasn't completed
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("[DontpullupApp] Firebase configured in SwiftUI App init")
    }

    // Initialize AuthState
    self._authState = StateObject(wrappedValue: AuthState.shared)

    // Setup StorageUploader network monitoring
    StorageUploader.setupNetworkMonitoring()

    print("[DontpullupApp] Initializer finished.")
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(networkMonitor)  // Inject NetworkMonitor
        .environmentObject(authState)  // Inject AuthState
    }
  }
}
