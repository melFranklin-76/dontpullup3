import SwiftUI
import FirebaseCore
import MapKit

extension Notification.Name {
    static let openMapAtCoordinate = Notification.Name("OpenMapAtCoordinate")
}

@main
struct DontpullupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var authState: AuthState
    
    init() {
        // Firebase is now configured in AppDelegate.didFinishLaunchingWithOptions
        // before any Firebase services are accessed
        self._authState = StateObject(wrappedValue: AuthState.shared)
        #if DEBUG
        print("[DontpullupApp] Initializer finished.")
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkMonitor)
                .environmentObject(authState)
                .onOpenURL { url in
                    #if DEBUG
                    print("[DeepLink] Received URL: \(url.absoluteString)")
                    print("[DeepLink] Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Path: \(url.path)")
                    #endif
                    Task {
                        if let parsed = await MapLinkRouter.parse(url) {
                            #if DEBUG
                            print("[DeepLink] Successfully parsed location: \(parsed.coordinate), source: \(parsed.source)")
                            #endif
                            NotificationCenter.default.post(
                                name: .openMapAtCoordinate,
                                object: nil,
                                userInfo: [
                                    "lat": parsed.coordinate.latitude,
                                    "lon": parsed.coordinate.longitude,
                                    "source": parsed.source
                                ]
                            )
                        } else {
                            #if DEBUG
                            print("[DeepLink] Failed to parse URL: \(url.absoluteString)")
                            #endif
                        }
                    }
                }
        }
    }
}
