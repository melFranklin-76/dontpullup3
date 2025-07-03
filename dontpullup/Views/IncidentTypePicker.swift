import AVKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Global function to show error banners from anywhere in this file
func showGlobalErrorBanner(_ message: String) {
  print("[IncidentTypePicker] SHOWING GLOBAL ERROR BANNER: \(message)")
  guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
    let window = windowScene.windows.first
  else {
    print("[IncidentTypePicker] ERROR: Could not find window scene for banner")
    return
  }

  let bannerView = UIView()
  bannerView.backgroundColor = UIColor.systemRed
  bannerView.layer.cornerRadius = 10
  bannerView.translatesAutoresizingMaskIntoConstraints = false

  let label = UILabel()
  label.text = message
  label.textColor = .white
  label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
  label.numberOfLines = 0
  label.textAlignment = .center
  label.translatesAutoresizingMaskIntoConstraints = false

  bannerView.addSubview(label)
  window.addSubview(bannerView)

  NSLayoutConstraint.activate([
    bannerView.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 20),
    bannerView.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -20),
    bannerView.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 20),
    bannerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

    label.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 16),
    label.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -16),
    label.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor),
  ])

  // Animate in
  bannerView.alpha = 0
  bannerView.transform = CGAffineTransform(translationX: 0, y: -100)

  UIView.animate(
    withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: []
  ) {
    bannerView.alpha = 1
    bannerView.transform = .identity
  }

  // Auto-dismiss after 4 seconds
  DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
    UIView.animate(
      withDuration: 0.3,
      animations: {
        bannerView.alpha = 0
        bannerView.transform = CGAffineTransform(translationX: 0, y: -100)
      }
    ) { _ in
      bannerView.removeFromSuperview()
    }
  }
}

struct IncidentTypePicker: View {
  @ObservedObject var viewModel: MapViewModel
  @Environment(\.presentationMode) var presentationMode
  @State private var selectedType: IncidentType?
  @State private var shouldPresentPicker = false
  @State private var showMediaOptions = false

