import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
          viewModel.showError("Could not present photo picker")
        }

      case .denied, .restricted:
        viewModel.showError(
          "Please allow access to your photo library in Settings to upload videos")
        // Optionally open settings
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(settingsURL)
        }

      case .notDetermined:
        // This shouldn't happen since we just requested authorization
        viewModel.showError("Photo library access not determined")

      @unknown default:
        viewModel.showError("Unknown photo library access status")
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
        imagePicker.mediaTypes = ["public.movie"]
        imagePicker.cameraCaptureMode = .video
        imagePicker.videoMaximumDuration = 180  // 3 minutes
        imagePicker.videoQuality = .typeHigh
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
          viewModel.showError("Could not present video recorder")
        }
      } else {
        viewModel.showError("Please allow access to your camera in Settings to record videos")
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
      viewModel.showError("Failed to process video: \(error.localizedDescription)")
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

    // Immediately dismiss the picker and IncidentTypePicker to reduce UI blocking
    picker.dismiss(animated: true) {
      DispatchQueue.main.async {
        self.presentationMode.wrappedValue.dismiss()
      }
    }

    // Remove this delegate from the static array to avoid memory leaks
    Self.activeDelegates.removeAll { $0 === self }

    guard let result = results.first else {
      print("[VideoDelegateAdapter] User canceled video selection")
      DispatchQueue.main.async {
        self.viewModel.clearPendingData()
      }
      return
    }

    print("[VideoDelegateAdapter] User selected a video, starting processing...")

    // Process video in background to avoid main thread blocking
    Task.detached(priority: .userInitiated) {
      await self.processVideoInBackground(result)
    }
  }

  private func processVideoInBackground(_ result: PHPickerResult) async {
    do {
      // Show immediate feedback to user - run on main thread
      await MainActor.run {
        self.viewModel.uploadProgress = 0.1  // Show we're starting
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
        self.viewModel.uploadProgress = 0.2
      }

      print("[VideoDelegateAdapter] Video loaded successfully, starting upload...")

      // Start upload directly without additional processing
      try await self.viewModel.dropPinWithVideo(for: self.incidentType, videoURL: tempURL)

    } catch {
      print("[VideoDelegateAdapter] Error processing video: \(error.localizedDescription)")
      await MainActor.run {
        // Provide user-friendly error messages
        let userMessage: String
        if error.localizedDescription.contains("copyItem") {
          userMessage =
            "Unable to access the selected video. Please try selecting a different video."
        } else if error.localizedDescription.contains("No video file") {
          userMessage =
            "The selected file is not a valid video. Please choose a video from your library."
        } else {
          userMessage = "Unable to process video. Please try again or select a different video."
        }

        self.viewModel.showError(userMessage)
        self.viewModel.clearPendingData()
      }
    }
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
        self.viewModel.showError("Failed to retrieve recorded video")
        self.viewModel.clearPendingData()
      }
      return
    }

    print("[VideoRecorderDelegateAdapter] Video recorded, starting processing...")

    // Process video in background
    Task.detached(priority: .userInitiated) {
      await self.processVideoInBackground(videoURL)
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
        self.viewModel.showError("Failed to process recorded video: \(error.localizedDescription)")
        self.viewModel.clearPendingData()
      }
    }
  }
}

// MARK: - Video loading (iOS 16+ uses async API directly)

// MARK: - ItemProvider Compatibility helper (bridges older callback API)

// Removed loadMovie function - no longer needed with improved video handling
