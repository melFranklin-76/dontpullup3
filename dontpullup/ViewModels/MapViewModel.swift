import AVKit
import Combine
@preconcurrency import CoreLocation
@preconcurrency import Dispatch
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
typealias ListenerRegistration = FirebaseFirestore.ListenerRegistration
import MapKit
import Photos
import SwiftUI
@preconcurrency import UIKit

enum MapDisplayStyle: String, CaseIterable, Identifiable {
  case explore
  case muted
  case satellite
  case hybrid
  case flyover

  var id: String { rawValue }

  var title: String {
    switch self {
    case .explore:
      return "Explore 2D"
    case .muted:
      return "Night Mode"
    case .satellite:
      return "Satellite"
    case .hybrid:
      return "Hybrid Detail"
    case .flyover:
      return "Immersive 3D"
    }
  }

  var subtitle: String {
    switch self {
    case .explore:
      return "Default streets & landmarks"
    case .muted:
      return "Low-glare dark canvas"
    case .satellite:
      return "High-resolution imagery"
    case .hybrid:
      return "Labels + satellite context"
    case .flyover:
      return "Tilted 3D perspective"
    }
  }

  var iconName: String {
    switch self {
    case .explore:
      return "map"
    case .muted:
      return "moon.stars.fill"
    case .satellite:
      return "sparkles.rectangle.stack"
    case .hybrid:
      return "globe.americas.fill"
    case .flyover:
      return "view.3d"
    }
  }

  var mapType: MKMapType {
    switch self {
    case .explore:
      return .standard
    case .muted:
      return .mutedStandard
    case .satellite:
      return .satellite
    case .hybrid:
      return .hybrid
    case .flyover:
      return .hybridFlyover
    }
  }

  var allowsPitch: Bool {
    switch self {
    case .flyover:
      return true
    default:
      return false
    }
  }

  var preferredPitch: CGFloat {
    allowsPitch ? 55 : 0
  }

  var preferredAltitude: CLLocationDistance {
    switch self {
    case .flyover:
      return 800
    case .satellite:
      return 1200
    default:
      return 900
    }
  }

  var showsBuildings: Bool {
    switch self {
    case .satellite:
      return false
    default:
      return true
    }
  }

  var showsTraffic: Bool {
    self == .hybrid
  }
}