  var body: some View {
    NoBounceScrollView {
      VStack(spacing: 24) {
        Text("Select Incident Type")
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.white)
          .padding(.top, 24)
          .padding(.bottom, 8)

        // Incident type buttons with improved spacing
        VStack(spacing: 16) {
          ForEach(IncidentType.allCases, id: \.self) { type in
            DPUCard(backgroundColor: Color.black.opacity(0.6)) {
              Button(action: {
                selectedType = type
                // Show media options sheet instead of immediately presenting picker
                showMediaOptions = true
              }) {
                HStack {
                  Text(type.emoji)
                    .font(.system(size: 36))
                    .frame(width: 60)

                  VStack(alignment: .leading, spacing: 4) {
                    Text(type.title)
                      .font(.headline)
                      .foregroundColor(.white)

                    Text(type.description)
                      .font(.subheadline)
                      .foregroundColor(.gray)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                  .padding(.vertical, 8)

                  Spacer()

                  Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .padding(.trailing, 8)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(PlainButtonStyle())
            }
          }
        }

        Spacer(minLength: 40)

        DPUCard(backgroundColor: Color.black.opacity(0.6)) {
          Button(action: {
            presentationMode.wrappedValue.dismiss()
          }) {
            Text("Cancel")
              .font(.headline)
              .foregroundColor(.red)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
          }
        }
      }
      .padding(.horizontal, 16)
    }
    .actionSheet(isPresented: $showMediaOptions) {
      ActionSheet(
        title: Text("Add Media"),
        message: Text("Choose a video source"),
        buttons: [
          .default(Text("Choose from Library")) {
            if selectedType != nil {
              shouldPresentPicker = true
            }
          },
          .default(Text("Record Video (3 min max)")) {
            if let type = selectedType {
              presentVideoRecorder(
                for: type, viewModel: viewModel, presentationMode: presentationMode)
            }
          },
          .cancel(),
        ]
      )
    }
    .onChange(of: shouldPresentPicker) { newValue in
      if newValue, let type = selectedType {
        // Present immediately without delay to avoid view hierarchy issues
        presentVideoPickerDirectly(
          for: type, viewModel: viewModel, presentationMode: presentationMode)
        shouldPresentPicker = false
      }
    }
  }
}

// Helper function to present the video picker using UIKit
@MainActor
func presentVideoPickerDirectly(
  for incidentType: IncidentType, viewModel: MapViewModel,
  presentationMode: Binding<PresentationMode>
) {
  // First check photo library permission
  PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
    DispatchQueue.main.async {
      switch status {
      case .authorized, .limited:
        // Configure and present picker
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)

        // Create the delegate adapter
        let delegateAdapter = VideoDelegateAdapter(
          incidentType: incidentType, viewModel: viewModel, presentationMode: presentationMode)
        VideoDelegateAdapter.activeDelegates.append(delegateAdapter)
        picker.delegate = delegateAdapter

        // Find the correct view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first,
          let rootVC = window.rootViewController
        {

          // Find the topmost presented controller
          var topController = rootVC
          while let presented = topController.presentedViewController {
            topController = presented
          }

          // Present immediately without delay and dismiss IncidentTypePicker after
          topController.present(picker, animated: true) {
            // Don't dismiss IncidentTypePicker here - wait for photo picker to finish
            print("[IncidentTypePicker] Photo picker presented successfully")
          }
        } else {
          showGlobalErrorBanner("Could not present photo picker")
        }

      case .denied, .restricted:
        showGlobalErrorBanner(
          "Please allow access to your photo library in Settings to upload videos")
        // Optionally open settings
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(settingsURL)
        }

      case .notDetermined:
        // This shouldn't happen since we just requested authorization
        showGlobalErrorBanner("Photo library access not determined")

      @unknown default:
        showGlobalErrorBanner("Unknown photo library access status")
      }
    }
  }
}

// Helper function to present the video recorder
@MainActor
func presentVideoRecorder(
  for incidentType: IncidentType, viewModel: MapViewModel,
  presentationMode: Binding<PresentationMode>
) {
  // Check camera permission first
  AVCaptureDevice.requestAccess(for: .video) { granted in
    DispatchQueue.main.async {
      if granted {
        // Create and configure the image picker for video recording
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.mediaTypes = [UTType.movie.identifier]
        imagePicker.cameraCaptureMode = .video
        imagePicker.videoMaximumDuration = 180  // 3 minutes

        // Set video quality to VGA (640x480) to match compression target
        // This eliminates the need for compression since we capture at the target resolution
        imagePicker.videoQuality = .type640x480  // VGA quality - matches compression target

        imagePicker.allowsEditing = true

        // Create the delegate adapter
        let delegateAdapter = VideoRecorderDelegateAdapter(
          incidentType: incidentType, viewModel: viewModel, presentationMode: presentationMode)
        VideoRecorderDelegateAdapter.activeDelegates.append(delegateAdapter)
        imagePicker.delegate = delegateAdapter

        // Find the correct view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first,
          let rootVC = window.rootViewController
        {

          // Find the topmost presented controller
          var topController = rootVC
          while let presented = topController.presentedViewController {
            topController = presented
          }

          // Present immediately
          topController.present(imagePicker, animated: true) {
            print("[IncidentTypePicker] Video recorder presented successfully")
          }
        } else {
          showGlobalErrorBanner("Could not present video recorder")
        }
      } else {
        showGlobalErrorBanner("Please allow access to your camera in Settings to record videos")
        // Optionally open settings
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(settingsURL)
        }
      }
    }
  }
}

// Helper class to handle async operations
@MainActor
class VideoProcessor {
  let viewModel: MapViewModel
  let incidentType: IncidentType

  init(viewModel: MapViewModel, incidentType: IncidentType) {
    self.viewModel = viewModel
    self.incidentType = incidentType
  }

