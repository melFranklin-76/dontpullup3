import Network
import SwiftUI

class NetworkMonitor: ObservableObject {
  @Published private(set) var isConnected = true
  @Published private(set) var isOnCellular = false
  @Published private(set) var connectionType: String = "Unknown"
  @Published private(set) var isExpensive = false

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "NetworkMonitor")

  static let shared = NetworkMonitor()

  init() {
    setupMonitoring()
  }

  private func setupMonitoring() {
    monitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async {
        self?.isConnected = path.status == .satisfied
        self?.isOnCellular = path.usesInterfaceType(.cellular)
        self?.isExpensive = path.isExpensive

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
          self?.connectionType = "WiFi"
        } else if path.usesInterfaceType(.cellular) {
          self?.connectionType = "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
          self?.connectionType = "Ethernet"
        } else if path.usesInterfaceType(.loopback) {
          self?.connectionType = "Loopback"
        } else {
          self?.connectionType = "Other"
        }

        print(
          "[NetworkMonitor] Connection status: \(path.status == .satisfied ? "Connected" : "Disconnected"), Type: \(self?.connectionType ?? "Unknown"), Expensive: \(path.isExpensive)"
        )
      }
    }
    monitor.start(queue: queue)
  }

  // Helper method to check if we should use high-quality uploads
  func shouldUseHighQuality() -> Bool {
    return isConnected && !isExpensive
  }

  deinit {
    monitor.cancel()
  }
}
