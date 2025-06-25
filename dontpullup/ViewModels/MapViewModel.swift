import AVKit
@preconcurrency import CoreLocation
@preconcurrency import Dispatch
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import MapKit
import Photos
import SwiftUI
@preconcurrency import UIKit

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
  @Published var mapType: MKMapType = .standard
  @Published var mapRegion: MKCoordinateRegion?
  @Published var showingOnlyMyPins = false
  @Published var pendingCoordinate: CLLocationCoordinate2D?
  @Published var isRequestingLocation = false
  @Published var currentlyPlayingVideoId: String?
  @Published var pendingVideoData: Data?
  @Published var uploadProgress: Double = 0
  @Published var reportStep: ReportStep?  // nil = no sheet
  @Published var reportDraft = PinDraft()  // holds coord/type/url
  @Published var isLimitedFunctionalityDueToLocationDenial: Bool = false
  @Published var activeUploads: Int = 0  // Track number of active uploads
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
  private let notificationManager = NotificationManager.shared
  private let authManager = AuthenticationManager.shared

  // MARK: - Private Properties
  private let locationManager = CLLocationManager()
  private let db = Firestore.firestore()

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

      // Apply zip code restriction for non-premium users
      if let userProfile = authManager.currentUserProfile, !userProfile.isPremium {
        // For non-premium users, only show pins in their original zip code
        let pinInUserZipCode = pin.zipCode == userProfile.originalZipCode

        // Show pins that pass both the type filter and are in user's original zip code
        return passesTypeFilter && pinInUserZipCode
      }

      // Premium users see all pins that match their type filters
      return passesTypeFilter
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
    print("[MapViewModel] Flag report submitted successfully for video \(videoId)")
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
    mapType = mapType == .standard ? .hybrid : .standard
    mapRegion = mapRegion
  }

  func toggleEditMode() {
    isEditMode.toggle()
  }

  // MARK: - Zoom helpers
  func zoomIn() {
    print("[MapViewModel] Zoom in requested")
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

    print(
      "[MapViewModel] Setting zoom region from \(self.region.span.latitudeDelta) to \(newRegion.span.latitudeDelta)"
    )

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
    print("[MapViewModel] Zoom out requested")
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

    print(
      "[MapViewModel] Setting zoom region from \(self.region.span.latitudeDelta) to \(newRegion.span.latitudeDelta)"
    )

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

    print("[MapViewModel] Centering on user location: \(validCoordinate)")

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
    guard await checkLocationServicesEnabled() else { return false }

    // 3. If we already have a fix, we're done.
    if userLocation != nil { return true }

    // 4. Otherwise request a one-time location and await the helper.
    locationManager.requestLocation()

    //   Re-use the existing getCurrentLocation() helper which already
    //   handles its own timeout and MainActor isolation.
    let location = await getCurrentLocation()
    return location != nil
  }

  /// Toggles continuous location tracking mode
  func toggleLocationTracking() {
    isTrackingUserLocation.toggle()

    if isTrackingUserLocation {
      // Start continuous updates if tracking is enabled
      locationManager.startUpdatingLocation()
      // Also center the map on the user
      if let location = userLocation {
        mapRegion = MKCoordinateRegion(
          center: location.coordinate,
          span: MKCoordinateSpan(latitudeDelta: 0.0011, longitudeDelta: 0.0011)
        )
      }
    } else {
      // Stop continuous updates if tracking is disabled
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
      print("[MapViewModel] Downloaded video data from \(remoteURL)")
    } catch {
      print("[MapViewModel] Error caching video: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Alert handling
  func showError(_ message: String) {
    Task { @MainActor in
      // Add message to queue and try to show
      alertQueue.append(message)
      processAlertQueue()
    }
  }

  @MainActor
  private func processAlertQueue() {
    // Only proceed if we're not already showing an alert and we have messages
    guard !isShowingAlert, !alertQueue.isEmpty else { return }

    // Get the next message and mark as showing
    alertMessage = alertQueue.removeFirst()
    isShowingAlert = true
    showAlert = true
  }

  func clearPendingData() {
    // Clear pending state regardless of upload progress if explicitly called
    // This ensures cleanup happens even after timeout errors
    print("[MapViewModel] Clearing pending operation data")

    // Clear all pending state in a single batch update
    pendingCoordinate = nil
    pendingVideoData = nil
    uploadProgress = 0
    showingIncidentPicker = false
    reportStep = nil

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

  /// Gets the current authorization status safely off the main thread
  private func getAuthorizationStatus() async -> CLAuthorizationStatus {
    // Always run this in a detached task to ensure it's completely off the main thread
    // and properly isolated from the MainActor constraints
    return await Task.detached(priority: .userInitiated) { () -> CLAuthorizationStatus in
      // Create a new instance of CLLocationManager rather than accessing self.locationManager
      // to ensure we're completely isolated from MainActor constraints
      return CLLocationManager().authorizationStatus
    }.value
  }

  /// Checks if location services are enabled safely off the main thread
  private func checkLocationServicesEnabled() async -> Bool {
    // Run in a detached task to ensure it's completely off the main thread
    return await Task.detached(priority: .userInitiated) { () -> Bool in
      return CLLocationManager.locationServicesEnabled()
    }.value
  }

  private func checkInitialLocationStatus() async {
    // Execute CoreLocation queries away from the main thread first
    let servicesEnabled = await checkLocationServicesEnabled()
    let status = await getAuthorizationStatus()

    // Publish results back on the main actor
    await MainActor.run {
      self.isLocationServicesEnabled = servicesEnabled
      self.isLocationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
      print(
        "[MapViewModel] Initial check: Services enabled: \(servicesEnabled), Authorized: \(self.isLocationAuthorized) (Status: \(status.rawValue))"
      )

      if !self.isLocationServicesEnabled
        || (!self.isLocationAuthorized && (status == .denied || status == .restricted))
      {
        self.isLimitedFunctionalityDueToLocationDenial = true
        // We can also set the UserDefaults flag here if appropriate, though a dedicated func might be better
        // UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")
        print(
          "[MapViewModel] Initial check: Location services/auth not sufficient. Limited functionality mode ON."
        )
      } else if self.isLocationAuthorized {
        self.isLimitedFunctionalityDueToLocationDenial = false
        // UserDefaults.standard.set(false, forKey: "userDeclinedLocationPermissions")
        print("[MapViewModel] Initial check: Location authorized. Limited functionality mode OFF.")
      } else {
        // If status is .notDetermined, we don't set isLimitedFunctionalityDueToLocationDenial yet.
        // It will be determined after the permission prompt.
        print(
          "[MapViewModel] Initial check: Location status .notDetermined. Waiting for prompt result."
        )
      }

      print(
        "[MapViewModel] No automatic location requests - waiting for user action (center or pin drop)."
      )
    }
  }

  @MainActor
  func forceLocationPermissionCheck() async {
    print("[MapViewModel] forceLocationPermissionCheck called.")
    // Move this off the main thread
    self.isLocationServicesEnabled = await checkLocationServicesEnabled()

    if !self.isLocationServicesEnabled {
      print("[MapViewModel] Location services disabled at device level.")
      self.isLocationAuthorized = false  // Reflect this state
      self.isLimitedFunctionalityDueToLocationDenial = true  // Set the flag
      UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")  // Set user default
      alertMessage = "Location services are disabled. Please enable them in Settings."
      showAlert = true
      return
    }

    // Get authorization status safely off the main thread
    let currentStatus = await getAuthorizationStatus()

    print("[MapViewModel] Current authorization status for force check: \(currentStatus.rawValue)")
    self.isLocationAuthorized =
      (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways)

    switch currentStatus {
    case .notDetermined:
      print("[MapViewModel] Authorization not determined, requesting WhenInUse.")
      isRequestingLocation = true  // Indicate a request is in progress
      // We don't set isLimitedFunctionalityDueToLocationDenial here, wait for delegate.
      locationManager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      print(
        "[MapViewModel] Authorization denied or restricted. Guiding user to settings may be needed."
      )
      self.isLimitedFunctionalityDueToLocationDenial = true  // Set the flag
      UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")  // Set user default
      alertMessage =
        "Location access was denied. Please enable it in Settings to use location features."
      showAlert = true
    // isLocationAuthorized is already false or will be set by delegate
    case .authorizedWhenInUse, .authorizedAlways:
      print("[MapViewModel] Already authorized.")
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
      print("[MapViewModel] Unknown authorization status: \(currentStatus.rawValue)")
    }
  }

  @MainActor
  func requestLocationPermission() {
    print("[MapViewModel] requestLocationPermission called.")

    // Move location services check off the main thread with Task
    Task {
      let servicesEnabled = await checkLocationServicesEnabled()

      await MainActor.run {
        self.isLocationServicesEnabled = servicesEnabled

        if !servicesEnabled {
          print("[MapViewModel] Location services are disabled. Cannot request permission.")
          self.isLocationAuthorized = false
          alertMessage = "Location services are disabled. Please enable them in Settings."
          showAlert = true
          return
        }

        // Continue with permission request after verifying services are enabled
        Task {
          let status = await getAuthorizationStatus()
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
      print("[MapViewModel] Status is .notDetermined. Requesting WhenInUse authorization.")
      isRequestingLocation = true
      locationManager.requestWhenInUseAuthorization()
    } else {
      print(
        "[MapViewModel] Permission already determined (Status: \(status.rawValue)). Handling via forceLocationPermissionCheck or delegate."
      )
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

    let pinId = UUID().uuidString
    let newPin = Pin(
      id: pinId,
      coordinate: pendingCoordinate,
      incidentType: incidentType,
      videoURL: "",
      userId: currentUserId
    )

    Task {
      do {
        let data: [String: Any] = [
          "id": pinId,
          "latitude": pendingCoordinate.latitude,
          "longitude": pendingCoordinate.longitude,
          "type": incidentType.firestoreType,
          "videoURL": "",
          "userId": currentUserId,
          "timestamp": Timestamp(),
          "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? "",
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
        print("[MapViewModel] Error adding pin: \(error.localizedDescription)")
        await MainActor.run {
          showAlert = true
          alertMessage = "Failed to drop pin: \(error.localizedDescription)"
          showingIncidentPicker = false
        }
      }
    }
  }

  func deletePin(_ pin: Pin) async throws {
    do {
      try await db.collection("pins").document(pin.id).delete()
      await MainActor.run {
        self.pins.removeAll { $0.id == pin.id }
      }
    } catch {
      print("[MapViewModel] Error deleting pin: \(error.localizedDescription)")
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

    loadPins()

    // Clean up any invalid pins on startup
    Task {
      await cleanupInvalidPins()
    }
  }

  deinit {
    // Remove notification observers
    NotificationCenter.default.removeObserver(
      self, name: .appDidBecomeActiveForLocationCheck, object: nil)
    NotificationCenter.default.removeObserver(
      self, name: Notification.Name("UploadProgressUpdated"), object: nil)
    print(
      "[MapViewModel] Deinitialized and unsubscribed from notifications."
    )
  }

  @objc private func updateUploadProgress(notification: Notification) {
    if let progress = notification.userInfo?["progress"] as? Double {
      Task { @MainActor in
        self.uploadProgress = progress / 100.0
      }
    }
  }

  @objc private func handleAppDidBecomeActive() {
    print("[MapViewModel] App active - NO automatic location check.")
    // Do nothing automatically - user must explicitly request location
  }

  private func loadPins() {
    print("[MapViewModel] Loading pins from Firestore")
    db.collection("pins").addSnapshotListener { [weak self] snapshot, error in
      guard let self = self else { return }

      if let error = error {
        print("[MapViewModel] Error loading pins: \(error.localizedDescription)")
        self.showError("Failed to load pins: \(error.localizedDescription)")
        return
      }

      guard let documents = snapshot?.documents else {
        print("[MapViewModel] No pins found")
        return
      }

      print("[MapViewModel] Found \(documents.count) pins")

      Task { @MainActor in
        let loadedPins = documents.compactMap { document -> Pin? in
          let data = document.data()

          guard let idString = data["id"] as? String,
            let latitudeValue = data["latitude"] as? Double,
            let longitudeValue = data["longitude"] as? Double,
            let typeString = data["type"] as? String,
            let userIdString = data["userId"] as? String
          else {
            print("[MapViewModel] Invalid pin data in document \(document.documentID)")
            print(
              "[MapViewModel] Pin data fields - id: \(data["id"] ?? "missing"), latitude: \(data["latitude"] ?? "missing"), longitude: \(data["longitude"] ?? "missing"), type: \(data["type"] ?? "missing"), userId: \(data["userId"] ?? "missing")"
            )
            return nil
          }

          let coordinate = CLLocationCoordinate2D(
            latitude: latitudeValue, longitude: longitudeValue)
          let videoURL = data["videoURL"] as? String ?? ""
          let zipCode = data["zipCode"] as? String ?? ""  // Get zip code if available

          let incidentType = IncidentType.fromFirestoreType(typeString)

          var pin = Pin(
            id: idString,
            coordinate: coordinate,
            incidentType: incidentType,
            videoURL: videoURL,
            userId: userIdString
          )

          pin.zipCode = zipCode  // Set zip code

          // If pin doesn't have a zip code, try to determine it based on current user's zip code
          if zipCode.isEmpty, let userProfile = self.authManager.currentUserProfile {
            pin.zipCode = userProfile.zipCode
          }

          return pin
        }

        self.pins = loadedPins
        print("[MapViewModel] Successfully loaded \(loadedPins.count) pins")
      }
    }
  }

  @MainActor
  private func fetchCurrentLocation() {
    if isLocationAuthorized {
      print("[MapViewModel] Fetching current location")
      locationManager.requestLocation()
    } else {
      print("[MapViewModel] Cannot fetch location: not authorized")
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
      let servicesEnabled = await checkLocationServicesEnabled()
      await MainActor.run {
        self.isLocationServicesEnabled = servicesEnabled
        print(
          "[MapViewModel] App returned to foreground, relying on delegate for authorization status")
      }
    }
  }

  /// Call from MainTabView.onAppear for one-time first launch prompt.
  @MainActor
  func ensureInitialPermissionPrompt() {
    print("[MapViewModel] Ensuring initial permission prompt")
    // Perform the check off-thread and then act on the result
    Task {
      let status = await getAuthorizationStatus()

      await MainActor.run {
        switch status {
        case .notDetermined:
          print("[MapViewModel] Requesting location permission on initial load")
          self.isRequestingLocation = true
          self.locationManager.requestWhenInUseAuthorization()
        default:
          print(
            "[MapViewModel] Permission already determined: \(status.rawValue). Forcing a refresh check"
          )
          Task { await self.forceLocationPermissionCheck() }
        }
      }
    }
  }

  func dropPinWithVideo(for incidentType: IncidentType, videoURL: URL) async throws {
    print("[MapViewModel] Starting video upload process...")

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
      print("[MapViewModel] Missing coordinate or user ID")
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

    print(
      "[MapViewModel] Uploading video for incident type: \(incidentType.title) at \(pinCoordinate.latitude), \(pinCoordinate.longitude)"
    )
    print("[MapViewModel] Generated pin ID: \(pinId)")

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
      print("[MapViewModel] Pin created and displayed on map, starting upload...")
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

          print("[MapViewModel] Starting upload task...")

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
            print("[MapViewModel] Upload task completed successfully")

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
                print("[MapViewModel] Failed to get download URL: \(error.localizedDescription)")
                localContinuation.resume(throwing: error)
                return
              }

              guard let downloadURL = url else {
                print("[MapViewModel] Download URL is nil")
                localContinuation.resume(
                  throwing: NSError(
                    domain: "StorageError", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                return
              }

              print("[MapViewModel] Got download URL: \(downloadURL.absoluteString)")

              // Show final progress step
              Task { @MainActor in
                self.uploadProgress = 0.95
              }

              // Get user's current zip code - SAFELY
              // We need to access MainActor-isolated property in a MainActor context
              Task { @MainActor in
                // Get zip code on the main actor
                let userZipCode = self.authManager.currentUserProfile?.zipCode ?? ""

                // Create pin data
                let pinData: [String: Any] = [
                  "id": pinId,
                  "latitude": pinCoordinate.latitude,
                  "longitude": pinCoordinate.longitude,
                  "type": incidentType.firestoreType,
                  "videoURL": downloadURL.absoluteString,
                  "userId": currentUserId,
                  "timestamp": FieldValue.serverTimestamp(),
                  "zipCode": userZipCode,  // Add zip code to the pin data
                ]

                // Add pin to Firestore
                let db = Firestore.firestore()

                // Store the continuation outside the Task so we can resume it properly
                let localContinuation = continuation

                // Use async/await instead of completion handler
                do {
                  try await db.collection("pins").document(pinId).setData(pinData)

                  print("[MapViewModel] Successfully saved pin to Firestore")

                  // Update the existing pin with video URL
                  if let index = self.pins.firstIndex(where: { $0.id == pinId }) {
                    self.pins[index] = Pin(
                      id: pinId,
                      coordinate: pinCoordinate,
                      incidentType: incidentType,
                      videoURL: downloadURL.absoluteString,
                      userId: currentUserId
                    )
                    print("[MapViewModel] Updated pin with video URL")
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
                      userId: currentUserId
                    ))

                  // Resume the continuation with success
                  localContinuation.resume(returning: ())
                } catch {
                  print(
                    "[MapViewModel] Failed to save pin to Firestore: \(error.localizedDescription)"
                  )
                  // Remove the pin from local array since Firestore save failed
                  self.pins.removeAll { $0.id == pinId }
                  self.activeUploads = max(0, self.activeUploads - 1)
                  self.uploadProgress = 0

                  // Resume the continuation with error
                  localContinuation.resume(throwing: error)
                }
              }
            }
          }

          failureHandle = uploadTask.observe(.failure) { snapshot in
            print("[MapViewModel] Upload task failed")

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
              print("[MapViewModel] Upload error: \(error.localizedDescription)")
              localContinuation.resume(throwing: error)
            } else {
              print("[MapViewModel] Unknown upload error")
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
    print("[MapViewModel] Starting upload process for pin with video: \(draft.videoURL != nil)")

    // Check if user is anonymous AND trying to upload a video
    if authState.isAnonymous && draft.videoURL != nil {
      print("[MapViewModel] Anonymous user attempted video upload - blocking")
      showError("Guests cannot upload videos.")
      reportStep = nil  // Dismiss the report sheet
      return
    }

    do {
      let pinId = UUID().uuidString
      print("[MapViewModel] Generated pin ID: \(pinId)")

      // Check if video file exists before attempting upload
      if let videoURL = draft.videoURL {
        if !FileManager.default.fileExists(atPath: videoURL.path) {
          print("[MapViewModel] ERROR: Video file does not exist at path: \(videoURL.path)")
          showError(
            "Selected video file is no longer available. Please try selecting another video.")
          return
        }
        print("[MapViewModel] Video file exists at: \(videoURL.path)")
      } else {
        print("[MapViewModel] No video attached - creating pin without video")
      }

      // Upload video if present
      print("[MapViewModel] Calling StorageUploader.uploadIfNeeded...")
      let remoteURL = try await StorageUploader.uploadIfNeeded(
        pinId: pinId, localURL: draft.videoURL)
      print("[MapViewModel] StorageUploader completed. Remote URL: '\(remoteURL)'")

      // Save pin to Firestore FIRST
      print("[MapViewModel] Saving pin to Firestore...")
      try await FirestorePins.addPin(
        id: pinId,
        coord: draft.coordinate,
        type: draft.incidentType,
        videoURL: remoteURL)
      print("[MapViewModel] Pin saved to Firestore successfully")

      // Let the Firestore listener handle adding the pin to the local array
      // This prevents race conditions where the listener overwrites our local update
      print("[MapViewModel] Waiting for Firestore listener to add pin to local array")

      // Send notifications
      let newPin = draft.makePin(id: pinId, remote: remoteURL)
      await sendZipCodeNotifications(for: newPin)

      reportStep = nil  // Close sheet
      print("[MapViewModel] Upload process completed successfully")

    } catch {
      print("[MapViewModel] Upload failed with error: \(error)")
      if let nsError = error as NSError? {
        print("[MapViewModel] Error domain: \(nsError.domain), code: \(nsError.code)")
        print("[MapViewModel] Error userInfo: \(nsError.userInfo)")
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

    print("[MapViewModel] Centering on user location with 500ft radius: \(validCoordinate)")

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
    switch mapType {
    case .standard:
      mapType = .hybrid
    case .hybrid:
      mapType = .satellite
    case .satellite:
      mapType = .mutedStandard
    case .mutedStandard:
      mapType = .standard
    default:
      mapType = .standard
    }
  }

  // Helper to get icon name for current map type
  func mapTypeIcon() -> String {
    switch mapType {
    case .standard:
      return "map"
    case .hybrid:
      return "globe.americas.fill"
    case .satellite:
      return "camera.aperture"
    case .mutedStandard:
      return "map.fill"
    default:
      return "map"
    }
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
  @MainActor
  func handleLocationAction(_ action: LocationAction) {
    Task {
      let servicesEnabled = await checkLocationServicesEnabled()
      let status = await getAuthorizationStatus()
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
    print("[MapViewModel] Starting cleanup of invalid pins...")
    let snapshot = try? await db.collection("pins").getDocuments()

    guard let documents = snapshot?.documents else {
      print("[MapViewModel] No documents found for cleanup")
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
        print("[MapViewModel] Removing invalid pin document: \(document.documentID)")
        try? await document.reference.delete()
        removedCount += 1
      }
    }

    print("[MapViewModel] Cleanup completed. Removed \(removedCount) invalid pins")
    if removedCount > 0 {
      // Refresh pins after cleanup
      loadPins()
    }
  }

  // MARK: - Notification Handling
  private func sendZipCodeNotifications(for pin: Pin) async {
    guard let currentUserProfile = authManager.currentUserProfile else {
      print("[MapViewModel] Cannot send notifications - no current user profile")
      return
    }

    let zipCode = currentUserProfile.zipCode
    print("[MapViewModel] Sending notifications to users in zip code: \(zipCode)")

    // Send notifications to other users in the same zip code
    await notificationManager.notifyUsersInZipCode(for: pin, zipCode: zipCode)
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
    reportStep = .type
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
          print("[MapViewModel] Successfully updated pin \(pinId) with video URL: \(newURL)")
        } catch {
          print(
            "[MapViewModel] Error updating pin video URL in Firestore: \(error.localizedDescription)"
          )
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
      let servicesEnabled = await self.checkLocationServicesEnabled()

      await MainActor.run {
        print("[MapViewModel] Delegate: Authorization status changed to: \(status.rawValue)")
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
          print("[MapViewModel] Delegate: Authorized.")
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
          print("[MapViewModel] Delegate: Denied or restricted.")
          self.alertMessage =
            "Location access is required for core features. Please enable it in Settings."
          self.showAlert = true
          // Ensure userLocation is nil if access is denied to prevent using stale data
          self.userLocation = nil
          self.isLimitedFunctionalityDueToLocationDenial = true  // Set the flag
          UserDefaults.standard.set(true, forKey: "userDeclinedLocationPermissions")  // Set user default
        case .notDetermined:
          print(
            "[MapViewModel] Delegate: Status became .notDetermined. This shouldn't usually happen after an initial request."
          )
        @unknown default:
          print("[MapViewModel] Delegate: Unknown authorization status: \(status.rawValue)")
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
      print("[MapViewModel] Delegate: Location updated: \(location.coordinate)")

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
        print(
          "[MapViewModel] First location fix or map is at a default. Centering on user: \(location.coordinate)"
        )
        // Use a span consistent with other user-centric views, e.g., from centerOnUserLocation or a sensible default.
        // For this example, using a span similar to the initial MapView span.
        let defaultUserSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)  // A reasonable zoom level for user location
        let newRegion = MKCoordinateRegion(
          center: location.coordinate,
          span: defaultUserSpan
        )
        self.region = newRegion  // Update the ViewModel's main region state
        self.mapRegion = newRegion  // Signal the MapView to update
        print(
          "[MapViewModel] Set initial map region to user location: \(newRegion.center), span: \(newRegion.span.latitudeDelta)"
        )
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
        print("[MapViewModel] Posted LocationUpdated notification")
      }
    }
  }

  nonisolated
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
  {
    print("[MapViewModel] Delegate: Failed to get location: \(error.localizedDescription)")
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

enum ReportStep: Int, Identifiable, CaseIterable {
  case type, video, confirm
  var id: Int { rawValue }
}