  func processVideo(_ result: PHPickerResult) async {
    do {
      // Load the video data directly instead of trying to copy a temporary file
      let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")

      // Use loadFileRepresentation to get the actual video data
      let success = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Bool, Error>) in
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) {
          url, error in
          if let error = error {
            continuation.resume(throwing: error)
            return
          }

          guard let sourceURL = url else {
            continuation.resume(
              throwing: NSError(
                domain: "VideoProcessor", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No video URL provided"]))
            return
          }

          do {
            // Copy the file data to our temporary location
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
            continuation.resume(returning: true)
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }

      if success {
        try await viewModel.dropPinWithVideo(for: incidentType, videoURL: tempURL)
      }
    } catch {
      showGlobalErrorBanner("Failed to process video: \(error.localizedDescription)")
      viewModel.clearPendingData()
    }
  }
}

class VideoDelegateAdapter: NSObject, PHPickerViewControllerDelegate {
  // Static array to hold strong references to active delegates
  static var activeDelegates = [VideoDelegateAdapter]()

  let incidentType: IncidentType
  let viewModel: MapViewModel
  let presentationMode: Binding<PresentationMode>

  init(
    incidentType: IncidentType, viewModel: MapViewModel, presentationMode: Binding<PresentationMode>
  ) {
    self.incidentType = incidentType
    self.viewModel = viewModel
    self.presentationMode = presentationMode
    super.init()
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    print("[VideoDelegateAdapter] Photo picker finished with \(results.count) results")
    print("[VideoDelegateAdapter] USING NEW CODE PATH - Photo picker delegate")

    // Store the result for processing after dismissal
    let selectedResult = results.first

    // Immediately dismiss the picker and IncidentTypePicker to reduce UI blocking
    picker.dismiss(animated: true) {
      DispatchQueue.main.async {
        self.presentationMode.wrappedValue.dismiss()

        // Wait for UI to settle before processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          if let result = selectedResult {
            print("[VideoDelegateAdapter] User selected a video, starting processing...")

            // Show immediate visual feedback
            self.viewModel.uploadProgress = 0.05

            // Process video with proper error handling
            Task {
              await self.processVideoSafely(result)
            }
          } else {
            print("[VideoDelegateAdapter] User canceled video selection")
            self.viewModel.clearPendingData()
          }
        }
      }
    }