@MainActor
class MapViewModel: NSObject, ObservableObject {
  // MARK: - Published Properties
  @Published var userLocation: CLLocation?
  @Published var isLocationAuthorized = false
  @Published var isLocationServicesEnabled = false
  @Published var isTrackingUserLocation = false
  @Published var region: MKCoordinateRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),  // Default to NYC
    span: MKCoordinateSpan(latitudeDelta: 0.001373, longitudeDelta: 0.001373)  // Span similar to MapView's initial
  )
  @Published var pins: [Pin] = []
  @Published var selectedFilters: Set<IncidentType> = []
  @Published var showingIncidentPicker = false
  @Published var showingHelp = false
  @Published var showAlert = false
  @Published var alertMessage = ""
  @Published var isEditMode = false
  @Published var mapType: MKMapType = MapDisplayStyle.explore.mapType
  @Published var mapDisplayStyle: MapDisplayStyle = .explore {
    didSet { mapType = mapDisplayStyle.mapType }
  }
  @Published var mapRegion: MKCoordinateRegion?
  @Published var showingOnlyMyPins = false
  @Published private(set) var accessibleZipCodes: Set<String> = []
  var pendingCoordinate: CLLocationCoordinate2D?
  var isRequestingLocation = false
  var currentlyPlayingVideoId: String?
  var pendingVideoData: Data?

  // Pre-compression for ultra-fast uploads
  @Published var preCompressedVideoURL: URL?
  private var preCompressionTask: Task<Void, Error>?
  @Published var uploadProgress: Double = 0
  @Published var reportStep: ReportStep?  // nil = no sheet
  @Published var reportDraft = PinDraft()  // holds coord/type/url
  @Published var isLimitedFunctionalityDueToLocationDenial: Bool = false
  @Published var activeUploads: Int = 0  // Track number of active uploads
  @Published var showingContentGuidelines = false  // Show content guidelines modal
  // Flag to remember that the user tapped center button before granting permission
  private var shouldCenterAfterAuthorization = false
  private var shouldCenterAfterLocationUpdate = false
  private var hasPromptedForInitialPermission = false

  // Alert queue to prevent multiple alerts
  private var alertQueue: [String] = []
  private var isShowingAlert = false

  // Add AuthState
  var authState: AuthState

  // Add NotificationManager for zip code notifications
  private lazy var notificationManager = NotificationManager.shared
  private let authManager = AuthenticationManager.shared
  private let zipAccessManager = ZipAccessManager.shared

  // MARK: - Private Properties
  private let locationManager = CLLocationManager()
  private lazy var db: Firestore = { Firestore.firestore() }()
  private var lastPresenceZipCode: String?
  private var lastPresenceLocation: CLLocation?
  private var lastPresenceUpdateDate: Date?
  private let presenceUpdateDistanceThreshold: CLLocationDistance = 120  // meters
  private let presenceUpdateInterval: TimeInterval = 60  // seconds between duplicate writes
  private var cancellables = Set<AnyCancellable>()
  
  // Geographic filtering properties
  private var lastQueriedRegion: MKCoordinateRegion?
  private let minimumRegionChangeThreshold: Double = 0.3 // 30% change triggers reload
  private var pinsListener: ListenerRegistration?

  // MARK: - Computed Properties
  var filteredPins: [Pin] {
    pins.filter { pin in
      // First apply user filter if enabled
      if showingOnlyMyPins {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return pin.userId == currentUserId
      }

      // Apply incident type filter
      let passesTypeFilter = selectedFilters.isEmpty || selectedFilters.contains(pin.incidentType)

      // Apply zip access filter when a pin has an associated zip code
      let passesZipFilter: Bool
      if pin.zipCode.isEmpty {
        passesZipFilter = true  // Legacy pins without zip remain visible
      } else {
        passesZipFilter = zipAccessManager.hasAccess(to: pin.zipCode)
      }

      return passesTypeFilter && passesZipFilter
    }
  }

  // MARK: - Firestore Operations

  /// Reports a video with provided information
  /// - Parameters:
  ///   - email: Email address of the person reporting
  ///   - reason: Reason for reporting
  ///   - videoId: ID of the video being reported
  /// - Returns: No return value
  /// - Throws: FirebaseError if the operation fails
  func reportVideo(email: String, reason: String, videoId: String) async throws {
    let report: [String: Any] = [
      "email": email,
      "reason": reason,
      "videoId": videoId,
      "timestamp": Date().timeIntervalSince1970,
      "status": "pending",
    ]

    try await db.collection("flaggedVideos").addDocument(data: report)
    #if DEBUG
    print("[MapViewModel] Flag report submitted successfully for video \(videoId)")
    #endif
  }

  // MARK: - User Actions
  func toggleFilter(_ type: IncidentType) {
    if selectedFilters.contains(type) {
      selectedFilters.remove(type)
    } else {
      selectedFilters.insert(type)
    }
  }

  func toggleMyPinsFilter() {
    showingOnlyMyPins.toggle()
  }

  func toggleMapType() {
    cycleMapType()
  }

  func toggleEditMode() {
    isEditMode.toggle()
  }

  func acceptContentGuidelines() {
    showingContentGuidelines = false
    UserDefaults.standard.set(true, forKey: "hasAcceptedContentGuidelines")
  }

  // MARK: - Zoom helpers
  func zoomIn() {
    #if DEBUG
    print("[MapViewModel] Zoom in requested")
    #endif
    var newRegion = self.region  // Start with the current actual region

    // Sanitize current region to prevent NaN propagation
    newRegion.center = sanitizeCoordinate(newRegion.center)
    newRegion.span = sanitizeSpan(newRegion.span)

    var latDelta = newRegion.span.latitudeDelta * 0.5
    var lonDelta = newRegion.span.longitudeDelta * 0.5

    // Validate calculations and provide fallbacks
    if latDelta.isNaN || latDelta.isInfinite {
      latDelta = minSpanDelta
    } else {
      latDelta = max(latDelta, minSpanDelta)
    }

    if lonDelta.isNaN || lonDelta.isInfinite {
      lonDelta = minSpanDelta
    } else {
      lonDelta = max(lonDelta, minSpanDelta)
    }

    newRegion.span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)

    #if DEBUG
    print(
      "[MapViewModel] Setting zoom region from \(self.region.span.latitudeDelta) to \(newRegion.span.latitudeDelta)"
    )
    #endif

    // Important: Update both properties
    self.region = newRegion

    // Use withAnimation to ensure smooth transition
    withAnimation(.easeInOut(duration: 0.3)) {
      self.mapRegion = newRegion
    }

    // Post notification for map update
    NotificationCenter.default.post(name: Notification.Name("MapRegionChanged"), object: nil)
  }

  func zoomOut() {
    #if DEBUG
    print("[MapViewModel] Zoom out requested")
    #endif
    var newRegion = self.region  // Start with the current actual region

    // Sanitize current region to prevent NaN propagation
    newRegion.center = sanitizeCoordinate(newRegion.center)
    newRegion.span = sanitizeSpan(newRegion.span)

    var latDelta = newRegion.span.latitudeDelta * 2
    var lonDelta = newRegion.span.longitudeDelta * 2

    // Validate calculations and provide fallbacks
    if latDelta.isNaN || latDelta.isInfinite {
      latDelta = maxSpanDelta
    } else {
      latDelta = min(latDelta, maxSpanDelta)
    }

    if lonDelta.isNaN || lonDelta.isInfinite {
      lonDelta = maxSpanDelta
    } else {
      lonDelta = min(lonDelta, maxSpanDelta)
    }

    newRegion.span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)

    #if DEBUG
    print(
      "[MapViewModel] Setting zoom region from \(self.region.span.latitudeDelta) to \(newRegion.span.latitudeDelta)"
    )
    #endif

    // Important: Update both properties
    self.region = newRegion

    // Use withAnimation to ensure smooth transition
    withAnimation(.easeInOut(duration: 0.3)) {
      self.mapRegion = newRegion
    }

    // Post notification for map update
    NotificationCenter.default.post(name: Notification.Name("MapRegionChanged"), object: nil)
  }

  @MainActor
  func centerOnUserLocation() {
    guard let userLocation = userLocation else {
      showAlert = true
      alertMessage = "Unable to determine your location"
      return
    }

    // Sanitize user location coordinate
    let validCoordinate = sanitizeCoordinate(userLocation.coordinate)

    #if DEBUG
    print("[MapViewModel] Centering on user location: \(validCoordinate)")
    #endif

    let newCenteredRegion = MKCoordinateRegion(
      center: validCoordinate,
      span: MKCoordinateSpan(latitudeDelta: 0.0011, longitudeDelta: 0.0011)
    )

    // Update both region and mapRegion for consistent state
    self.region = newCenteredRegion

    // Force UI update by explicitly setting a new region
    self.mapRegion = MKCoordinateRegion(
      center: validCoordinate,
      span: MKCoordinateSpan(latitudeDelta: 0.0011, longitudeDelta: 0.0011)
    )
  }

  /// Ensures that a usable location is available within a short timeout.
  /// Returns `true` if `userLocation` is already populated or becomes
  /// available within the timeout window, otherwise `false`.
  func checkLocationAvailability() async -> Bool {
    // 1. Must be authorized.
    guard isLocationAuthorized else { return false }

    // 2. Device-level services need to be enabled.
    guard await checkLocationServicesEnabledAsync() else { return false }

    // 3. If we already have a fix, we're done.
    if userLocation != nil { return true }

    // 4. Otherwise request a one-time location and await the helper.
    locationManager.requestLocation()

    //   Re-use the existing getCurrentLocation() helper which already
    //   handles its own timeout and MainActor isolation.
    let location = await getCurrentLocation()
    return location != nil
  }

  /// Toggles continuous location tracking mode (like navigation)
  func toggleLocationTracking() {
    isTrackingUserLocation.toggle()

    if isTrackingUserLocation {
      #if DEBUG
      print("[MapViewModel] Starting real-time location tracking (navigation mode)")
      #endif
      
      // Configure location manager for navigation-style tracking
      locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
      locationManager.distanceFilter = 5 // Update every 5 meters
      
      // Start continuous updates for real-time tracking
      locationManager.startUpdatingLocation()
      
      // Also center the map on the user with a good zoom level
      if let location = userLocation {
        let navigationSpan = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        mapRegion = MKCoordinateRegion(
          center: location.coordinate,
          span: navigationSpan
        )
        #if DEBUG
        print("[MapViewModel] Centered map on user at \(location.coordinate)")
        #endif
      }
    } else {
      #if DEBUG
      print("[MapViewModel] Stopping real-time location tracking")
      #endif
      
      // Reset to normal accuracy for battery efficiency
      locationManager.desiredAccuracy = kCLLocationAccuracyBest
      locationManager.distanceFilter = kCLDistanceFilterNone
      
      // Stop continuous updates to save battery
      locationManager.stopUpdatingLocation()
    }
  }

  func getCurrentLocation() async -> CLLocation? {
    if let location = userLocation {
      return location
    }

    if !isLocationAuthorized || !isLocationServicesEnabled {
      return nil
    }

    let timeoutSeconds = 3.0
    do {
      return try await withTimeout(seconds: timeoutSeconds) {
        try await withCheckedThrowingContinuation { continuation in
          var token: Any?
          var hasResumed = false  // Flag to track if continuation has been resumed

          // Define a function to safely resume continuation once
          func safelyResume(with location: CLLocation) {
            guard !hasResumed else { return }
            hasResumed = true

            // Remove observer if it exists
            if let token = token {
              NotificationCenter.default.removeObserver(token)
            }

            continuation.resume(returning: location)
          }

          // Set up observer for location updates
          token = NotificationCenter.default.addObserver(
            forName: Notification.Name("LocationUpdated"),
            object: nil,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor in
              guard let self = self, let location = self.userLocation else { return }
              safelyResume(with: location)
            }
          }

          Task { @MainActor in
            self.locationManager.requestLocation()
            // Check if location is already available
            if let location = self.userLocation {
              safelyResume(with: location)
            }
          }
        }
      }
    } catch {
      return nil
    }
  }

  private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T)
    async throws -> T
  {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TimeoutError()
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  private struct TimeoutError: Error {}

  func initiatePinDropVerification(at coordinate: CLLocationCoordinate2D) {
    if !isLocationAuthorized {
      // Use unified handler for permission and pin drop
      handleLocationAction(.pinDrop(coordinate))
      return
    }
    guard let userLocation = userLocation else {
      showAlert = true
      alertMessage = "Unable to determine your location"
      return
    }
    let pinLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let distance = userLocation.distance(from: pinLocation)
    if distance <= 200 * 0.3048 {
      pendingCoordinate = coordinate
      showingIncidentPicker = true
    } else {
      showAlert = true
      alertMessage = "You can only drop pins within 200 feet of your location"
    }
  }

  func userCanEditPin(_ pin: Pin) -> Bool {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
    return pin.userId == currentUserId
  }

  func getCachedVideo(for videoURL: String) -> Data? { return nil }

  func cacheVideo(from remoteURL: URL, key: String) async throws {
    do {
      let _ = try await URLSession.shared.data(from: remoteURL)
      #if DEBUG
      print("[MapViewModel] Downloaded video data from \(remoteURL)")
      #endif
    } catch {
      #if DEBUG
      print("[MapViewModel] Error caching video: \(error.localizedDescription)")
      #endif
      throw error
    }
  }

  // MARK: - Alert handling
  func showError(_ message: String) {
    Task { @MainActor in
      // Add message to queue and try to show after a brief delay
      // This prevents "presentation in progress" conflicts when sheets are dismissing
      alertQueue.append(message)
      
      // Small delay to allow any ongoing presentations/dismissals to complete
      try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
      processAlertQueue()
    }
  }

  @MainActor
  private func processAlertQueue() {
    // Only proceed if we're not already showing an alert and we have messages
    guard !isShowingAlert, !alertQueue.isEmpty else { return }

    // Use DispatchQueue.main.async to defer the state update and avoid
    // "Publishing changes from within view updates" warning
    DispatchQueue.main.async {
      self.alertMessage = self.alertQueue.removeFirst()
      self.isShowingAlert = true
      self.showAlert = true
    }
  }

  /// Starts pre-compression of video immediately when selected for ultra-fast uploads
  func startPreCompression(videoURL: URL) {
    // Cancel any existing pre-compression
    preCompressionTask?.cancel()
    preCompressedVideoURL = nil

    // Start new pre-compression task
    preCompressionTask = Task {
      do {
        #if DEBUG
        print("[MapViewModel] Starting pre-compression of video...")
        #endif

        let compressedURL = try await StorageUploader.compressVideo(inputURL: videoURL)

        // Update on main actor
        await MainActor.run {
          self.preCompressedVideoURL = compressedURL
          #if DEBUG
          print("[MapViewModel] Pre-compression completed successfully")
          #endif
        }
      } catch {
        #if DEBUG
        print("[MapViewModel] Pre-compression failed: \(error.localizedDescription)")
        #endif
        await MainActor.run {
          self.preCompressedVideoURL = nil
        }
      }
    }
  }

  /// Uses pre-compressed video if available, otherwise compresses on demand
  func getOptimizedVideoURL(originalURL: URL) async throws -> URL {
    // If we have a pre-compressed version, use it
    if let preCompressed = preCompressedVideoURL {
      #if DEBUG
      print("[MapViewModel] Using pre-compressed video for ultra-fast upload")
      #endif
      return preCompressed
    }

    // Otherwise compress on demand (fallback)
    #if DEBUG
    print("[MapViewModel] No pre-compressed video available, compressing now...")
    #endif
    return try await StorageUploader.compressVideo(inputURL: originalURL)
  }

  func clearPendingData() {
    // Clear pending state regardless of upload progress if explicitly called
    // This ensures cleanup happens even after timeout errors
    #if DEBUG
    print("[MapViewModel] Clearing pending operation data")
    #endif

    // Clear all pending state in a single batch update
    pendingCoordinate = nil
    pendingVideoData = nil
    uploadProgress = 0
    showingIncidentPicker = false
    reportStep = nil

    // Cancel pre-compression and clear cached video
    preCompressionTask?.cancel()
    preCompressionTask = nil
    preCompressedVideoURL = nil

    // Also reset active uploads counter if we're clearing everything
    activeUploads = 0
  }

  // Separate function for async operations that need to be performed after clearing data
  @MainActor
  private func performPostClearOperations() async {
    // Any async operations that need to be performed after clearing data
    // can be added here
  }

  // MARK: - Location Management

  /// Gets the current authorization status on the main actor (required by CoreLocation)
  private func getAuthorizationStatus() -> CLAuthorizationStatus {
    return locationManager.authorizationStatus
  }

  /// Checks if location services are enabled (async to avoid main thread warnings)
  private func checkLocationServicesEnabledAsync() async -> Bool {
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        let enabled = CLLocationManager.locationServicesEnabled()
        continuation.resume(returning: enabled)
      }
    }
  }

  private func getAuthorizationStatusAsync() async -> CLAuthorizationStatus {
    return await MainActor.run { locationManager.authorizationStatus }
  }

  private func checkInitialLocationStatus() async {
    // Execute CoreLocation queries away from the main thread first
    let servicesEnabled = await checkLocationServicesEnabledAsync()
    let status = await getAuthorizationStatusAsync()

    // Publish results back on the main actor
    await MainActor.run {
      self.isLocationServicesEnabled = servicesEnabled
      self.isLocationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
      #if DEBUG
      print(
        "[MapViewModel] Initial check: Services enabled: \(servicesEnabled), Authorized: \(self.isLocationAuthorized) (Status: \(status.rawValue))"
      )
      #endif

      if !self.isLocationServicesEnabled
        || (!self.isLocationAuthorized && (status == .denied || status == .restricted))
      {
        self.isLimitedFunctionalityDueToLocationDenial = true
        // We can also set the UserDefaults flag here if appropriate, though a dedicated func might be better
        // UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")
        #if DEBUG
        print(
          "[MapViewModel] Initial check: Location services/auth not sufficient. Limited functionality mode ON."
        )
        #endif
      } else if self.isLocationAuthorized {
        self.isLimitedFunctionalityDueToLocationDenial = false
        // UserDefaults.standard.set(false, forKey: "userDeclinedLocationPermissions")
        #if DEBUG
        print("[MapViewModel] Initial check: Location authorized. Limited functionality mode OFF.")
        #endif
      } else {
        // If status is .notDetermined, we don't set isLimitedFunctionalityDueToLocationDenial yet.
        // It will be determined after the permission prompt.
        #if DEBUG
        print(
          "[MapViewModel] Initial check: Location status .notDetermined. Waiting for prompt result."
        )
        #endif
      }

      #if DEBUG
      print(
        "[MapViewModel] No automatic location requests - waiting for user action (center or pin drop)."
      )
      #endif
    }
  }

  @MainActor
  func forceLocationPermissionCheck() async {
    #if DEBUG
    print("[MapViewModel] forceLocationPermissionCheck called.")
    #endif
    // Move this off the main thread
    self.isLocationServicesEnabled = await checkLocationServicesEnabledAsync()

    if !self.isLocationServicesEnabled {
      #if DEBUG
      print("[MapViewModel] Location services disabled at device level.")
      #endif
      self.isLocationAuthorized = false  // Reflect this state
      self.isLimitedFunctionalityDueToLocationDenial = true  // Set the flag
      UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")  // Set user default
      alertMessage = "Location services are disabled. Please enable them in Settings."
      showAlert = true
      return
    }

    // Get authorization status safely off the main thread
    let currentStatus = await getAuthorizationStatusAsync()

    #if DEBUG
    print("[MapViewModel] Current authorization status for force check: \(currentStatus.rawValue)")
    #endif
    self.isLocationAuthorized =
      (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways)

    switch currentStatus {
    case .notDetermined:
      #if DEBUG
      print("[MapViewModel] Authorization not determined, requesting WhenInUse.")
      #endif
      isRequestingLocation = true  // Indicate a request is in progress
      // We don't set isLimitedFunctionalityDueToLocationDenial here, wait for delegate.
      locationManager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      #if DEBUG
      print(
        "[MapViewModel] Authorization denied or restricted. Guiding user to settings may be needed."
      )
      #endif
      self.isLimitedFunctionalityDueToLocationDenial = true  // Set the flag
      UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")  // Set user default
      alertMessage =
        "Location access was denied. Please enable it in Settings to use location features."
      showAlert = true
    // isLocationAuthorized is already false or will be set by delegate
    case .authorizedWhenInUse, .authorizedAlways:
      #if DEBUG
      print("[MapViewModel] Already authorized.")
      #endif
      self.isLimitedFunctionalityDueToLocationDenial = false  // Clear the flag
      UserDefaults.standard.set(false, forKey: "userDeclinedLocationPermissions")  // Clear user default
      // NO automatic location updates - only request if explicitly needed
      if shouldCenterAfterAuthorization {
        centerOnUserLocation()
        shouldCenterAfterAuthorization = false
      }
      if let coord = pendingCoordinate {
        initiatePinDropVerification(at: coord)
        pendingCoordinate = nil
      }
    @unknown default:
      #if DEBUG
      print("[MapViewModel] Unknown authorization status: \(currentStatus.rawValue)")
      #endif
    }
  }

  @MainActor
  func requestLocationPermission() {
    #if DEBUG
    print("[MapViewModel] requestLocationPermission called.")
    #endif

    // Move location services check off the main thread with Task
    Task {
    let servicesEnabled = await checkLocationServicesEnabledAsync()

      await MainActor.run {
        self.isLocationServicesEnabled = servicesEnabled

        if !servicesEnabled {
          #if DEBUG
          print("[MapViewModel] Location services are disabled. Cannot request permission.")
          #endif
          self.isLocationAuthorized = false
          alertMessage = "Location services are disabled. Please enable them in Settings."
          showAlert = true
          return
        }

        // Continue with permission request after verifying services are enabled
        Task {
          let status = await getAuthorizationStatusAsync()
          await MainActor.run {
            self.handleAuthorizationStatus(status)
          }
        }
      }
    }
  }

  @MainActor
  private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
    if status == .notDetermined {
      #if DEBUG
      print("[MapViewModel] Status is .notDetermined. Requesting WhenInUse authorization.")
      #endif
      isRequestingLocation = true
      locationManager.requestWhenInUseAuthorization()
    } else {
      #if DEBUG
      print(
        "[MapViewModel] Permission already determined (Status: \(status.rawValue)). Handling via forceLocationPermissionCheck or delegate."
      )
      #endif
      // If already determined, let forceLocationPermissionCheck or delegate handle state
      // Potentially trigger force check if called directly and not .notDetermined
      Task { handleLocationAction(.initialPrompt) }
    }
  }

  // MARK: - Pin Management
  func dropPin(for incidentType: IncidentType) {
    guard let pendingCoordinate = pendingCoordinate,
      let currentUserId = Auth.auth().currentUser?.uid
    else {
      showAlert = true
      alertMessage = "Unable to drop pin. Please try again."
      showingIncidentPicker = false
      return
    }

    // Validate coordinate is on Earth
    guard abs(pendingCoordinate.latitude) <= 90 && abs(pendingCoordinate.longitude) <= 180 else {
      showError("Invalid location coordinates")
      showingIncidentPicker = false
      return
    }

    let pinId = UUID().uuidString

    Task {
      do {
        // Get zip code for the pin location
        let pinLocation = CLLocation(latitude: pendingCoordinate.latitude, longitude: pendingCoordinate.longitude)
        let zipCode = await getCurrentLocationZipCode(from: pinLocation) ?? authManager.currentUserProfile?.originalZipCode ?? ""
        
        // Create pin with zipCode
        let newPin = Pin(
          id: pinId,
          coordinate: pendingCoordinate,
          incidentType: incidentType,
          videoURL: "",
          userId: currentUserId,
          zipCode: zipCode
        )
        
        let data: [String: Any] = [
          "id": pinId,
          "latitude": pendingCoordinate.latitude,
          "longitude": pendingCoordinate.longitude,
          "type": incidentType.firestoreType,
          "videoURL": "",
          "userId": currentUserId,
          "timestamp": Timestamp(),
          "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? "",
          "zipCode": zipCode,
        ]

        try await db.collection("pins").document(pinId).setData(data)
        await MainActor.run {
          self.pins.append(newPin)
          self.pendingCoordinate = nil
          self.showingIncidentPicker = false

          // Send notifications to users in the same zip code
          Task {
            await self.sendZipCodeNotifications(for: newPin)
          }
        }
      } catch {
        #if DEBUG
        print("[MapViewModel] Error adding pin: \(error.localizedDescription)")
        #endif
        await MainActor.run {
          showAlert = true
          alertMessage = "Failed to drop pin: \(error.localizedDescription)"
          showingIncidentPicker = false
        }
      }
    }
  }

  @MainActor
  func beginVideoCaptureFlow(for incidentType: IncidentType) {
    guard let pendingCoordinate = pendingCoordinate else {
      showError("Unable to determine pin location. Please try again.")
      showingIncidentPicker = false
      return
    }

    reportDraft = PinDraft(coordinate: pendingCoordinate, incidentType: incidentType)
    self.pendingCoordinate = nil
    showingIncidentPicker = false
    reportStep = .video
  }

  func deletePin(_ pin: Pin) async throws {
    do {
      try await db.collection("pins").document(pin.id).delete()
      await MainActor.run {
        self.pins.removeAll { $0.id == pin.id }
      }
    } catch {
      #if DEBUG
      print("[MapViewModel] Error deleting pin: \(error.localizedDescription)")
      #endif
      throw error
    }
  }

  // MARK: - Initialization
  init(authState: AuthState) {
    self.authState = authState
    super.init()

    // Set up location manager
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = 10  // Update when user moves 10 meters

    // Set up notification observer for upload progress
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(updateUploadProgress),
      name: Notification.Name("UploadProgressUpdated"),
      object: nil
    )

    // Initialize location status
    Task {
      await checkInitialLocationStatus()
    }

    // Defer loadPins() to avoid publishing changes during view initialization
    Task { @MainActor in
      loadPins()
    }

    // Clean up any invalid pins on startup
    Task {
      await cleanupInvalidPins()
    }

    accessibleZipCodes = zipAccessManager.effectiveAccessZIPs
    zipAccessManager.$effectiveAccessZIPs
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newSet in
        self?.accessibleZipCodes = newSet
      }
      .store(in: &cancellables)
  }

  deinit {
    // Remove notification observers
    NotificationCenter.default.removeObserver(
      self, name: .appDidBecomeActiveForLocationCheck, object: nil)
    NotificationCenter.default.removeObserver(
      self, name: Notification.Name("UploadProgressUpdated"), object: nil)

    // Remove Firestore listener
    pinsListener?.remove()

    #if DEBUG
    print(
      "[MapViewModel] Deinitialized and unsubscribed from notifications and Firestore listener."
    )
    #endif
  }

  @objc private func updateUploadProgress(notification: Notification) {
    if let progress = notification.userInfo?["progress"] as? Double {
      Task { @MainActor in
        self.uploadProgress = progress / 100.0
      }
    }
  }

  @objc private func handleAppDidBecomeActive() {
    #if DEBUG
    print("[MapViewModel] App active - NO automatic location check.")
    #endif
    // Do nothing automatically - user must explicitly request location
  }

  private func loadPins() {
    #if DEBUG
    print("[MapViewModel] Setting up real-time pins listener")
    #endif

    // Remove existing listener
    pinsListener?.remove()

    // Calculate region bounds for listener
    let safeCenter = sanitizeCoordinate(region.center)

    // Calculate radius based on span (in km)
    // Approximate: 1 degree latitude ≈ 111 km
    let latRadiusKm = (region.span.latitudeDelta / 2.0) * 111.0
    let lonRadiusKm = (region.span.longitudeDelta / 2.0) * 111.0 * max(0.0, cos(safeCenter.latitude * .pi / 180.0))
    var radiusKm = max(latRadiusKm, lonRadiusKm) * 1.5  // Add 50% buffer

    // Clamp to a sane maximum to avoid invalid query bounds
    let maxQueryRadiusKm = 2000.0
    radiusKm = min(radiusKm, maxQueryRadiusKm)

    // Calculate approximate bounds (1 degree latitude ≈ 111 km)
    let latDelta = radiusKm / 111.0
    let lonDelta = radiusKm / (111.0 * cos(safeCenter.latitude * .pi / 180.0))

    let minLat = safeCenter.latitude - latDelta
    let maxLat = safeCenter.latitude + latDelta
    let minLon = safeCenter.longitude - lonDelta
    let maxLon = safeCenter.longitude + lonDelta

    #if DEBUG
    print("[MapViewModel] Setting up listener for region: lat [\(minLat), \(maxLat)], lon [\(minLon), \(maxLon)]")
    #endif

    // Set up real-time listener for pins in this region
    let query = Firestore.firestore().collection("pins")
      .whereField("latitude", isGreaterThan: minLat)
      .whereField("latitude", isLessThan: maxLat)
      .limit(to: 500)

    pinsListener = query.addSnapshotListener { [weak self] snapshot, error in
      guard let self = self else { return }

      if let error = error {
        #if DEBUG
        print("[MapViewModel] Listener error: \(error.localizedDescription)")
        #endif
        Task { @MainActor in
          self.showError("Failed to listen for pins: \(error.localizedDescription)")
        }
        return
      }

      guard let documents = snapshot?.documents else {
        #if DEBUG
        print("[MapViewModel] No documents in snapshot")
        #endif
        return
      }

      // Process documents and filter by longitude client-side
      let centerLocation = CLLocation(latitude: safeCenter.latitude, longitude: safeCenter.longitude)

      let pins = documents.compactMap { document -> Pin? in
        let data = document.data()

        guard let latitude = data["latitude"] as? Double,
          let longitude = data["longitude"] as? Double,
          let typeString = data["type"] as? String,
          let videoURL = data["videoURL"] as? String,
          let userId = data["userId"] as? String
        else {
          return nil
        }

        // Filter by longitude bounds
        guard longitude >= minLon && longitude <= maxLon else {
          return nil
        }

        // Calculate actual distance to filter by radius
        let pinLocation = CLLocation(latitude: latitude, longitude: longitude)
        let distanceKm = centerLocation.distance(from: pinLocation) / 1000.0

        guard distanceKm <= radiusKm else {
          return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let incidentType = IncidentType.fromFirestoreType(typeString)
        let zipCode = data["zipCode"] as? String ?? ""

        return Pin(
          id: document.documentID,
          coordinate: coordinate,
          incidentType: incidentType,
          videoURL: videoURL,
          userId: userId,
          zipCode: zipCode
        )
      }

      Task { @MainActor in
        let oldCount = self.pins.count
        self.pins = pins

        #if DEBUG
        print("[MapViewModel] Real-time listener updated: \(oldCount) → \(pins.count) pins")
        #endif

        // Update last queried region
        self.lastQueriedRegion = self.region
      }
    }
  }
  
  /// Refreshes pins for the current map region
  /// Called when the map region changes significantly
  @MainActor
  func refreshPinsForCurrentRegion() {
    loadPins()
  }

  @MainActor
  private func fetchCurrentLocation() {
    if isLocationAuthorized {
      #if DEBUG
      print("[MapViewModel] Fetching current location")
      #endif
      locationManager.requestLocation()
    } else {
      #if DEBUG
      print("[MapViewModel] Cannot fetch location: not authorized")
      #endif
    }
  }

  @MainActor
  func centerMapOnUserLocation() {
    guard let userLocation = userLocation else {
      showAlert = true
      alertMessage = "Unable to determine your location"
      return
    }

    let newCenteredRegion = MKCoordinateRegion(
      center: userLocation.coordinate,
      span: MKCoordinateSpan(latitudeDelta: 0.0011, longitudeDelta: 0.0011)
    )
    self.region = newCenteredRegion  // Update the ViewModel's main region state
    self.mapRegion = newCenteredRegion  // Signal the MapView to update
  }

  func continueWithLimitedFunctionality() {
    UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")
    showAlert = true
    alertMessage =
      "Some features like pin dropping will be unavailable without location access. Enable it later in Settings."
  }

  @objc private func refreshLocationPermissions() {
    Task {
      let servicesEnabled = await checkLocationServicesEnabledAsync()
      await MainActor.run {
        self.isLocationServicesEnabled = servicesEnabled
        #if DEBUG
        print(
          "[MapViewModel] App returned to foreground, relying on delegate for authorization status")
        #endif
      }
    }
  }

  /// Call from MainTabView.onAppear for one-time first launch prompt.
  @MainActor
  func ensureInitialPermissionPrompt() {
    #if DEBUG
    print("[MapViewModel] Ensuring initial permission prompt")
    #endif
    // Perform the check off-thread and then act on the result
    Task {
          let status = await getAuthorizationStatusAsync()

      await MainActor.run {
        switch status {
        case .notDetermined:
          #if DEBUG
          print("[MapViewModel] Requesting location permission on initial load")
          #endif
          self.isRequestingLocation = true
          self.locationManager.requestWhenInUseAuthorization()
        default:
          #if DEBUG
          print(
            "[MapViewModel] Permission already determined: \(status.rawValue). Forcing a refresh check"
          )
          #endif
          Task { await self.forceLocationPermissionCheck() }
        }
      }
    }
  }

  /// Ultra-fast instant reporting: Create pin immediately, upload video in background
  func dropPinInstantReport(for incidentType: IncidentType, videoURL: URL? = nil) async throws {
    #if DEBUG
    print("[MapViewModel] Starting ultra-fast instant reporting...")
    #endif

    guard let currentPendingCoordinate = pendingCoordinate,
          let currentUserId = Auth.auth().currentUser?.uid
    else {
      await MainActor.run {
        showAlert = true
        alertMessage = "Unable to drop pin. Please try again."
        showingIncidentPicker = false
      }
      throw NSError(domain: "MapViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing coordinate or user ID"])
    }

    let pinCoordinate = currentPendingCoordinate
    let pinId = UUID().uuidString

    #if DEBUG
    print("[MapViewModel] Instant pin ID: \(pinId) at \(pinCoordinate.latitude), \(pinCoordinate.longitude)")
    #endif

    // Clear pending state immediately for instant feedback
    await MainActor.run {
      self.pendingCoordinate = nil
      self.showingIncidentPicker = false
      self.uploadProgress = 0.1  // Show immediate progress
    }

    // Create instant pin (no video initially)
    let success = try await StorageUploader.createInstantPin(
      pinId: pinId,
      coordinate: pinCoordinate,
      incidentType: incidentType,
      localURL: videoURL
    )

    if success {
      // Add pin to local map immediately (will be updated when video uploads)
      await MainActor.run {
        let newPin = Pin(
          id: pinId,
          coordinate: pinCoordinate,
          incidentType: incidentType,
          videoURL: "",  // Empty initially
          userId: currentUserId
        )
        self.pins.append(newPin)
        self.uploadProgress = 1.0  // Instant completion feedback

        // Clear progress after brief success indication
        Task {
          try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
          await MainActor.run {
            self.uploadProgress = 0
          }
        }
      }

      #if DEBUG
      print("[MapViewModel] Instant pin created successfully - video uploading in background")
      #endif

      // Get zip code for the pin location for notifications
      let pinLocation = CLLocation(latitude: pinCoordinate.latitude, longitude: pinCoordinate.longitude)
      let pinZipCode = await getCurrentLocationZipCode(from: pinLocation) ?? authManager.currentUserProfile?.originalZipCode ?? ""

      // Send instant notifications with correct zip code
      let instantPin = Pin(
        id: pinId,
        coordinate: pinCoordinate,
        incidentType: incidentType,
        videoURL: "",
        userId: currentUserId,
        zipCode: pinZipCode
      )
      await sendZipCodeNotifications(for: instantPin)
    }
  }

  func dropPinWithVideo(for incidentType: IncidentType, videoURL: URL) async throws {
    #if DEBUG
    print("[MapViewModel] Starting video upload process...")
    #endif

    // Check if too many uploads are already in progress
    if activeUploads >= 2 {
      await MainActor.run {
        showAlert = true
        alertMessage = "Please wait for current uploads to complete before dropping more pins."
        showingIncidentPicker = false
      }
      throw NSError(
        domain: "MapViewModel", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Too many concurrent uploads"])
    }

    guard let currentPendingCoordinate = pendingCoordinate,
      let currentUserId = Auth.auth().currentUser?.uid
    else {
      #if DEBUG
      print("[MapViewModel] Missing coordinate or user ID")
      #endif
      await MainActor.run {
        showAlert = true
        alertMessage = "Unable to drop pin. Please try again."
        showingIncidentPicker = false
      }
      throw NSError(
        domain: "MapViewModel", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing coordinate or user ID"])
    }

    // Store coordinate locally for this specific pin operation
    let pinCoordinate = currentPendingCoordinate
    let pinId = UUID().uuidString

    #if DEBUG
    print(
      "[MapViewModel] Uploading video for incident type: \(incidentType.title) at \(pinCoordinate.latitude), \(pinCoordinate.longitude)"
    )
    print("[MapViewModel] Generated pin ID: \(pinId)")
    #endif

    // Increment active uploads counter and clear pending state - DO THIS FIRST
    await MainActor.run {
      self.activeUploads += 1
      self.pendingCoordinate = nil
      self.pendingVideoData = nil
      self.showingIncidentPicker = false
      self.uploadProgress = 0.3  // Show immediate progress
    }

    // Create pin immediately and add to local array to show on map during upload
    await MainActor.run {
      let newPin = Pin(
        id: pinId,
        coordinate: pinCoordinate,
        incidentType: incidentType,
        videoURL: "",  // Empty initially, will be updated after upload
        userId: currentUserId
      )

      self.pins.append(newPin)
      #if DEBUG
      print("[MapViewModel] Pin created and displayed on map, starting upload...")
      #endif
    }

    // Perform upload in background task to avoid blocking
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      Task.detached(priority: .userInitiated) {
        do {
          // Upload video to Firebase Storage
          let storageRef = Storage.storage().reference().child("videos/\(pinId).mp4")

          // Create metadata
          let metadata = StorageMetadata()
          metadata.contentType = "video/mp4"

          #if DEBUG
          print("[MapViewModel] Starting upload task...")
          #endif

          // Start the upload task
          let uploadTask = storageRef.putFile(from: videoURL, metadata: metadata)

          // Store handles for cleanup
          var progressHandle: String?
          var successHandle: String?
          var failureHandle: String?

          // Monitor upload progress with throttled updates
          var lastProgressUpdate: TimeInterval = 0
          progressHandle = uploadTask.observe(.progress) { snapshot in
            let now = Date().timeIntervalSince1970
            let completedUnitCount = snapshot.progress?.completedUnitCount ?? 0
            let totalUnitCount = snapshot.progress?.totalUnitCount ?? 1
            let percentComplete = Double(completedUnitCount) / Double(totalUnitCount)

            // Throttle progress updates to every 0.2 seconds to reduce UI load
            if now - lastProgressUpdate > 0.2 {
              lastProgressUpdate = now
              Task { @MainActor in
                // Map progress from 0.3 to 0.9 (leaving room for Firestore save)
                self.uploadProgress = 0.3 + (percentComplete * 0.6)
              }
            }
          }

          successHandle = uploadTask.observe(.success) { _ in
            #if DEBUG
            print("[MapViewModel] Upload task completed successfully")
            #endif

            // Clean up observers
            if let progressHandle = progressHandle {
              uploadTask.removeObserver(withHandle: progressHandle)
            }
            if let failureHandle = failureHandle {
              uploadTask.removeObserver(withHandle: failureHandle)
            }

            // Get download URL after successful upload
            storageRef.downloadURL { url, error in
              // Store the continuation locally to avoid using it in an async context
              let localContinuation = continuation

              if let error = error {
                #if DEBUG
                print("[MapViewModel] Failed to get download URL: \(error.localizedDescription)")
                #endif
                localContinuation.resume(throwing: error)
                return
              }

              guard let downloadURL = url else {
                #if DEBUG
                print("[MapViewModel] Download URL is nil")
                #endif
                localContinuation.resume(
                  throwing: NSError(
                    domain: "StorageError", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                return
              }

              #if DEBUG
              print("[MapViewModel] Got download URL: \(downloadURL.absoluteString)")
              #endif

              // Show final progress step
              Task { @MainActor in
                self.uploadProgress = 0.95
              }

              // Get zip code for the pin location (not user's home zip code)
              Task { @MainActor in
                // Get zip code for the pin's coordinate location using reverse geocoding
                let pinLocation = CLLocation(latitude: pinCoordinate.latitude, longitude: pinCoordinate.longitude)
                let pinZipCode = await self.getCurrentLocationZipCode(from: pinLocation) ?? self.authManager.currentUserProfile?.originalZipCode ?? ""

                // Create pin data
                let pinData: [String: Any] = [
                  "id": pinId,
                  "latitude": pinCoordinate.latitude,
                  "longitude": pinCoordinate.longitude,
                  "type": incidentType.firestoreType,
                  "videoURL": downloadURL.absoluteString,
                  "userId": currentUserId,
                  "timestamp": FieldValue.serverTimestamp(),
                  "zipCode": pinZipCode,  // Use pin's location zip code, not user's home zip
                ]

                // Add pin to Firestore using async/await
                let db = Firestore.firestore()

                do {
                  // Use modern async/await API instead of completion handler
                  try await db.collection("pins").document(pinId).setData(pinData)
                  
                  #if DEBUG
                  print("[MapViewModel] Successfully saved pin to Firestore")
                  #endif

                  // Update the existing pin with video URL and zip code
                  if let index = self.pins.firstIndex(where: { $0.id == pinId }) {
                    self.pins[index] = Pin(
                      id: pinId,
                      coordinate: pinCoordinate,
                      incidentType: incidentType,
                      videoURL: downloadURL.absoluteString,
                      userId: currentUserId,
                      zipCode: pinZipCode
                    )
                    #if DEBUG
                    print("[MapViewModel] Updated pin with video URL")
                    #endif
                  }

                  self.activeUploads = max(0, self.activeUploads - 1)
                  self.uploadProgress = 1.0

                  // Clear progress after a brief delay
                  Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                    // Ensure we're on the main actor
                    await MainActor.run {
                      self.uploadProgress = 0
                    }
                  }

                  // Send notifications to users in the same zip code
                  await self.sendZipCodeNotifications(
                    for: Pin(
                      id: pinId,
                      coordinate: pinCoordinate,
                      incidentType: incidentType,
                      videoURL: downloadURL.absoluteString,
                      userId: currentUserId,
                      zipCode: pinZipCode
                    ))

                  // Resume continuation successfully
                  continuation.resume(returning: ())
                } catch {
                  #if DEBUG
                  print(
                    "[MapViewModel] Failed to save pin to Firestore: \(error.localizedDescription)"
                  )
                  #endif
                  // Remove the pin from local array since Firestore save failed
                  self.pins.removeAll { $0.id == pinId }
                  self.activeUploads = max(0, self.activeUploads - 1)
                  self.uploadProgress = 0
                  
                  // Resume continuation with error
                  continuation.resume(throwing: error)
                }
              }
            }
          }

          failureHandle = uploadTask.observe(.failure) { snapshot in
            #if DEBUG
            print("[MapViewModel] Upload task failed")
            #endif

            // Store the continuation locally to avoid using it in an async context
            let localContinuation = continuation

            // Clean up observers
            if let progressHandle = progressHandle {
              uploadTask.removeObserver(withHandle: progressHandle)
            }
            if let successHandle = successHandle {
              uploadTask.removeObserver(withHandle: successHandle)
            }

            // Remove the pin from local array since upload failed
            Task { @MainActor in
              self.pins.removeAll { $0.id == pinId }
              self.activeUploads = max(0, self.activeUploads - 1)
              self.uploadProgress = 0
            }

            if let error = snapshot.error as? NSError {
              #if DEBUG
              print("[MapViewModel] Upload error: \(error.localizedDescription)")
              #endif
              localContinuation.resume(throwing: error)
            } else {
              #if DEBUG
              print("[MapViewModel] Unknown upload error")
              #endif
              localContinuation.resume(
                throwing: NSError(
                  domain: "StorageError", code: -2,
                  userInfo: [NSLocalizedDescriptionKey: "Unknown upload error"]))
            }
          }
        }
      }
    }
  }

  @MainActor
  func upload(draft: PinDraft) async {
    #if DEBUG
    print("[MapViewModel] Starting upload process for pin with video: \(draft.videoURL != nil)")
    #endif

    // Reset and initialize upload progress
    await MainActor.run {
      uploadProgress = 0
      activeUploads += 1
    }

    // Check if user is anonymous AND trying to upload a video
    if authState.isAnonymous && draft.videoURL != nil {
      #if DEBUG
      print("[MapViewModel] Anonymous user attempted video upload - blocking")
      #endif
      await MainActor.run {
        uploadProgress = 0
        activeUploads = max(0, activeUploads - 1)
      }
      showError("Guests cannot upload videos.")
      reportStep = nil  // Dismiss the report sheet
      return
    }

    do {
      let pinId = UUID().uuidString
      #if DEBUG
      print("[MapViewModel] Generated pin ID: \(pinId)")
      #endif

      // Check if video file exists before attempting upload
      if let videoURL = draft.videoURL {
        if !FileManager.default.fileExists(atPath: videoURL.path) {
          #if DEBUG
          print("[MapViewModel] ERROR: Video file does not exist at path: \(videoURL.path)")
          #endif
          await MainActor.run {
            uploadProgress = 0
            activeUploads = max(0, activeUploads - 1)
          }
          showError(
            "Selected video file is no longer available. Please try selecting another video.")
          return
        }
        #if DEBUG
        print("[MapViewModel] Video file exists at: \(videoURL.path)")
        #endif
        
        // Set initial progress to show upload has started
        await MainActor.run {
          uploadProgress = 0.1
        }
      } else {
        #if DEBUG
        print("[MapViewModel] No video attached - creating pin without video")
        #endif
      }

      // Upload video if present
      #if DEBUG
      print("[MapViewModel] Calling StorageUploader.uploadIfNeeded...")
      #endif
      let remoteURL = try await StorageUploader.uploadIfNeeded(
        pinId: pinId, localURL: draft.videoURL)
      #if DEBUG
      print("[MapViewModel] StorageUploader completed. Remote URL: '\(remoteURL)'")
      #endif

      // Save pin to Firestore FIRST
      #if DEBUG
      print("[MapViewModel] Saving pin to Firestore...")
      #endif
      
      // Get zip code for the pin location
      let pinLocation = CLLocation(latitude: draft.coordinate.latitude, longitude: draft.coordinate.longitude)
      let zipCode = await getCurrentLocationZipCode(from: pinLocation) ?? authManager.currentUserProfile?.originalZipCode ?? ""
      
      try await FirestorePins.addPin(
        id: pinId,
        coord: draft.coordinate,
        type: draft.incidentType,
        videoURL: remoteURL,
        zipCode: zipCode)
      #if DEBUG
      print("[MapViewModel] Pin saved to Firestore successfully")
      #endif

      // The real-time Firestore listener will automatically update the local pins array
      // when the new pin is added to the database
      #if DEBUG
      print("[MapViewModel] Pin uploaded successfully - real-time listener will show it")
      #endif

      // Send notifications - create pin with the correct zip code
      var draftWithZip = draft
      draftWithZip.zipCode = zipCode
      let newPin = draftWithZip.makePin(id: pinId, remote: remoteURL)
      await sendZipCodeNotifications(for: newPin)

      // Mark upload as complete
      await MainActor.run {
        uploadProgress = 1.0
        activeUploads = max(0, activeUploads - 1)
        
        // Clear progress after brief success indication
        Task {
          try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
          await MainActor.run {
            uploadProgress = 0
          }
        }
      }

      reportStep = nil  // Close sheet
      #if DEBUG
      print("[MapViewModel] Upload process completed successfully")
      #endif

    } catch {
      #if DEBUG
      print("[MapViewModel] Upload failed with error: \(error)")
      #endif
      if let nsError = error as NSError? {
        #if DEBUG
        print("[MapViewModel] Error domain: \(nsError.domain), code: \(nsError.code)")
        #endif
        #if DEBUG
        print("[MapViewModel] Error userInfo: \(nsError.userInfo)")
        #endif
      }
      
      // Reset progress on error
      await MainActor.run {
        uploadProgress = 0
        activeUploads = max(0, activeUploads - 1)
      }
      
      showError("Failed to create pin: \(error.localizedDescription)")
    }
  }

  // Enhanced zoom to user location function
  func zoomToUserTight() {
    guard let userLocation = userLocation else {
      showAlert = true
      alertMessage = "Unable to determine your location"
      return
    }

    // Sanitize user location coordinate
    let validCoordinate = sanitizeCoordinate(userLocation.coordinate)

    // Zoom to roughly 200 foot radius for precise pin placement
    // 200 feet is approximately 61 meters
    let pinDropRadius = 200 * 0.3048  // Convert feet to meters

    // Calculate span to show roughly the pin drop radius
    // Approx conversion: 1 degree latitude = 111km (111,000m)
    var spanDelta = (pinDropRadius * 1.5) / 111000

    // Validate calculation to prevent NaN
    if spanDelta.isNaN || spanDelta.isInfinite || spanDelta <= 0 {
      spanDelta = 0.001  // Fallback to reasonable zoom
    }

    // Set region with tight zoom focused on user
    let newTightRegion = MKCoordinateRegion(
      center: validCoordinate,
      span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
    )
    self.region = newTightRegion  // Update the ViewModel's main region state
    self.mapRegion = newTightRegion  // Signal the MapView to update
  }

  // Center button zoom function - 500 feet radius as requested
  func centerOnUserWith500FeetRadius() {
    guard let userLocation = userLocation else {
      showAlert = true
      alertMessage = "Unable to determine your location"
      return
    }

    // Sanitize user location coordinate
    let validCoordinate = sanitizeCoordinate(userLocation.coordinate)

    // Zoom to 500 foot radius for center button
    // 500 feet is approximately 152 meters
    let centerRadius = 500 * 0.3048  // Convert feet to meters

    // Calculate span to show roughly the center radius
    // Approx conversion: 1 degree latitude = 111km (111,000m)
    var spanDelta = (centerRadius * 1.5) / 111000

    // Validate calculation to prevent NaN
    if spanDelta.isNaN || spanDelta.isInfinite || spanDelta <= 0 {
      spanDelta = 0.002  // Fallback to reasonable zoom (larger than tight zoom)
    }

    #if DEBUG
    print("[MapViewModel] Centering on user location with 500ft radius: \(validCoordinate)")
    #endif

    // Set region with 500-foot zoom focused on user
    let newCenterRegion = MKCoordinateRegion(
      center: validCoordinate,
      span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
    )
    self.region = newCenterRegion  // Update the ViewModel's main region state
    self.mapRegion = newCenterRegion  // Signal the MapView to update
  }

  // Cycle through multiple map types instead of just two
  func cycleMapType() {
    guard let currentIndex = MapDisplayStyle.allCases.firstIndex(of: mapDisplayStyle) else { return }
    let nextIndex = (currentIndex + 1) % MapDisplayStyle.allCases.count
    setMapDisplayStyle(MapDisplayStyle.allCases[nextIndex])
  }

  func setMapDisplayStyle(_ style: MapDisplayStyle) {
    mapDisplayStyle = style
  }

  // Helper to get icon name for current map type
  func mapTypeIcon() -> String {
    mapDisplayStyle.iconName
  }

  /// Checks if a given coordinate is within 200 feet of the user's current location
  /// - Parameter coordinate: The coordinate to check
  /// - Returns: Boolean indicating if coordinate is within range
  func isWithinPinDropRange(coordinate: CLLocationCoordinate2D) async -> Bool {
    guard let userLocation = await getCurrentLocation() else {
      return false
    }

    let pinLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let distance = userLocation.distance(from: pinLocation)

    // 200 feet in meters (1 foot ≈ 0.3048 meters)
    let pinDropLimit = 200 * 0.3048

    return distance <= pinDropLimit
  }

  // Zoom constraints - aligned with MapViewConstants for consistency
  private let minSpanDelta: CLLocationDegrees = 0.00013  // Must match MapViewConstants.minSpan
  private let maxSpanDelta: CLLocationDegrees = 0.8  // Reasonable max zoom out, less than MapViewConstants.maxZoomDistance

  // MARK: - Pin Creation and Upload
  private func uploadVideoAndCreatePin(videoData: Data, pinDetails: PinDraft) {
    // Check if user is anonymous before proceeding with video operations
    if authState.isAnonymous {
      showError("Guests cannot upload videos.")
      reportStep = nil  // Dismiss the report sheet
      self.authState.isLoading = false  // Reset loading state if any
      return
    }

    self.authState.isLoading = true

    // ... rest of the method ...
  }

  /// Call when the user dismisses an alert presented by the View layer.
  /// Resets the `isShowingAlert` flag and shows the next queued alert if any.
  @MainActor
  func alertDismissed() {
    isShowingAlert = false
    processAlertQueue()
  }

  // Add this enum to clarify location actions
  enum LocationAction {
    case initialPrompt
    case center
    case pinDrop(CLLocationCoordinate2D)
  }

  // Unified location request handler
  func handleLocationAction(_ action: LocationAction) {
    Task {
      let servicesEnabled = await checkLocationServicesEnabledAsync()
      let status = await getAuthorizationStatusAsync()
      await MainActor.run {
        if !servicesEnabled {
          self.alertMessage = "Location services are disabled. Please enable them in Settings."
          self.showAlert = true
          return
        }
        switch status {
        case .notDetermined:
          // Request permission and remember what to do after
          switch action {
          case .center:
            self.shouldCenterAfterAuthorization = true
          case .pinDrop(let coord):
            self.pendingCoordinate = coord
          default: break
          }
          self.locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
          self.alertMessage = "Location access is required. Please enable it in Settings."
          self.showAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
          switch action {
          case .center:
            self.shouldCenterAfterLocationUpdate = true
            self.locationManager.requestLocation()
          case .pinDrop(let coord):
            self.initiatePinDropVerification(at: coord)
          case .initialPrompt:
            // No action needed, permission already granted
            break
          }
        @unknown default:
          break
        }
      }
    }
  }

  // Helper function to clean up invalid pin documents
  @MainActor
  func cleanupInvalidPins() async {
    #if DEBUG
    print("[MapViewModel] Starting cleanup of invalid pins...")
    #endif
    
    // Only clean up pins belonging to the current user
    guard let currentUserId = Auth.auth().currentUser?.uid else {
      #if DEBUG
      print("[MapViewModel] No current user, skipping cleanup")
      #endif
      return
    }
    
    let snapshot = try? await db.collection("pins")
      .whereField("userId", isEqualTo: currentUserId)
      .getDocuments()

    guard let documents = snapshot?.documents else {
      #if DEBUG
      print("[MapViewModel] No documents found for cleanup")
      #endif
      return
    }

    var removedCount = 0
    for document in documents {
      let data = document.data()

      // Check if required fields are missing
      let hasRequiredFields =
        data["id"] != nil && data["latitude"] != nil && data["longitude"] != nil
        && data["type"] != nil && data["userId"] != nil

      if !hasRequiredFields {
        #if DEBUG
        print("[MapViewModel] Removing invalid pin document: \(document.documentID)")
        #endif
        try? await document.reference.delete()
        removedCount += 1
      }
    }

    #if DEBUG
    print("[MapViewModel] Cleanup completed. Removed \(removedCount) invalid pins")
    #endif
    if removedCount > 0 {
      // Refresh pins after cleanup
      loadPins()
    }
  }

  // MARK: - Notification Handling
  private func sendZipCodeNotifications(for pin: Pin) async {
    guard let currentUserProfile = authManager.currentUserProfile else {
      #if DEBUG
      print("[MapViewModel] Cannot send notifications - no current user profile")
      #endif
      return
    }

    let notificationZip = pin.zipCode.isEmpty ? currentUserProfile.zipCode : pin.zipCode
    
    guard !notificationZip.isEmpty else {
      #if DEBUG
      print("[MapViewModel] Cannot send notifications - pin zip code missing")
      #endif
      return
    }
    
    #if DEBUG
    print("[MapViewModel] Sending notifications to users in zip code: \(notificationZip)")
    #endif

    // Send notifications to other users in the same zip code
    await notificationManager.notifyUsersInZipCode(for: pin, zipCode: notificationZip)
  }

  // Helper function to validate and sanitize coordinate values
  private func sanitizeCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    let validLatitude: CLLocationDegrees
    let validLongitude: CLLocationDegrees

    // Check for NaN, infinity, or out-of-bounds values
    if coordinate.latitude.isNaN || coordinate.latitude.isInfinite || coordinate.latitude < -90
      || coordinate.latitude > 90
    {
      validLatitude = 40.7128  // Default to NYC
    } else {
      validLatitude = coordinate.latitude
    }

    if coordinate.longitude.isNaN || coordinate.longitude.isInfinite || coordinate.longitude < -180
      || coordinate.longitude > 180
    {
      validLongitude = -74.0060  // Default to NYC
    } else {
      validLongitude = coordinate.longitude
    }

    return CLLocationCoordinate2D(latitude: validLatitude, longitude: validLongitude)
  }

  // Helper function to validate and sanitize span values
  private func sanitizeSpan(_ span: MKCoordinateSpan) -> MKCoordinateSpan {
    let validLatitudeDelta: CLLocationDegrees
    let validLongitudeDelta: CLLocationDegrees

    // Check for NaN, infinity, or invalid values
    if span.latitudeDelta.isNaN || span.latitudeDelta.isInfinite || span.latitudeDelta <= 0 {
      validLatitudeDelta = 0.01  // Reasonable default
    } else {
      validLatitudeDelta = max(minSpanDelta, min(maxSpanDelta, span.latitudeDelta))
    }

    if span.longitudeDelta.isNaN || span.longitudeDelta.isInfinite || span.longitudeDelta <= 0 {
      validLongitudeDelta = 0.01  // Reasonable default
    } else {
      validLongitudeDelta = max(minSpanDelta, min(maxSpanDelta, span.longitudeDelta))
    }

    return MKCoordinateSpan(latitudeDelta: validLatitudeDelta, longitudeDelta: validLongitudeDelta)
  }

  func startReportFlow(at coord: CLLocationCoordinate2D) {
    reportDraft = PinDraft(coordinate: coord)
    reportStep = .video
  }

  // Method to update a pin's video URL
  func updatePinVideoURL(_ pinId: String, newURL: String) {
    // Update in our local pins array
    if let index = pins.firstIndex(where: { $0.id == pinId }) {
      pins[index] = Pin(
        id: pins[index].id,
        coordinate: pins[index].coordinate,
        incidentType: pins[index].incidentType,
        videoURL: newURL,
        userId: pins[index].userId
      )

      // Also update in Firestore for persistence
      Task {
        do {
          try await FirestorePins.updatePinVideoURL(pinId: pinId, videoURL: newURL)
          #if DEBUG
          print("[MapViewModel] Successfully updated pin \(pinId) with video URL: \(newURL)")
          #endif
        } catch {
          #if DEBUG
          print(
            "[MapViewModel] Error updating pin video URL in Firestore: \(error.localizedDescription)"
          )
          #endif
        }
      }
    }
  }

  // MARK: - Video Metadata Validation

  /// Returns true if the asset is ≤5h old and ≤200ft from the pin location
  @MainActor
  func checkVideoMetadata(asset: PHAsset, pinLocation: CLLocation) async -> Bool {
    guard let creationDate = asset.creationDate,
      let assetLocation = asset.location
    else {
      return false
    }
    // Calculate age in hours
    let hours =
      Calendar.current
      .dateComponents([.hour], from: creationDate, to: Date())
      .hour ?? Int.max
    // Calculate distance in feet
    let feet = assetLocation.distance(from: pinLocation) * 3.28084
    return hours <= 5 && feet <= 200
  }
  
  // MARK: - Premium Video Access Check
  
  /// Checks if the current user can watch a video for a given pin
  /// Returns (canWatch: Bool, shouldPromptPremium: Bool, message: String?)
  @MainActor
  func canWatchVideo(for pin: Pin) async -> (canWatch: Bool, shouldPromptPremium: Bool, message: String?) {
    // Get current user profile
    guard let userProfile = authManager.currentUserProfile else {
      #if DEBUG
      print("[MapViewModel] Video access denied - no user profile")
      #endif
      return (false, false, "Please sign in to watch videos")
    }
    
    // Premium users can watch all videos
    if userProfile.isPremium {
      #if DEBUG
      print("[MapViewModel] Video access granted - user is premium")
      #endif
      return (true, false, nil)
    }
    
    // Allow videos with empty zip codes (legacy or same-session)
    if pin.zipCode.isEmpty {
      #if DEBUG
      print("[MapViewModel] Video access granted - pin has no zip code (legacy/same-session)")
      #endif
      return (true, false, nil)
    }

    if zipAccessManager.hasAccess(to: pin.zipCode) {
      #if DEBUG
      print("[MapViewModel] Video access granted via ZipAccessManager for zip \(pin.zipCode)")
      #endif
      return (true, false, nil)
    }
    
    #if DEBUG
    print("[MapViewModel] Video access DENIED - pin zip \(pin.zipCode) not in allowed zones")
    #endif
    
    // Pin is outside allowed zip codes - offer to purchase this specific zip or upgrade to premium
    return (false, true, "This video is in zip code \(pin.zipCode). Unlock this area or upgrade to Premium for unlimited access.")
  }
  
  /// Gets the zip code for a given location using reverse geocoding
  private func getCurrentLocationZipCode(from location: CLLocation) async -> String? {
    return await withCheckedContinuation { continuation in
      let geocoder = CLGeocoder()
      geocoder.reverseGeocodeLocation(location) { placemarks, error in
        if let error = error {
          #if DEBUG
          print("[MapViewModel] Reverse geocoding error: \(error.localizedDescription)")
          #endif
          continuation.resume(returning: nil)
          return
        }
        
        let zipCode = placemarks?.first?.postalCode
        #if DEBUG
        print("[MapViewModel] Reverse geocoded zip code: \(zipCode ?? "nil")")
        #endif
        continuation.resume(returning: zipCode)
      }
    }
  }
}

