import Foundation
import CoreLocation
import SwiftUI

/// Handles all location-related operations including permissions, updates, and location services
@MainActor
class LocationViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var userLocation: CLLocation?
    @Published var isLocationAuthorized = false
    @Published var isLocationServicesEnabled = false
    @Published var isRequestingLocation = false
    @Published var isLimitedFunctionalityDueToLocationDenial = false
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var locationUpdateTimer: Timer?
    private var shouldCenterAfterAuthorization = false
    private var hasPromptedForInitialPermission = false
    private var pendingLocationRequests: [CheckedContinuation<CLLocation?, Never>] = []
    
    // MARK: - Constants
    private let locationUpdateInterval: TimeInterval = 5.0 // Throttle location updates
    private let locationTimeout: TimeInterval = 10.0
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
        setupNotifications()
        
        // Perform initial location status check
        Task {
            await checkInitialLocationStatus()
        }
    }
    
    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Only update when moved 10 meters
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Location Services
    
    /// Requests location permission from the user
    func requestLocationPermission() {
        Task {
            let servicesEnabled = await checkLocationServicesEnabled()
            
            self.isLocationServicesEnabled = servicesEnabled
            
            if !servicesEnabled {
                print("[LocationViewModel] Location services are disabled. Cannot request permission.")
                self.isLocationAuthorized = false
                self.isLimitedFunctionalityDueToLocationDenial = true
                return
            }
            
            let status = await getAuthorizationStatus()
            await handleAuthorizationStatus(status)
        }
    }
    
    /// Gets current location with timeout
    func getCurrentLocation() async -> CLLocation? {
        if let location = userLocation {
            return location
        }
        
        if !isLocationAuthorized || !isLocationServicesEnabled {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            // Add to pending requests
            pendingLocationRequests.append(continuation)
            
            // Start location update
            locationManager.requestLocation()
            
            // Set timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + locationTimeout) {
                self.completePendingRequests(with: nil)
            }
        }
    }
    
    /// Starts continuous location updates (throttled)
    func startLocationUpdates() {
        guard isLocationAuthorized else { return }
        
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: locationUpdateInterval, repeats: true) { _ in
            self.locationManager.requestLocation()
        }
        
        print("[LocationViewModel] Started throttled location updates")
    }
    
    /// Stops continuous location updates
    func stopLocationUpdates() {
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        locationManager.stopUpdatingLocation()
        print("[LocationViewModel] Stopped location updates")
    }
    
    /// Checks if location is available within timeout
    func checkLocationAvailability() async -> Bool {
        guard isLocationAuthorized else { return false }
        guard await checkLocationServicesEnabled() else { return false }
        
        if userLocation != nil { return true }
        
        let location = await getCurrentLocation()
        return location != nil
    }
    
    // MARK: - Location Status Checks
    
    /// Gets the current authorization status safely off the main thread
    private func getAuthorizationStatus() async -> CLAuthorizationStatus {
        return await Task.detached(priority: .userInitiated) { () -> CLAuthorizationStatus in
            return CLLocationManager().authorizationStatus
        }.value
    }
    
    /// Checks if location services are enabled safely off the main thread
    private func checkLocationServicesEnabled() async -> Bool {
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            return CLLocationManager.locationServicesEnabled()
        }.value
    }
    
    private func checkInitialLocationStatus() async {
        let servicesEnabled = await checkLocationServicesEnabled()
        let status = await getAuthorizationStatus()
        
        self.isLocationServicesEnabled = servicesEnabled
        self.isLocationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        
        if !servicesEnabled || (!isLocationAuthorized && (status == .denied || status == .restricted)) {
            self.isLimitedFunctionalityDueToLocationDenial = true
            print("[LocationViewModel] Location services/auth not sufficient. Limited functionality mode ON.")
        } else if isLocationAuthorized {
            self.isLimitedFunctionalityDueToLocationDenial = false
            print("[LocationViewModel] Location authorized. Limited functionality mode OFF.")
        }
        
        print("[LocationViewModel] Initial status - Services: \(servicesEnabled), Auth: \(isLocationAuthorized)")
    }
    
    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) async {
        if status == .notDetermined {
            print("[LocationViewModel] Status is .notDetermined. Requesting WhenInUse authorization.")
            isRequestingLocation = true
            locationManager.requestWhenInUseAuthorization()
        } else {
            print("[LocationViewModel] Permission already determined (Status: \(status.rawValue))")
            await forceLocationPermissionCheck()
        }
    }
    
    @MainActor
    private func forceLocationPermissionCheck() async {
        print("[LocationViewModel] Force location permission check")
        
        self.isLocationServicesEnabled = await checkLocationServicesEnabled()
        
        if !self.isLocationServicesEnabled {
            print("[LocationViewModel] Location services disabled at device level.")
            self.isLocationAuthorized = false
            self.isLimitedFunctionalityDueToLocationDenial = true
            return
        }
        
        let currentStatus = await getAuthorizationStatus()
        print("[LocationViewModel] Current authorization status: \(currentStatus.rawValue)")
        
        self.isLocationAuthorized = (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways)
        
        switch currentStatus {
        case .notDetermined:
            print("[LocationViewModel] Authorization not determined, requesting WhenInUse.")
            isRequestingLocation = true
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("[LocationViewModel] Authorization denied or restricted.")
            self.isLimitedFunctionalityDueToLocationDenial = true
        case .authorizedWhenInUse, .authorizedAlways:
            print("[LocationViewModel] Already authorized.")
            self.isLimitedFunctionalityDueToLocationDenial = false
            if shouldCenterAfterAuthorization {
                shouldCenterAfterAuthorization = false
                // Notify that location is ready for centering
                NotificationCenter.default.post(name: .locationReadyForCentering, object: nil)
            }
        @unknown default:
            print("[LocationViewModel] Unknown authorization status: \(currentStatus.rawValue)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Completes all pending location requests
    private func completePendingRequests(with location: CLLocation?) {
        let requests = pendingLocationRequests
        pendingLocationRequests.removeAll()
        
        for continuation in requests {
            continuation.resume(returning: location)
        }
    }
    
    /// Calculates distance between two coordinates
    func distance(from coordinate1: CLLocationCoordinate2D, to coordinate2: CLLocationCoordinate2D) -> CLLocationDistance {
        let location1 = CLLocation(latitude: coordinate1.latitude, longitude: coordinate1.longitude)
        let location2 = CLLocation(latitude: coordinate2.latitude, longitude: coordinate2.longitude)
        return location1.distance(from: location2)
    }
    
    /// Checks if a coordinate is within a certain distance of user location
    func isWithinRange(coordinate: CLLocationCoordinate2D, maxDistance: CLLocationDistance) async -> Bool {
        guard let userLocation = await getCurrentLocation() else { return false }
        
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distance = userLocation.distance(from: targetLocation)
        
        return distance <= maxDistance
    }
    
    // MARK: - Notifications
    
    @objc private func handleAppDidBecomeActive() {
        print("[LocationViewModel] App became active - checking location permissions")
        Task {
            await forceLocationPermissionCheck()
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        locationUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        completePendingRequests(with: nil)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationViewModel: CLLocationManagerDelegate {
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        Task {
            let servicesEnabled = await checkLocationServicesEnabled()
            
            await MainActor.run {
                print("[LocationViewModel] Authorization status changed to: \(status.rawValue)")
                self.isLocationServicesEnabled = servicesEnabled
                self.isLocationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
                self.isRequestingLocation = false
                
                if !servicesEnabled {
                    print("[LocationViewModel] Location services disabled")
                    return
                }
                
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    print("[LocationViewModel] Location authorized")
                    self.isLimitedFunctionalityDueToLocationDenial = false
                    
                    if self.shouldCenterAfterAuthorization {
                        self.shouldCenterAfterAuthorization = false
                        NotificationCenter.default.post(name: .locationReadyForCentering, object: nil)
                    }
                    
                case .denied, .restricted:
                    print("[LocationViewModel] Location denied or restricted")
                    self.userLocation = nil
                    self.isLimitedFunctionalityDueToLocationDenial = true
                    
                case .notDetermined:
                    print("[LocationViewModel] Location status became not determined")
                    
                @unknown default:
                    print("[LocationViewModel] Unknown authorization status: \(status.rawValue)")
                }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            let previousLocation = self.userLocation
            self.userLocation = location
            
            print("[LocationViewModel] Location updated: \(location.coordinate)")
            
            // Complete pending requests
            self.completePendingRequests(with: location)
            
            // Post notification for location update
            let shouldNotify = previousLocation == nil || 
                             (previousLocation != nil && previousLocation!.distance(from: location) > 1.0)
            
            if shouldNotify {
                NotificationCenter.default.post(name: .locationUpdated, object: location)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationViewModel] Location update failed: \(error.localizedDescription)")
        
        Task { @MainActor in
            self.isRequestingLocation = false
            self.completePendingRequests(with: nil)
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let locationUpdated = Notification.Name("LocationUpdated")
    static let locationReadyForCentering = Notification.Name("LocationReadyForCentering")
}

// MARK: - Location Constants

extension LocationViewModel {
    
    /// Pin drop distance limit (200 feet in meters)
    static let pinDropLimit: CLLocationDistance = 200 * 0.3048
    
    /// Location accuracy threshold for filtering updates
    static let accuracyThreshold: CLLocationAccuracy = 100
}