    // Remove this delegate from the static array to avoid memory leaks
    Self.activeDelegates.removeAll { $0 === self }
  }

  // New method that handles errors without showing alerts
  private func processVideoSafely(_ result: PHPickerResult) async {
    print("[VideoDelegateAdapter] ENTERING processVideoSafely - NEW METHOD")
    // Show processing feedback
    await MainActor.run {
      self.viewModel.uploadProgress = 0.1
      print("[VideoDelegateAdapter] Set upload progress to 0.1")
    }

    // Check video metadata before proceeding
    guard let assetId = result.assetIdentifier,
      let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject,
      let coord = await MainActor.run(body: { self.viewModel.pendingCoordinate })
    else {
      print("[VideoDelegateAdapter] Could not load video metadata")
      await MainActor.run {
        self.viewModel.uploadProgress = 0
        self.viewModel.clearPendingData()
        // Show error as a banner instead of alert
        self.showErrorBanner("Could not load video metadata")
      }
      return
    }

    let pinLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
    let isValid = await self.viewModel.checkVideoMetadata(asset: asset, pinLocation: pinLocation)

    guard isValid else {
      print("[VideoDelegateAdapter] Video metadata validation failed")
      await MainActor.run {
        self.viewModel.uploadProgress = 0
        self.viewModel.clearPendingData()
        // Show error as a banner instead of alert
        self.showErrorBanner("Video must be ≤5 hours old and ≤200 ft from the pin location")
      }
      return
    }

    // Process video in background
    do {
      try await self.processVideoInBackground(result)
    } catch {
      print("[VideoDelegateAdapter] Video processing failed: \(error)")
      await MainActor.run {
        self.viewModel.uploadProgress = 0
        self.viewModel.clearPendingData()
        self.showErrorBanner("Failed to process video: \(error.localizedDescription)")
      }
    }
  }

  // Show error as a temporary banner instead of alert
  private func showErrorBanner(_ message: String) {
    print("[VideoDelegateAdapter] SHOWING ERROR BANNER: \(message)")
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first
    else {
      print("[VideoDelegateAdapter] ERROR: Could not find window scene for banner")
      return
    }

    let bannerView = UIView()
    bannerView.backgroundColor = UIColor.systemRed
    bannerView.layer.cornerRadius = 10
    bannerView.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = message
    label.textColor = .white
    label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    bannerView.addSubview(label)
    window.addSubview(bannerView)

    NSLayoutConstraint.activate([
      bannerView.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 20),
      bannerView.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -20),
      bannerView.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 20),
      bannerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

      label.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -16),
      label.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor),
    ])

    // Animate in
    bannerView.alpha = 0
    bannerView.transform = CGAffineTransform(translationX: 0, y: -100)

    UIView.animate(
      withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
      options: []
    ) {
      bannerView.alpha = 1
      bannerView.transform = .identity
    }

    // Auto-dismiss after 4 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
      UIView.animate(
        withDuration: 0.3,
        animations: {
          bannerView.alpha = 0
          bannerView.transform = CGAffineTransform(translationX: 0, y: -100)
        }
      ) { _ in
        bannerView.removeFromSuperview()
      }
    }
  }

  private func processVideoInBackground(_ result: PHPickerResult) async throws {
    // Show immediate feedback to user - run on main thread
    await MainActor.run {
      self.viewModel.uploadProgress = 0.2  // Show we're starting
    }

    // Create temporary URL for video processing
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")

    // Load video file WITHOUT timeout wrapper to avoid deadlock
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) {
        url, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        guard let sourceURL = url else {
          continuation.resume(
            throwing: NSError(
              domain: "VideoDelegateAdapter", code: -1,
              userInfo: [NSLocalizedDescriptionKey: "No video file was provided"]))
          return
        }

        do {
          // Quick copy without processing
          try FileManager.default.copyItem(at: sourceURL, to: tempURL)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }

    // Update progress and start upload immediately - run on main thread
    await MainActor.run {
      self.viewModel.uploadProgress = 0.3
    }

    print("[VideoDelegateAdapter] Video loaded successfully, starting upload...")

    // Start upload directly without additional processing
    try await self.viewModel.dropPinWithVideo(for: self.incidentType, videoURL: tempURL)
  }
}

