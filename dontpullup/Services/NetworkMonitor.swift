import Network
import SwiftUI

class NetworkMonitor: ObservableObject {
  @Published private(set) var isConnected = true
  @Published private(set) var isOnCellular = false

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
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }
}
