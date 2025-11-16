import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PresentationCoordinator {
  static let shared = PresentationCoordinator()
  private var isPresenting = false

  func beginPresentation(_ context: String) -> Bool {
    guard !isPresenting else {
      print("[PresentationCoordinator] Blocked presentation: \(context) (another is active)")
      return false
    }
    isPresenting = true
    return true
  }

  func endPresentation() {
    isPresenting = false
  }
}

private let maxVideoDurationSeconds: Double = 180
private let cameraSafetyDurationSeconds: Double = 170

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

  let bannerViewLeading = bannerView.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 20)
  bannerViewLeading.priority = .defaultHigh
  bannerViewLeading.identifier = "bannerViewLeading"

  let bannerViewTrailing = bannerView.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -20)
  bannerViewTrailing.priority = .defaultHigh
  bannerViewTrailing.identifier = "bannerViewTrailing"

  let bannerViewHeight = bannerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
  bannerViewHeight.priority = .defaultLow
  bannerViewHeight.identifier = "bannerViewHeight"

  let labelLeading = label.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 16)
  labelLeading.priority = .defaultHigh
  labelLeading.identifier = "labelLeading"

  let labelTrailing = label.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -16)
  labelTrailing.priority = .defaultHigh
  labelTrailing.identifier = "labelTrailing"

  NSLayoutConstraint.activate([
    bannerViewLeading,
    bannerViewTrailing,
    bannerView.centerXAnchor.constraint(equalTo: window.centerXAnchor),
    bannerView.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 20),
    bannerViewHeight,

    labelLeading,
    labelTrailing,
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
    ZStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Select Incident Type")
              .font(.system(size: 30, weight: .bold, design: .rounded))
              .foregroundColor(DPUTheme.colors.lightGray)

            Text("Pick the category that best matches what happened. You’ll attach evidence right after this step.")
              .font(.subheadline)
              .foregroundColor(DPUTheme.colors.mutedGray)
          }

          VStack(spacing: 16) {
            ForEach(IncidentType.allCases, id: \.self) { type in
              DPUCard {
                Button(action: {
                  selectedType = type
                  showMediaOptions = true
                }) {
                  HStack(alignment: .top, spacing: 16) {
                    Text(type.emoji)
                      .font(.system(size: 36))
                      .frame(width: 48)

                    VStack(alignment: .leading, spacing: 6) {
                      Text(type.title)
                        .font(.headline)
                        .foregroundColor(DPUTheme.colors.lightGray)

                      Text(type.description)
                        .font(.subheadline)
                        .foregroundColor(DPUTheme.colors.mutedGray)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                      .foregroundColor(DPUTheme.colors.mutedGray)
                  }
                  .padding(.vertical, 4)
                  .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
              }
            }
          }

          Divider()
            .background(DPUTheme.colors.subtleSeparator)

          ModernButton(
            title: "Cancel",
            systemImage: "xmark.circle",
            style: .secondary
          ) {
            presentationMode.wrappedValue.dismiss()
          }
        }
        .glassSheetStyle()
      }

      if viewModel.uploadProgress > 0 && viewModel.uploadProgress < 1.0 {
        UploadProgressOverlay(viewModel: viewModel)
          .transition(.opacity)
          .animation(.easeInOut(duration: 0.3), value: viewModel.uploadProgress)
      }
    }
    .dpuBackground()
    .actionSheet(isPresented: $showMediaOptions) {
      ActionSheet(
        title: Text("Add Media"),
        message: Text("Choose a video source"),
        buttons: [
          .default(Text("Choose from Library")) {
            if selectedType != nil {
              // Delay to ensure action sheet is fully dismissed before presenting picker
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.shouldPresentPicker = true
              }
            }
          },
          .default(Text("Record Video (3 min max)")) {
            if let type = selectedType {
              // Check camera availability FIRST (for simulator compatibility)
              #if targetEnvironment(simulator)
              DispatchQueue.main.async {
                showGlobalErrorBanner("Camera is not available on simulator. Please use a physical device to record videos.")
              }
              #else
              // Delay to ensure action sheet is fully dismissed before presenting camera
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentVideoRecorder(
                  for: type, viewModel: self.viewModel, presentationMode: self.presentationMode)
              }
              #endif
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
        // Don't dismiss - let the delegate handle it after upload completes
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
  nonisolated(unsafe) let unsafePresentationMode = presentationMode
  
  PHPhotoLibrary.requestAuthorization(for: .readWrite) { [viewModel, incidentType] status in
    Task { @MainActor in
      // Access the unsafe binding here - safe because we're back on MainActor
      let dismissalBinding = unsafePresentationMode
      switch status {
      case .authorized, .limited:
        // Configure and present picker
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)

        // Create the delegate adapter
        let delegateAdapter = VideoDelegateAdapter(
          incidentType: incidentType, viewModel: viewModel, presentationMode: dismissalBinding)
        VideoDelegateAdapter.activeDelegates.append(delegateAdapter)
        picker.delegate = delegateAdapter

        // Find the correct view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first,
          let rootVC = window.rootViewController
        {
          guard PresentationCoordinator.shared.beginPresentation("Photo Picker") else {
            showGlobalErrorBanner("Another media picker is already open. Please finish that first.")
            return
          }
          
          var topController = rootVC
          while let presented = topController.presentedViewController {
            topController = presented
          }
          topController.present(picker, animated: true) {
            print("[IncidentTypePicker] Photo picker presented successfully")
          }
        } else {
          showGlobalErrorBanner("Could not present photo picker")
        }
      case .denied, .restricted:
        showGlobalErrorBanner(
          "Please allow access to your photo library in Settings to upload videos")
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(settingsURL)
        }
      case .notDetermined:
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
  nonisolated(unsafe) let unsafePresentationMode = presentationMode
  
  // Check if camera is available (not available on simulators)
  guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
    DispatchQueue.main.async {
      #if targetEnvironment(simulator)
      showGlobalErrorBanner("Camera is not available on simulator. Please use a physical device to record videos.")
      #else
      showGlobalErrorBanner("Camera is not available on this device.")
      #endif
    }
    return
  }
  
  AVCaptureDevice.requestAccess(for: .video) { [viewModel, incidentType] granted in
    DispatchQueue.main.async {
      // Access the unsafe binding here - safe because we're back on main thread
      let dismissalBinding = unsafePresentationMode
      
      if granted {
        // Create and configure the image picker for video recording
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.mediaTypes = [UTType.movie.identifier]
        imagePicker.cameraCaptureMode = .video
        imagePicker.videoMaximumDuration = cameraSafetyDurationSeconds
        imagePicker.videoQuality = .typeMedium  // Changed from .typeHigh to reduce initial file size
        imagePicker.allowsEditing = true

        // Create the delegate adapter
        let delegateAdapter = VideoRecorderDelegateAdapter(
          incidentType: incidentType, viewModel: viewModel, presentationMode: dismissalBinding)
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

          // Present the camera picker
          guard PresentationCoordinator.shared.beginPresentation("Video Recorder") else {
            showGlobalErrorBanner("Another media picker is already open. Please finish that first.")
            return
          }

          topController.present(imagePicker, animated: true) {
            print("[IncidentTypePicker] Video recorder presented successfully")
          }
        } else {
          PresentationCoordinator.shared.endPresentation()
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

    // Only dismiss the video picker, keep the incident type picker open to show progress
    picker.dismiss(animated: true) {
      PresentationCoordinator.shared.endPresentation()
      if let result = selectedResult {
        print("[VideoDelegateAdapter] User selected a video, starting processing...")

        // Show immediate visual feedback
        DispatchQueue.main.async {
          self.viewModel.uploadProgress = 0.05
        }

        // Process video with proper error handling
        Task {
          await self.processVideoSafely(result)
          
          // After successful processing, dismiss the incident type picker
          await MainActor.run {
            if self.viewModel.uploadProgress >= 0.9 || self.viewModel.uploadProgress == 0 {
              self.presentationMode.wrappedValue.dismiss()
            }
          }
        }
      } else {
        print("[VideoDelegateAdapter] User canceled video selection")
        DispatchQueue.main.async {
          self.viewModel.clearPendingData()
          // Dismiss on cancel
          self.presentationMode.wrappedValue.dismiss()
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

    let durationSeconds: Double = asset.duration

    if durationSeconds > maxVideoDurationSeconds {
      print("[VideoDelegateAdapter] Video duration \(durationSeconds)s exceeds limit")
      await MainActor.run {
        self.viewModel.uploadProgress = 0
        self.viewModel.clearPendingData()
        self.showErrorBanner("Videos must be 3 minutes or less. Please trim your clip and try again.")
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

    let bannerViewLeading = bannerView.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 20)
    bannerViewLeading.priority = .defaultHigh
    bannerViewLeading.identifier = "bannerViewLeading"

    let bannerViewTrailing = bannerView.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -20)
    bannerViewTrailing.priority = .defaultHigh
    bannerViewTrailing.identifier = "bannerViewTrailing"

    let bannerViewHeight = bannerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
    bannerViewHeight.priority = .defaultLow
    bannerViewHeight.identifier = "bannerViewHeight"

    let labelLeading = label.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 16)
    labelLeading.priority = .defaultHigh
    labelLeading.identifier = "labelLeading"

    let labelTrailing = label.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -16)
    labelTrailing.priority = .defaultHigh
    labelTrailing.identifier = "labelTrailing"

    NSLayoutConstraint.activate([
      bannerViewLeading,
      bannerViewTrailing,
      bannerView.centerXAnchor.constraint(equalTo: window.centerXAnchor),
      bannerView.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 20),
      bannerViewHeight,

      labelLeading,
      labelTrailing,
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

  init(
    incidentType: IncidentType, viewModel: MapViewModel, presentationMode: Binding<PresentationMode>
  ) {
    self.incidentType = incidentType
    self.viewModel = viewModel
    self.presentationMode = presentationMode
    super.init()
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    print("[VideoRecorderDelegateAdapter] Video recording finished")

    // Only dismiss the camera/recorder, keep the incident type picker open to show progress
    picker.dismiss(animated: true) {
      PresentationCoordinator.shared.endPresentation()
      // Get the video URL from the info dictionary
      guard let videoURL = info[.mediaURL] as? URL else {
        print("[VideoRecorderDelegateAdapter] No video URL found")
        DispatchQueue.main.async {
          showGlobalErrorBanner("Failed to retrieve recorded video")
          self.viewModel.clearPendingData()
          // Dismiss on error
          self.presentationMode.wrappedValue.dismiss()
        }
        return
      }

      print("[VideoRecorderDelegateAdapter] Video recorded, starting processing...")

      // Show immediate feedback
      DispatchQueue.main.async {
        self.viewModel.uploadProgress = 0.05
      }

      // Process video in background
      Task {
        await self.processVideoInBackground(videoURL)
        
        // After successful processing, dismiss the incident type picker
        await MainActor.run {
          if self.viewModel.uploadProgress >= 0.9 || self.viewModel.uploadProgress == 0 {
            self.presentationMode.wrappedValue.dismiss()
          }
        }
      }
    }

    // Remove this delegate from the static array to avoid memory leaks
    Self.activeDelegates.removeAll { $0 === self }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    print("[VideoRecorderDelegateAdapter] Video recording canceled")

    // Dismiss both the recorder and the incident type picker on cancel
    picker.dismiss(animated: true) {
      PresentationCoordinator.shared.endPresentation()
      DispatchQueue.main.async {
        self.viewModel.clearPendingData()
        self.presentationMode.wrappedValue.dismiss()
      }
    }

    // Remove this delegate from the static array to avoid memory leaks
    Self.activeDelegates.removeAll { $0 === self }
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

      let asset = AVURLAsset(url: videoURL)
      let durationSeconds: Double
      if #available(iOS 16.0, *) {
        let loadedDuration = try await asset.load(.duration)
        durationSeconds = CMTimeGetSeconds(loadedDuration)
      } else {
        durationSeconds = CMTimeGetSeconds(asset.duration)
      }
      guard durationSeconds <= cameraSafetyDurationSeconds else {
        throw NSError(
          domain: "VideoRecorderDelegateAdapter",
          code: -2,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Recorded video is longer than 3 minutes. Please record a shorter clip."
          ])
      }

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



