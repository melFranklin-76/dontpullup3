import SwiftUI
import FirebaseCore

private let firebaseBootstrap: Void = {
    if FirebaseApp.app() == nil {
        FirebaseApp.configure()
        print("[FirebaseBootstrap] Firebase configured before SwiftUI launches")
    }
}()

@main
struct DontpullupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var authState: AuthState
    
    init() {
        _ = firebaseBootstrap
        self._authState = StateObject(wrappedValue: AuthState.shared)
        print("[DontpullupApp] Initializer finished.")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkMonitor)
                .environmentObject(authState)
        }
    }
}
