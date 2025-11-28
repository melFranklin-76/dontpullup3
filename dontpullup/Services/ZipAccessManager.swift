import Combine
import CoreLocation
import Foundation

/// Centralizes the rules for ZIP-based access control.
/// Summary:
/// - Home ZIP is always unlocked.
/// - Users can permanently unlock additional ZIPs one-by-one.
/// - Entering a new ZIP grants temporary access that expires when leaving.
/// - Visibility/notifications should reference the effective access set
///   (home + purchased + current physical ZIP when it is outside the permanent list).
@MainActor
final class ZipAccessManager: ObservableObject {
  static var shared: ZipAccessManager = {
    let authManager = AuthenticationManager.shared
    return ZipAccessManager(authManager: authManager)
  }()

  // MARK: - Published state

  @Published private(set) var homeZIP: String?
  @Published private(set) var purchasedZIPs: Set<String> = []
  @Published private(set) var currentPhysicalZIP: String?
  @Published private(set) var currentTravelZIP: String?
  @Published private(set) var effectiveAccessZIPs: Set<String> = []

  // MARK: - Dependencies

  private let authManager: AuthenticationManager
  private let geocoder: CLGeocoder
  private let userDefaults: UserDefaults

  private var cancellables = Set<AnyCancellable>()
  private var geocodeTask: Task<Void, Never>?

  // MARK: - Constants

  private let accuracyThreshold: CLLocationAccuracy = 150  // meters (~492 ft)
  private let travelZipDefaultsKey = "ZipAccessManager.currentTravelZIP"

  // MARK: - Init

  private init(
    authManager: AuthenticationManager,
    geocoder: CLGeocoder = CLGeocoder(),
    userDefaults: UserDefaults = .standard
  ) {
    self.authManager = authManager
    self.geocoder = geocoder
    self.userDefaults = userDefaults

    if let savedZip = sanitized(userDefaults.string(forKey: travelZipDefaultsKey)) {
      currentTravelZIP = savedZip
    }

    bindToAuthentication()
  }

  // MARK: - Public API

  /// Returns true if the user should see incidents for the provided ZIP.
  func hasAccess(to zipCode: String?) -> Bool {
    guard let zip = sanitized(zipCode) else { return false }
    return effectiveAccessZIPs.contains(zip)
  }

  /// Filters a list of pins using the effective access list.
  func filterPins(_ pins: [Pin]) -> [Pin] {
    guard !effectiveAccessZIPs.isEmpty else { return [] }
    return pins.filter { hasAccess(to: $0.zipCode) }
  }

  /// Exposes the sorted ZIP list for UI components (picker, chips, etc).
  func allowedZIPsList() -> [String] {
    return Array(effectiveAccessZIPs).sorted()
  }

  /// Updates the current physical ZIP based on a fresh location reading.
  /// Only locations that meet the accuracy threshold trigger a reverse-geocode.
  func updateTravelAccess(with location: CLLocation) {
    guard location.horizontalAccuracy <= accuracyThreshold else {
      #if DEBUG
        print(
          "[ZipAccessManager] Ignoring location update, accuracy too low: \(location.horizontalAccuracy)"
        )
      #endif
      return
    }

    geocodeTask?.cancel()
    geocodeTask = Task { [weak self] in
      guard let self else { return }

      do {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let zip = sanitized(placemarks.first?.postalCode) else { return }
        self.handleResolvedCurrentZip(zip)
      } catch {
        #if DEBUG
          print("[ZipAccessManager] Reverse geocode failed: \(error.localizedDescription)")
        #endif
      }
    }
  }

  /// Allows manual overrides (e.g., when a ZIP is derived server-side).
  func forceSetCurrentZip(_ zipCode: String?) {
    handleResolvedCurrentZip(zipCode)
  }

  /// Clears all cached state (typically when a user signs out).
  func reset() {
    geocodeTask?.cancel()
    homeZIP = nil
    purchasedZIPs = []
    currentPhysicalZIP = nil
    currentTravelZIP = nil
    effectiveAccessZIPs = []
    userDefaults.removeObject(forKey: travelZipDefaultsKey)
    notifyAccessChange()
  }

  /// Returns true when the provided ZIP is being accessed via temporary travel.
  func isTemporarilyUnlocked(zipCode: String) -> Bool {
    guard let currentTravelZIP else { return false }
    return currentTravelZIP == sanitized(zipCode)
  }

  // MARK: - Private helpers

  private func bindToAuthentication() {
    authManager.$currentUserProfile
      .receive(on: DispatchQueue.main)
      .sink { [weak self] profile in
        self?.apply(profile)
      }
      .store(in: &cancellables)
  }

  private func apply(_ profile: UserProfile?) {
    guard let profile else {
      reset()
      return
    }

    homeZIP = sanitized(profile.originalZipCode.isEmpty ? profile.zipCode : profile.originalZipCode)
    purchasedZIPs = Set(profile.purchasedZipCodes.compactMap { sanitized($0) })

    // If the user just purchased a ZIP that was previously temporary, drop the temporary flag.
    if let tempZip = currentTravelZIP, purchasedZIPs.contains(tempZip) {
      clearStoredTravelZip()
    }

    mergeEffectiveAccessSet()
  }

  private func handleResolvedCurrentZip(_ rawZip: String?) {
    guard let resolvedZip = sanitized(rawZip) else {
      clearStoredTravelZip()
      currentPhysicalZIP = nil
      mergeEffectiveAccessSet()
      return
    }

    if currentPhysicalZIP == resolvedZip {
      return  // No-op if nothing changed
    }

    currentPhysicalZIP = resolvedZip

    let isHome = resolvedZip == homeZIP
    let isPurchased = purchasedZIPs.contains(resolvedZip)

    if isHome || isPurchased {
      clearStoredTravelZip()
    } else {
      currentTravelZIP = resolvedZip
      userDefaults.set(resolvedZip, forKey: travelZipDefaultsKey)
    }

    mergeEffectiveAccessSet()
  }

  private func mergeEffectiveAccessSet() {
    var next = Set<String>()

    if let home = homeZIP {
      next.insert(home)
    }

    next.formUnion(purchasedZIPs)

    if let travel = currentTravelZIP {
      next.insert(travel)
    }

    let changed = next != effectiveAccessZIPs
    effectiveAccessZIPs = next

    if changed {
      notifyAccessChange()
    }
  }

  private func clearStoredTravelZip() {
    if currentTravelZIP != nil || userDefaults.string(forKey: travelZipDefaultsKey) != nil {
      currentTravelZIP = nil
      userDefaults.removeObject(forKey: travelZipDefaultsKey)
    }
  }

  private func notifyAccessChange() {
    NotificationCenter.default.post(name: .zipAccessStateDidChange, object: nil)
  }
}

// MARK: - Pure helper

private func sanitized(_ zip: String?) -> String? {
  guard
    let trimmed = zip?.trimmingCharacters(in: .whitespacesAndNewlines),
    !trimmed.isEmpty
  else { return nil }
  return trimmed.uppercased()
}


