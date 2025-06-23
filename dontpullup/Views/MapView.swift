import SwiftUI
import MapKit
import AVKit
import FirebaseAuth
import AVFoundation
import FirebaseFirestore

// Update the constants to be more specific and avoid naming conflicts
private enum MapViewConstants {
    static let pinDropLimit: CLLocationDistance = 200 * 0.3048 // 200 feet in meters
    static let defaultSpan = MKCoordinateSpan(
        latitudeDelta: pinDropLimit / 111000 * 2.5, // Convert meters to degrees with some padding
        longitudeDelta: pinDropLimit / 111000 * 2.5
    )
    static let minZoomDistance: CLLocationDistance = 50 // Reduced from 100 to allow closer zoom
    static let maxZoomDistance: CLLocationDistance = 80000 // Increased from 50000 to allow farther zoom out
    static let defaultAltitude: CLLocationDistance = 1000
    
    // Add minimum span to prevent over-zooming
    static let minSpan = MKCoordinateSpan(
        latitudeDelta: defaultSpan.latitudeDelta * 0.5, // Reduced from 0.8 to allow closer zoom
        longitudeDelta: defaultSpan.longitudeDelta * 0.5
    )
}

class PinAnnotation: MKPointAnnotation {
    let pin: Pin
    
    init(pin: Pin) {
        self.pin = pin
        super.init()
        self.coordinate = pin.coordinate
        // Remove title since we're using glyphText
    }
}

struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel
    @Binding var region: MKCoordinateRegion
    @Binding var showingReportVideo: Bool
    @Binding var currentVideoPlayer: AVPlayerViewController?
    
    func makeUIView(context: Context) -> MKMapView {
        // Disable debug overlays using safer method
        disableDebugOverlays()
        
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        // Configure map appearance
        configureMapView(mapView)
        
        // Explicitly enable interaction capabilities
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        
        // Disable clustering
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        
        // Set strict zoom level constraints
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: MapViewConstants.minZoomDistance,
            maxCenterCoordinateDistance: MapViewConstants.maxZoomDistance
        )
        
        // Set initial region with default coordinates
        let defaultCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let defaultRegion = MKCoordinateRegion(
            center: defaultCoordinate,
            span: MapViewConstants.defaultSpan
        )
        mapView.setRegion(defaultRegion, animated: false)
        
        // Try to update with user location after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds delay
            
            if let location = await viewModel.getCurrentLocation() {
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MapViewConstants.defaultSpan
                )
                mapView.setRegion(region, animated: false)
            }
        }
        
        // Add gesture recognizer
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)
        
        return mapView
    }
    
    private func configureMapView(_ mapView: MKMapView) {
        // Configure base appearance with standard settings that don't require external style files
        mapView.mapType = .standard 
        mapView.showsUserLocation = true
        mapView.showsBuildings = true
        mapView.showsTraffic = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = true
        
        // Set clear tint color for better visibility
        mapView.tintColor = UIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        
        // Set default camera position
        let camera = MKMapCamera()
        camera.pitch = 0
        camera.altitude = MapViewConstants.defaultAltitude
        mapView.camera = camera
        
        // Set default region (NYC as fallback if no location)
        let defaultCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let defaultRegion = MKCoordinateRegion(
            center: defaultCoordinate,
            span: MapViewConstants.defaultSpan
        )
        mapView.setRegion(defaultRegion, animated: false)
        
        print("DEBUG: MapView configured with mapType: \(mapView.mapType.rawValue)")
    }
    
    // Safe method to disable debug overlays via UserDefaults only
    private func disableDebugOverlays() {
        let defaults = UserDefaults.standard
        
        // Metal, SceneKit and MapKit debug keys
        let keysToDisable = [
            // Metal debug keys
            "MTShowDebugVisualizer",
            "MetalDebugShowMeshStats",
            "MTShowMeshStatOverlay", 
            "MTShowUIDebuggingInfo",
            
            // SceneKit debug keys
            "SCNShowMeshStatistics",
            "SCNDebugVisualizeMeshes",
            "SCNDisplayStatistics",
            "SCNDisableDebugWireframe",
            
            // MapKit debug keys
            "MKShowsDebugTiles",
            "MKShowsMeshData",
            "MKDebugMapView"
        ]
        
        // Disable all debug keys
        for key in keysToDisable {
            defaults.set(false, forKey: key)
        }
        
        // Force update defaults
        defaults.synchronize()
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove debug logging
        if !context.coordinator.hasLoggedMapStatus {
            context.coordinator.hasLoggedMapStatus = true
        }
        
        // Update map type with animation if needed
        if mapView.mapType != viewModel.mapType {
            UIView.animate(withDuration: 0.3) {
                mapView.mapType = viewModel.mapType
                mapView.overrideUserInterfaceStyle = .dark
            }
        }
        
        // Ensure user location is always shown
        if !mapView.showsUserLocation {
            mapView.showsUserLocation = true
        }
        
        // Batch annotation updates
        let currentAnnotations = mapView.annotations.compactMap { $0 as? PinAnnotation }
        let newPins = viewModel.filteredPins
        
        // Calculate differences
        let annotationsToRemove = currentAnnotations.filter { annotation in
            !newPins.contains { $0.id == annotation.pin.id }
        }
        
        let existingPinIds = Set(currentAnnotations.map { $0.pin.id })
        let newAnnotations = newPins
            .filter { !existingPinIds.contains($0.id) }
            .map { PinAnnotation(pin: $0) }
        
        // Apply updates in a batch
        if !annotationsToRemove.isEmpty || !newAnnotations.isEmpty {
            mapView.removeAnnotations(annotationsToRemove)
            mapView.addAnnotations(newAnnotations)
        }
        
        // Update region if needed and enforce minimum zoom
        if let newRegion = viewModel.mapRegion {
            let enforcedSpan = MKCoordinateSpan(
                latitudeDelta: max(newRegion.span.latitudeDelta, MapViewConstants.minSpan.latitudeDelta),
                longitudeDelta: max(newRegion.span.longitudeDelta, MapViewConstants.minSpan.longitudeDelta)
            )
            
            let region = MKCoordinateRegion(
                center: newRegion.center,
                span: enforcedSpan
            )
            
            // Only update region if it's significantly different
            let currentCenter = mapView.region.center
            let newCenter = region.center
            let distance = MKMapPoint(currentCenter).distance(to: MKMapPoint(newCenter))
            
            if distance > 100 || // If centers are more than 100 points apart
               abs(mapView.region.span.latitudeDelta - region.span.latitudeDelta) > 0.01 {
                mapView.setRegion(region, animated: true)
            }
            
            // Reset region after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak viewModel] in
                viewModel?.mapRegion = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Add overlay to display upload progress
    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        // Clean up when view is removed
    }
}