// MARK: - CLLocationManagerDelegate
extension MapViewModel: CLLocationManagerDelegate {
  nonisolated
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
  {
    // Capture the status in the nonisolated context
    let status = manager.authorizationStatus

    // Process the status on the MainActor where UI updates happen
    Task {
      // Get location services enabled state off the main thread
      let servicesEnabled = await self.checkLocationServicesEnabledAsync()

      await MainActor.run {
        #if DEBUG
        print("[MapViewModel] Delegate: Authorization status changed to: \(status.rawValue)")
        #endif
        self.isLocationServicesEnabled = servicesEnabled
        self.isLocationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        self.isRequestingLocation = false  // No longer actively requesting permission itself

        if !self.isLocationServicesEnabled {
          self.alertMessage = "Location services are disabled. Please enable them in Settings."
          self.showAlert = true
          return
        }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
          #if DEBUG
          print("[MapViewModel] Delegate: Authorized.")
          #endif
          self.isLimitedFunctionalityDueToLocationDenial = false  // Clear the flag
          UserDefaults.standard.set(false, forKey: "userDeclinedLocationPermissions")  // Clear user default
          // NEVER automatically get location - wait for explicit requests
          if self.shouldCenterAfterAuthorization {
            self.centerOnUserWith500FeetRadius()
            self.shouldCenterAfterAuthorization = false
          }
          if let coord = self.pendingCoordinate {
            self.initiatePinDropVerification(at: coord)
            self.pendingCoordinate = nil
          }
        case .denied, .restricted:
          #if DEBUG
          print("[MapViewModel] Delegate: Denied or restricted.")
          #endif
          self.alertMessage =
            "Location access is required for core features. Please enable it in Settings."
          self.showAlert = true
          // Ensure userLocation is nil if access is denied to prevent using stale data
          self.userLocation = nil
          self.isLimitedFunctionalityDueToLocationDenial = true  // Set the flag
          UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")  // Set user default
        case .notDetermined:
          #if DEBUG
          print(
            "[MapViewModel] Delegate: Status became .notDetermined. This shouldn't usually happen after an initial request."
          )
          #endif
        @unknown default:
          #if DEBUG
          print("[MapViewModel] Delegate: Unknown authorization status: \(status.rawValue)")
          #endif
        }

        // If we're not in live-tracking mode, stop updates after we get a fix
        if !self.isTrackingUserLocation {
          self.locationManager.stopUpdatingLocation()
        }
      }
    }
  }

  nonisolated
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
  {
    guard let location = locations.last else { return }
    Task { @MainActor in
      // Store previous location to check if it's meaningfully different
      let previousLocation = self.userLocation

      // Update userLocation
      self.userLocation = location
      #if DEBUG
      print("[MapViewModel] Delegate: Location updated: \(location.coordinate)")
      #endif
      self.zipAccessManager.updateTravelAccess(with: location)

      // Break down complex conditions into separate variables
      let isLatitudeNYC = self.region.center.latitude == 40.7128
      let isLongitudeNYC = self.region.center.longitude == -74.0060
      let isMapAtDefaultNYC = isLatitudeNYC && isLongitudeNYC

      let isLatitudeEquator = self.region.center.latitude == 0
      let isLongitudeEquator = self.region.center.longitude == 0
      let isMapAtDefaultEquator = isLatitudeEquator && isLongitudeEquator

      let isFirstLocationFix = previousLocation == nil
      let shouldUpdateRegionToUserLocation =
        isFirstLocationFix || isMapAtDefaultNYC || isMapAtDefaultEquator

      if shouldUpdateRegionToUserLocation {
        #if DEBUG
        print(
          "[MapViewModel] First location fix or map is at a default. Centering on user: \(location.coordinate)"
        )
        #endif
        // Use a span consistent with other user-centric views, e.g., from centerOnUserLocation or a sensible default.
        // For this example, using a span similar to the initial MapView span.
        let defaultUserSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)  // A reasonable zoom level for user location
        let newRegion = MKCoordinateRegion(
          center: location.coordinate,
          span: defaultUserSpan
        )
        self.region = newRegion  // Update the ViewModel's main region state
        self.mapRegion = newRegion  // Signal the MapView to update
        #if DEBUG
        print(
          "[MapViewModel] Set initial map region to user location: \(newRegion.center), span: \(newRegion.span.latitudeDelta)"
        )
        #endif
      }

      // If in tracking mode, update the region to follow the user in real-time
      // This ensures the map smoothly follows the user like a navigation app
      if self.isTrackingUserLocation {
        #if DEBUG
        print("[MapViewModel] Tracking mode active - updating map to follow user")
        #endif
        // Keep the current zoom level (span) but update the center to follow the user
        let trackingRegion = MKCoordinateRegion(
          center: location.coordinate,
          span: self.region.span
        )
        self.region = trackingRegion
        // Note: We don't set mapRegion here because the MapView's userTrackingMode
        // will handle the smooth following animation automatically
      }

      // Center map if explicitly requested after authorization
      if self.shouldCenterAfterAuthorization {
        self.centerOnUserWith500FeetRadius()
        self.shouldCenterAfterAuthorization = false
      }

      // Center map if explicitly requested from center button
      if self.shouldCenterAfterLocationUpdate {
        self.centerOnUserWith500FeetRadius()
        self.shouldCenterAfterLocationUpdate = false
      }

      // Break down notification check into separate variables
      let isNewLocation = previousLocation == nil
      let hasMoved = previousLocation != nil && (previousLocation!.distance(from: location) > 1.0)  // 1 meter threshold
      let shouldNotify = isNewLocation || hasMoved

      if shouldNotify {
        NotificationCenter.default.post(name: Notification.Name("LocationUpdated"), object: nil)
        #if DEBUG
        print("[MapViewModel] Posted LocationUpdated notification")
        #endif
      }
      
      self.updatePresenceIfNeeded(with: location)
    }
  }

  private func updatePresenceIfNeeded(with location: CLLocation) {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    
    if let lastLocation = lastPresenceLocation,
      location.distance(from: lastLocation) < presenceUpdateDistanceThreshold,
      let lastDate = lastPresenceUpdateDate,
      Date().timeIntervalSince(lastDate) < presenceUpdateInterval
    {
      return
    }
    
    Task {
      guard let zip = await getCurrentLocationZipCode(from: location), !zip.isEmpty else { return }
      
      if zip == lastPresenceZipCode,
        let lastDate = lastPresenceUpdateDate,
        Date().timeIntervalSince(lastDate) < 300
      {
        lastPresenceLocation = location
        return
      }
      
      lastPresenceZipCode = zip
      lastPresenceLocation = location
      lastPresenceUpdateDate = Date()
      
      do {
        try await db.collection("users").document(userId).updateData([
          "currentZipCode": zip,
          "currentZipUpdatedAt": Timestamp(date: Date())
        ])
        
        if var profile = authManager.currentUserProfile {
          profile.updateCurrentZip(zip)
          authManager.currentUserProfile = profile
        }
      } catch {
        #if DEBUG
        print("[MapViewModel] Error updating presence zip: \(error.localizedDescription)")
        #endif
      }
    }
  }

  nonisolated
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
  {
    #if DEBUG
    print("[MapViewModel] Delegate: Failed to get location: \(error.localizedDescription)")
    #endif
    Task { @MainActor in
      self.isRequestingLocation = false
      self.shouldCenterAfterLocationUpdate = false  // Clear the flag on error
      // Optionally show an alert to the user
      // self.alertMessage = "Failed to get location: \(error.localizedDescription)"
      // self.showAlert = true
    }
  }

  // Add a helper method to access authorizationStatus safely in other parts of the code
  func getCurrentAuthorizationStatus() -> CLAuthorizationStatus {
    // Avoid touching the MainActor-isolated `locationManager` from the
    // non-isolated context by instantiating a fresh manager here.
    return CLLocationManager().authorizationStatus
  }
}

enum ReportStep: Int, Identifiable {
  case video
  var id: Int { rawValue }
}

