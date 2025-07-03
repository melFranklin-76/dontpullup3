import FirebaseCore
import SwiftUI

// import FirebaseCore // Assuming AppDelegate handles this sufficiently

@main
struct DontpullupApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var networkMonitor = NetworkMonitor()
  @StateObject private var authState: AuthState  // Declare as @StateObject, initialize in init

  init() {
    // Firebase is configured by the AppDelegate's module load-time initializer
    // No need to configure Firebase here

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