// Add this extension to the MapView to include the upload progress overlay
extension MapView {
    func overlayView() -> some View {
        // This creates a transparent view that overlays the map
        // and shows the upload progress indicator when needed
        ZStack {
            Color.clear // Transparent background
            
            // Show upload progress indicator when uploading
            if viewModel.uploadProgress > 0 && viewModel.uploadProgress < 1.0 {
                UploadProgressOverlay(viewModel: viewModel)
            }

            // Banner for location denial
            if viewModel.isLimitedFunctionalityDueToLocationDenial {
                VStack {
                    Spacer() // Pushes content to the bottom
                    HStack {
                        Image(systemName: "location.slash.fill")
                            .foregroundColor(.white)
                        Text("Location disabled. Tap to enable for full features.")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .padding(.horizontal) 
                    .padding(.bottom, 10) 
                    .onTapGesture {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .edgesIgnoringSafeArea(.bottom) // Allow background to extend towards edge
            }
        }
    }
}

class Coordinator: NSObject, MKMapViewDelegate {
    var parent: MapView
    var hasLoggedMapStatus = false
    
    init(_ parent: MapView) {
        self.parent = parent
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Respond to long-press only when NOT in delete-edit mode
        guard gesture.state == .began, parent.viewModel.isEditMode == false else { return }

        // Check if user is anonymous first
        if parent.viewModel.authState.isAnonymous {
            parent.viewModel.showError("Guests cannot drop new pins.")
            return
        }
        
        let point = gesture.location(in: gesture.view)
        let coordinate = (gesture.view as? MKMapView)?.convert(point, toCoordinateFrom: gesture.view)
        
        guard let validCoordinate = coordinate else { return }
        
        // Check authentication first
        guard Auth.auth().currentUser != nil else {
            parent.viewModel.showError("You need to sign in to drop pins")
            return
        }
        
        // Use the unified location handler for pin drop
        parent.viewModel.handleLocationAction(.pinDrop(validCoordinate))
    }
    
    // Implement MKMapViewDelegate methods to prevent unwanted zoom changes
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        let currentSpan = mapView.region.span
        
        // Prevent zooming in too far
        if currentSpan.latitudeDelta < MapViewConstants.minSpan.latitudeDelta ||
           currentSpan.longitudeDelta < MapViewConstants.minSpan.longitudeDelta {
            mapView.setRegion(MKCoordinateRegion(
                center: mapView.region.center,
                span: MapViewConstants.minSpan
            ), animated: false)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tileOverlay = overlay as? MKTileOverlay {
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = 0.8 // Adjust for desired neon effect intensity
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            let identifier = "UserLocation"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if view == nil {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.image = UIImage(systemName: "location.fill")?.withTintColor(.red, renderingMode: .alwaysTemplate)
                view?.canShowCallout = false
            } else {
                view?.annotation = annotation
            }
            
            // Configure appearance
            view?.tintColor = UIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
            
            return view
        }
        
        if let pinAnnotation = annotation as? PinAnnotation else {
            let identifier = "PinAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
                annotationView?.clusteringIdentifier = nil
            } else {
                annotationView?.annotation = annotation
            }
            
            // Configure pin appearance with neon styling
            annotationView?.glyphText = pinAnnotation.pin.incidentType.emoji
            
            // Set pin color based on incident type with neon effect
            let pinColor: UIColor
            switch pinAnnotation.pin.incidentType {
            case .verbal:
                pinColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // Neon yellow
            case .physical:
                pinColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Neon red
            case .emergency:
                pinColor = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0) // Neon green
            }
            
            annotationView?.markerTintColor = parent.viewModel.isEditMode ? .red : pinColor
            annotationView?.glyphTintColor = .white
            annotationView?.displayPriority = .required
            
            // Retain edit mode animation but remove shadow adjustments
            UIView.animate(withDuration: 0.3) {
                annotationView?.transform = self.parent.viewModel.isEditMode ?
                    CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
                if self.parent.viewModel.isEditMode {
                    // Shadow adjustments omitted in edit mode
                }
            }

            return annotationView
        }
        
        return nil
    }
    
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        views.forEach { view in
            view.alpha = 0
            
            UIView.animate(withDuration: 0.3) {
                view.alpha = 1
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        mapView.deselectAnnotation(annotation, animated: true)
        
        guard let pinAnnotation = annotation as? PinAnnotation else { return }
        let pin = pinAnnotation.pin

        if parent.viewModel.isEditMode {
            // Delete pin only if user owns it
            Task { @MainActor in
                if parent.viewModel.userCanEditPin(pin) {
                    do {
                        try await parent.viewModel.deletePin(pin)
                        // Add deletion animation
                        UIView.animate(withDuration: 0.3, animations: {
                            view.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
                            view.alpha = 0
                        }) { _ in
                            mapView.removeAnnotation(annotation)
                        }
                    } catch {
                        parent.viewModel.showError(error.localizedDescription)
                    }
                } else {
                    parent.viewModel.showError("You can only delete your own pins")
                }
            }
            return
        }
        
        // Set current video ID for flagging reference
        parent.viewModel.currentlyPlayingVideoId = pin.id
        
        // Use the new refresh mechanism to handle video playback
        Task { @MainActor in
            do {
                // First check if we need to refresh the pin data
                if pin.videoURL.isEmpty {
                    print("[MapView] Pin has empty videoURL, attempting to refresh from Firestore")
                    if let refreshedPin = try await refreshPinFromFirestore(pinId: pin.id), 
                       !refreshedPin.videoURL.isEmpty {
                        // Update pin in viewModel to have the correct URL for future references
                        parent.viewModel.updatePinVideoURL(pin.id, newURL: refreshedPin.videoURL)
                        
                        // Play the video with the refreshed URL
                        print("[MapView] Successfully refreshed pin with video URL: \(refreshedPin.videoURL)")
                        await dismissExistingPlayer(animated: true)
                        if let url = URL(string: refreshedPin.videoURL) {
                            await playVideo(from: url)
                        } else {
                            throw NSError(domain: "VideoPlayback", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URL format after refresh."])
                        }
                    } else {
                        // Check if this pin is currently uploading
                        if parent.viewModel.uploadProgress > 0 && parent.viewModel.uploadProgress < 1.0 {
                            throw NSError(domain: "VideoPlayback", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video is still uploading. Please wait for upload to complete."])
                        } else {
                            throw NSError(domain: "VideoPlayback", code: -1, userInfo: [NSLocalizedDescriptionKey: "This pin has no video attached."])
                        }
                    }
                } else {
                    // We already have a video URL, proceed with normal playback
                    print("[MapView] Pin already has videoURL: \(pin.videoURL)")
                    await dismissExistingPlayer(animated: true)
                    if let url = URL(string: pin.videoURL) {
                        await playVideo(from: url)
                    } else {
                        throw NSError(domain: "VideoPlayback", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URL format."])
                    }
                }
            } catch {
                print("Error during video playback: \(error)")
                parent.viewModel.showError("Failed to play video: \(error.localizedDescription)")
            }
        }
    }
    
    // Helper to dismiss existing player, ensuring completion
    private func dismissExistingPlayer(animated: Bool) async {
         guard let rootViewController = getRootViewController(),
               rootViewController.presentedViewController is AVPlayerViewController else { return }
           
         await dismissViewController(rootViewController.presentedViewController, animated: animated)
    }
    
    // Generic helper to dismiss a view controller and wait for completion
    private func dismissViewController(_ viewController: UIViewController?, animated: Bool) async {
        guard let vc = viewController else { return }
        
        // Use continuation to bridge completion handler
        await withCheckedContinuation { continuation in
            vc.dismiss(animated: animated) {
                continuation.resume()
            }
        }
        print("Dismiss completion handler executed for \(type(of: vc))") // Debug log
    }

    // Helper to get root view controller
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return nil }
        return window.rootViewController
    }

    // Helper to create temp file only when needed for AVPlayer
    private func createTemporaryFile(from data: Data) throws -> URL {
         let tempDir = FileManager.default.temporaryDirectory
         let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
         try data.write(to: tempFile, options: .atomic)
         print("Created temporary video file for player: \(tempFile.path)")
         return tempFile
    }
    
    // playVideo function refined
    private func playVideo(from url: URL) async {
        do {
            // Assume caller handled dismissing previous VCs
            
            // 1. Create Asset from temp URL
            let asset = AVURLAsset(url: url)

            // 2. Load essential properties asynchronously *before* creating PlayerItem
            // Remove unused key definitions
            // let loadableKeys: [AVAsyncProperty<AVURLAsset, CMTime>] = [.duration]
            // let tracksKey: AVAsyncProperty<AVURLAsset, [AVAssetTrack]> = .tracks
            
            // Check duration first (optional, but can filter invalid assets early)
             let duration = try await asset.load(.duration)
             guard duration.seconds > 0 else {
                 throw NSError(domain: "VideoPlayback", code: -10, userInfo: [NSLocalizedDescriptionKey: "Video asset has invalid duration."])
             }

            // Load tracks (important for player setup)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                 throw NSError(domain: "VideoPlayback", code: -11, userInfo: [NSLocalizedDescriptionKey: "Video asset has no video tracks."])
            }
            
            // Optional: Re-check isPlayable if needed, though loading tracks often suffices
            // let isPlayable = try await asset.load(.isPlayable)
            // guard isPlayable else { throw ... }

            // 3. Create PlayerItem *after* loading asset properties
            let playerItem = AVPlayerItem(asset: asset) 

            // 4. Setup Player and ViewController
            let player = AVPlayer(playerItem: playerItem)
            let playerViewController = AVPlayerViewController()
            playerViewController.player = player
            player.actionAtItemEnd = .pause
            
            // Add flag button to player UI
            let flagButton = UIButton(type: .system)
            flagButton.setImage(UIImage(systemName: "flag.fill"), for: .normal)
            flagButton.tintColor = UIColor.white
            flagButton.backgroundColor = UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.7)
            flagButton.layer.cornerRadius = 15
            flagButton.tag = 100 // Tag to find button later
            
            // Configure button size and position
            flagButton.frame = CGRect(x: 20, y: 60, width: 30, height: 30)
            flagButton.addTarget(self, action: #selector(flagButtonTapped), for: .touchUpInside)
            
            // Add button to player view
            playerViewController.contentOverlayView?.addSubview(flagButton)
            
            guard let rootVC = getRootViewController() else {
                print("Error: Cannot present player, root VC not found.")
                try? FileManager.default.removeItem(at: url) // Clean up temp file
                return
            }
             
            // 5. Present player and wait for completion
            try await presentViewController(playerViewController, on: rootVC, animated: true)
            player.play() // Play after presentation completes

            // 6. Setup temporary file cleanup observer (remains the same)
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, 
                                               object: playerItem,
                                               queue: .main) { _ in 
                print("Player item finished playing. Cleaning up temp file: \(url.path)")
                try? FileManager.default.removeItem(at: url)
            }
            
        } catch { // Catch errors from asset loading or presentation
            parent.viewModel.showError("Failed to play video: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url) // Clean up temp file on error
        }
    }
    
    // Generic helper to present a view controller and wait for completion
    private func presentViewController(_ viewControllerToPresent: UIViewController, on presentingViewController: UIViewController, animated: Bool) async throws {
        // Use continuation to bridge completion handler and handle potential errors
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            presentingViewController.present(viewControllerToPresent, animated: animated) {
                // Check if the presentation actually succeeded if possible (though usually completion implies success)
                // If presentation could fail silently, more checks might be needed here.
                continuation.resume()
            }
        }
        print("Presentation completion handler executed for \(type(of: viewControllerToPresent))") // Debug log
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Silently update the map region without debug logs
        if let currentRegion = self.parent.viewModel.mapRegion,
           (currentRegion.center.latitude != mapView.region.center.latitude ||
            currentRegion.center.longitude != mapView.region.center.longitude ||
            currentRegion.span.latitudeDelta != mapView.region.span.latitudeDelta ||
            currentRegion.span.longitudeDelta != mapView.region.span.longitudeDelta) {
            DispatchQueue.main.async {
                self.parent.viewModel.mapRegion = mapView.region
            }
        }
    }
    
    @objc private func flagButtonTapped() {
        guard let rootVC = getRootViewController(),
              let playerVC = rootVC.presentedViewController as? AVPlayerViewController else {
            return
        }
        
        // Pause video
        playerVC.player?.pause()
        
        // Store the player reference and show SwiftUI report view
        parent.currentVideoPlayer = playerVC
        parent.showingReportVideo = true
    }
}

// Wrapper view to handle the report video sheet
struct MapViewWithReportSheet: View {
    @ObservedObject var viewModel: MapViewModel
    @Binding var region: MKCoordinateRegion
    @State private var showingReportVideo = false
    @State private var currentVideoPlayer: AVPlayerViewController?
    