// Delegate adapter for handling video recording with UIImagePickerController
class VideoRecorderDelegateAdapter: NSObject, UIImagePickerControllerDelegate,
  UINavigationControllerDelegate
{
  // Static array to hold strong references to active delegates
  static var activeDelegates = [VideoRecorderDelegateAdapter]()

  let incidentType: IncidentType
  let viewModel: MapViewModel
  let presentationMode: Binding<PresentationMode>

  // Track background tasks
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  init(
    incidentType: IncidentType, viewModel: MapViewModel, presentationMode: Binding<PresentationMode>
  ) {
    self.incidentType = incidentType
    self.viewModel = viewModel
    self.presentationMode = presentationMode
    super.init()
  }

  deinit {
    // Make sure any background tasks are ended
    endBackgroundTaskIfNeeded()
  }

  private func beginBackgroundTask() {
    // End any existing task first
    endBackgroundTaskIfNeeded()

    // Start a new background task
    backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
      // This is the expiration handler
      self?.endBackgroundTaskIfNeeded()
    }

    print("[VideoRecorderDelegateAdapter] Started background task: \(backgroundTaskID.rawValue)")
  }

  private func endBackgroundTaskIfNeeded() {
    if backgroundTaskID != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTaskID)
      print("[VideoRecorderDelegateAdapter] Ended background task: \(backgroundTaskID.rawValue)")
      backgroundTaskID = .invalid
    }
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    print("[VideoRecorderDelegateAdapter] Video recording finished")

    // Begin background task to handle camera power controller
    beginBackgroundTask()

    // Dismiss the recorder and the incident type picker
    picker.dismiss(animated: true) {
      DispatchQueue.main.async {
        self.presentationMode.wrappedValue.dismiss()
      }
    }

    // Remove this delegate from the static array to avoid memory leaks
    Self.activeDelegates.removeAll { $0 === self }

    // Get the video URL from the info dictionary
    guard let videoURL = info[.mediaURL] as? URL else {
      print("[VideoRecorderDelegateAdapter] No video URL found")
      DispatchQueue.main.async {
        showGlobalErrorBanner("Failed to retrieve recorded video")
        self.viewModel.clearPendingData()
      }
      self.endBackgroundTaskIfNeeded()
      return
    }

    print("[VideoRecorderDelegateAdapter] Video recorded, starting processing...")

    // Process video in background
    Task.detached(priority: .userInitiated) {
      await self.processVideoInBackground(videoURL)
      // End background task after processing completes
      await MainActor.run {
        self.endBackgroundTaskIfNeeded()
      }
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    print("[VideoRecorderDelegateAdapter] Video recording canceled")

    // Dismiss the recorder but keep the incident type picker open
    picker.dismiss(animated: true)

    // Remove this delegate from the static array to avoid memory leaks
    Self.activeDelegates.removeAll { $0 === self }

    // Clear any pending data
    DispatchQueue.main.async {
      self.viewModel.clearPendingData()
    }

    // End any background task
    endBackgroundTaskIfNeeded()
  }

  private func processVideoInBackground(_ videoURL: URL) async {
    do {
      // Show immediate feedback to user
      await MainActor.run {
        self.viewModel.uploadProgress = 0.1
      }

      // Create a temporary URL for the video
      let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")

      // Copy the video to the temporary location
      try FileManager.default.copyItem(at: videoURL, to: tempURL)

      // Update progress
      await MainActor.run {
        self.viewModel.uploadProgress = 0.2
      }

      print("[VideoRecorderDelegateAdapter] Video prepared successfully, starting upload...")

      // Check if file exists at the temporary URL
      if FileManager.default.fileExists(atPath: tempURL.path) {
        print(
          "[VideoRecorderDelegateAdapter] Video file exists at temporary location: \(tempURL.path)")
      } else {
        print("[VideoRecorderDelegateAdapter] ERROR: Video file not found at: \(tempURL.path)")
      }

      // Set the pending coordinate if it's not already set
      if self.viewModel.pendingCoordinate == nil,
        let userLocation = self.viewModel.userLocation?.coordinate
      {
        print(
          "[VideoRecorderDelegateAdapter] Setting pending coordinate to user location: \(userLocation)"
        )
        await MainActor.run {
          self.viewModel.pendingCoordinate = userLocation
        }
      }

      // Start upload with explicit error handling
      do {
        try await self.viewModel.dropPinWithVideo(for: self.incidentType, videoURL: tempURL)
        print("[VideoRecorderDelegateAdapter] Upload completed successfully")
      } catch {
        print("[VideoRecorderDelegateAdapter] Error during dropPinWithVideo: \(error)")
        throw error
      }

    } catch {
      print("[VideoRecorderDelegateAdapter] Error processing video: \(error.localizedDescription)")
      await MainActor.run {
        showGlobalErrorBanner("Failed to process recorded video: \(error.localizedDescription)")
        self.viewModel.clearPendingData()
      }
    }
  }
}

// MARK: - Video loading (iOS 16+ uses async API directly)

// MARK: - ItemProvider Compatibility helper (bridges older callback API)

// Removed loadMovie function - no longer needed with improved video handling