    var body: some View {
        MapView(
            viewModel: viewModel,
            region: $region,
            showingReportVideo: $showingReportVideo,
            currentVideoPlayer: $currentVideoPlayer
        )
        .sheet(isPresented: $showingReportVideo) {
            ReportVideoView(
                isPresented: $showingReportVideo,
                onSubmit: { email, reason in
                    submitFlagReport(email: email, reason: reason)
                },
                onCancel: {
                    cancelReport()
                }
            )
        }
    }
    
    private func submitFlagReport(email: String, reason: String) {
        Task {
            do {
                let videoId = viewModel.currentlyPlayingVideoId ?? "unknown"
                try await viewModel.reportVideo(email: email, reason: reason, videoId: videoId)
                print("Flag report submitted successfully")
                
                // Show success message and dismiss player
                await MainActor.run {
                    if let playerVC = currentVideoPlayer {
                        playerVC.dismiss(animated: true) {
                            // Show confirmation alert after player is dismissed
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = scene.windows.first?.rootViewController {
                                let confirmAlert = UIAlertController(
                                    title: "Report Submitted",
                                    message: "Thank you. We'll review this video and contact you at \(email).",
                                    preferredStyle: .alert
                                )
                                confirmAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                rootVC.present(confirmAlert, animated: true)
                            }
                        }
                    }
                    currentVideoPlayer = nil
                }
            } catch {
                print("Error submitting flag report: \(error.localizedDescription)")
                await MainActor.run {
                    viewModel.showError("Failed to submit report: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func cancelReport() {
        // Resume video playback
        currentVideoPlayer?.player?.play()
    }
}

// Helper extension for array safe subscript
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Function to play video for a pin
func playVideo(for pin: Pin) {
    guard !pin.videoURL.isEmpty else {
        // First try to refresh the pin from Firestore to get the latest data
        Task {
            do {
                print("[MapView] Attempting to refresh pin data from Firestore for \(pin.id)")
                let refreshedPin = try await refreshPinFromFirestore(pinId: pin.id)
                
                if let refreshedPin = refreshedPin, !refreshedPin.videoURL.isEmpty {
                    print("[MapView] Successfully refreshed pin with video URL: \(refreshedPin.videoURL)")
                    await MainActor.run {
                        // Play the video with the refreshed URL
                        playVideoWithURL(refreshedPin.videoURL, for: refreshedPin)
                    }
                } else {
                    // Still no video URL after refresh
                    let error = NSError(domain: "VideoPlayback", code: -1, userInfo: [NSLocalizedDescriptionKey: "This pin has no video attached."])
                    print("Error during video playback: \(error)")
                    
                    // Show error alert
                    let alert = UIAlertController(title: "Video Unavailable", message: "This pin has no video attached.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        var topVC = rootVC
                        while let presentedVC = topVC.presentedViewController {
                            topVC = presentedVC
                        }
                        topVC.present(alert, animated: true)
                    }
                }
            } catch {
                print("[MapView] Error refreshing pin data: \(error.localizedDescription)")
                let errorAlert = UIAlertController(title: "Error", message: "Failed to load video: \(error.localizedDescription)", preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    var topVC = rootVC
                    while let presentedVC = topVC.presentedViewController {
                        topVC = presentedVC
                    }
                    topVC.present(errorAlert, animated: true)
                }
            }
        }
        return
    }
    
    // If we already have a video URL, play it directly
    playVideoWithURL(pin.videoURL, for: pin)
}

// Helper function to refresh a pin from Firestore
func refreshPinFromFirestore(pinId: String) async throws -> Pin? {
    print("[MapView] Refreshing pin data for ID: \(pinId)")
    let db = Firestore.firestore()
    let docRef = db.collection("pins").document(pinId)
    
    let snapshot = try await docRef.getDocument()
    guard let data = snapshot.data() else {
        print("[MapView] No data found for pin ID: \(pinId)")
        return nil
    }
    
    // Extract pin data
    guard let id = data["id"] as? String,
          let latitude = data["latitude"] as? Double,
          let longitude = data["longitude"] as? Double,
          let typeString = data["type"] as? String,
          let userId = data["userId"] as? String else {
        print("[MapView] Invalid pin data format")
        return nil
    }
    
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let incidentType = IncidentType.from(firestoreType: typeString)
    let videoURL = data["videoURL"] as? String ?? ""
    
    print("[MapView] Refreshed pin data - videoURL: '\(videoURL)'")
    
    return Pin(id: id, coordinate: coordinate, incidentType: incidentType, videoURL: videoURL, userId: userId)
}

// Helper function to play video with URL
func playVideoWithURL(_ videoURL: String, for pin: Pin) {
    print("[MapView] Attempting to play video for pin \(pin.id), videoURL: '\(videoURL)', isEmpty: \(videoURL.isEmpty)")
    
    guard !videoURL.isEmpty else {
        let error = NSError(domain: "VideoPlayback", code: -1, userInfo: [NSLocalizedDescriptionKey: "This pin has no video attached."])
        print("Error during video playback: \(error)")
        
        // Show error alert
        let alert = UIAlertController(title: "Video Unavailable", message: "This pin has no video attached.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presentedVC = topVC.presentedViewController {
                topVC = presentedVC
            }
            topVC.present(alert, animated: true)
        }
        return
    }
    
    // Play video from URL
    if let url = URL(string: videoURL) {
        print("Playing directly from URL...")
        let player = AVPlayer(url: url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        // Find the view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presentedVC = topVC.presentedViewController {
                topVC = presentedVC
            }
            
            topVC.present(playerViewController, animated: true) {
                print("Presentation completion handler executed for AVPlayerViewController")
                player.play()
            }
            
            // Add observer to clean up when done
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                print("Player item finished playing. Cleaning up temp file: \(url.lastPathComponent)")
                playerViewController.dismiss(animated: true)
            }
        }
    } else {
        print("Invalid video URL format")
    }
}

