@preconcurrency import AVFoundation
import MapKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Always present modals from the topmost view controller to avoid UIKit constraint issues.
func topMostViewController() -> UIViewController? {
  guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
    return nil
  }
  var topController = windowScene.windows.first { $0.isKeyWindow }?.rootViewController
  while let presented = topController?.presentedViewController {
    topController = presented
  }
  return topController
}

/// Minimalist incident type picker that appears after long press
struct IncidentPickerView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: MapViewModel

  var body: some View {
    VStack(spacing: 20) {
      // Simple incident type options in a horizontal layout
      HStack(spacing: 25) {
        ForEach(IncidentType.allCases, id: \.self) { type in
          Button {
            // Save the type and move into the video/photo flow
            viewModel.beginVideoCaptureFlow(for: type)
            dismiss()
          } label: {
            VStack(spacing: 8) {
              Text(type.emoji)
                .font(.system(size: 50))

              Text(type.title)
                .font(.caption)
                .foregroundColor(.white)
            }
            .frame(width: 90, height: 90)
            .background(type.color.opacity(0.2))
            .cornerRadius(12)
          }
        }
      }
      .padding(.top, 30)

      Spacer()
    }
    .presentationDetents([.height(180)])
    .presentationBackground(.ultraThinMaterial)
  }
}

/// Minimal upload progress overlay that appears during video upload
struct UploadProgressView: View {
  @ObservedObject var viewModel: MapViewModel

  var body: some View {
    VStack {
      Spacer()

      HStack {
        Spacer()

        // Non-intrusive upload progress indicator
        VStack(spacing: 8) {
          ProgressView(value: viewModel.uploadProgress)
            .progressViewStyle(LinearProgressViewStyle())
            .frame(width: 200)

          Text("Uploading video \(Int(viewModel.uploadProgress * 100))%")
            .font(.caption)
            .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)

        Spacer()
      }
      .padding(.bottom, 30)
    }
    .ignoresSafeArea()
  }
}

/// Extension for MapView to implement streamlined reporting flow
extension MapView {
  // This would be called from the Coordinator's handleLongPress method
  func handlePinDrop(at coordinate: CLLocationCoordinate2D) {
    viewModel.startReportFlow(at: coordinate)

    // Present the incident picker
    showIncidentPicker()
  }

  // Shows the incident picker sheet
  private func showIncidentPicker() {
    guard let topVC = topMostViewController() else {
      return
    }

    let incidentPicker = UIHostingController(rootView: IncidentPickerView(viewModel: viewModel))
    incidentPicker.modalPresentationStyle = .formSheet

    topVC.present(incidentPicker, animated: true)

    // Set up observation for when the incident type gets selected
    NotificationCenter.default.addObserver(
      forName: .incidentTypeSelected, object: nil, queue: .main
    ) { _ in
      // Dismiss the incident picker first
      incidentPicker.dismiss(animated: true) {
        // Then show the photo picker
        self.showPhotoPicker()
      }
    }
  }

  // Shows the native photo picker immediately after incident selection
  private func showPhotoPicker() {
    var config = PHPickerConfiguration()
    config.selectionLimit = 1
    config.filter = .videos

    let picker = PHPickerViewController(configuration: config)

    // Use the Coordinator as the delegate instead of self
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let coordinator = (windowScene.windows.first?.rootViewController?.view as? MKMapView)?
        .delegate as? Coordinator
    {
      picker.delegate = coordinator
    } else {
      viewModel.showError("Could not setup photo picker")
      return
    }

    guard let topVC = topMostViewController() else {
      return
    }

    topVC.present(picker, animated: true)
  }
}

// MARK: - Video Picking Implementation - Move to Coordinator class
extension Coordinator {
  // Nonisolated helper to copy movies to a stable temp URL (usable from background callbacks)
  nonisolated private func copyMovieToTempNonisolated(url: URL) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let target = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    try FileManager.default.copyItem(at: url, to: target)
    return target
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    // Dismiss picker immediately
    picker.dismiss(animated: true)
    print("[Picker] didFinishPicking. results: \(results.count)")

    // Perspective flow: handle witness upload first if a pin is pending.
    if let perspectivePin = pendingPerspectivePin {
      pendingPerspectivePin = nil

      guard let provider = results.first?.itemProvider,
        provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      else {
        Task { @MainActor in
          parent.viewModel.showError("Please select a video.")
        }
        print("[Picker] Perspective flow missing movie provider.")
        return
      }

      print("[Picker] Loading movie for perspective pin \(perspectivePin.id)")
      provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
        guard let self else { return }

        if let error {
          print("[Picker] loadFileRepresentation error: \(error.localizedDescription)")
          Task { @MainActor in
            self.parent.viewModel.showError("Unable to load video: \(error.localizedDescription)")
          }
          return
        }

        guard let fileURL = url else {
          print("[Picker] No URL returned from loadFileRepresentation")
          Task { @MainActor in
            self.parent.viewModel.showError("No video URL returned.")
          }
          return
        }

        do {
          let tempURL = try self.copyMovieToTempNonisolated(url: fileURL)
          Task { @MainActor in
            print("[Picker] Prepared temp URL for perspective: \(tempURL.lastPathComponent)")
            await self.parent.viewModel.uploadPerspective(for: perspectivePin, videoURL: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
          }
        } catch {
          print("[Picker] copyMovieToTemp failed: \(error.localizedDescription)")
          Task { @MainActor in
            self.parent.viewModel.showError("Failed to prepare video: \(error.localizedDescription)")
          }
        }
      }
      return
    }

    // Handle video selection
    guard let result = results.first else {
      // User canceled selection, abort the flow
      parent.viewModel.reportStep = nil
      Task { @MainActor in
        parent.viewModel.showError("No video selected.")
      }
      print("[Picker] No results; user likely cancelled.")
      return
    }

    // Check video metadata first
    guard let assetId = result.assetIdentifier,
      let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
    else {
      Task { @MainActor in
        self.parent.viewModel.showError("Could not load video metadata.")
      }
      print("[Picker] Could not load PHAsset for selected video.")
      return
    }

    let draftCoord = self.parent.viewModel.reportDraft.coordinate
    let pinLocation = CLLocation(latitude: draftCoord.latitude, longitude: draftCoord.longitude)

    Task { @MainActor in
      let validationResult = await self.parent.viewModel.validateVideoMetadata(
        asset: asset,
        pinLocation: pinLocation
      )

      guard validationResult.isValid else {
        // Show specific error message explaining the problem and how to fix it
        self.parent.viewModel.showError(
          validationResult.errorMessage,
          title: "Video Not Accepted"
        )
        return
      }

      // Continue with the rest of the process if metadata check passes
      // Get the video URL from the result
      result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) {
        url, error in
        if let error {
          print("[Picker] Pin flow loadFileRepresentation error: \(error.localizedDescription)")
        }
        #if DEBUG
        if let url { print("[Picker] Pin flow got file URL: \(url.lastPathComponent)") }
        #endif

        guard let url = url else {
          Task { @MainActor in
            self.parent.viewModel.showError("Could not load video")
          }
          return
        }

        // Check video duration (limit to 3 minutes)
        Task {
          do {
            // Copy to our own temp location to keep the file available during upload
            let tempURL = try self.copyMovieToTempNonisolated(url: url)
            #if DEBUG
            print("[Picker] Pin flow temp copy: \(tempURL.lastPathComponent)")
            #endif
            
            let asset = AVAsset(url: tempURL)
            // Get video duration using modern API
            var duration: CMTime = .zero

            if #available(iOS 16.0, *) {
              // Use modern async/await API in iOS 16+
              duration = try await asset.load(.duration)
            } else {
              // Use older API for iOS 15 and below
              let durationKey = "duration"
              try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                asset.loadValuesAsynchronously(forKeys: [durationKey]) {
                  var error: NSError?
                  let status = asset.statusOfValue(forKey: durationKey, error: &error)

                  if status == .loaded {
                    duration = asset.duration
                    continuation.resume()
                  } else if let error = error {
                    continuation.resume(throwing: error)
                  } else {
                    continuation.resume(
                      throwing: NSError(
                        domain: "AVAsset", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load duration"]))
                  }
                }
              }
            }

            // Check if video is too long
            let maxDurationInSeconds: Double = 180  // 3 minutes
            if duration.seconds > maxDurationInSeconds {
              let minutes = Int(duration.seconds / 60)
              let seconds = Int(duration.seconds) % 60
              print("[SimplifiedReportFlow] Video too long: \(duration.seconds) seconds")
              await MainActor.run {
                self.parent.viewModel.showError(
                  "This video is \(minutes):\(String(format: "%02d", seconds)) long.\n\nVideos must be 3 minutes or less to keep reports concise and ensure quick uploads.\n\nTip: Trim your video in the Photos app before selecting it, or record a shorter clip.",
                  title: "Video Too Long"
                )
              }
              return
            }

            // Video is acceptable
            await MainActor.run {
              self.parent.viewModel.reportDraft.videoURL = tempURL
              Task {
                await self.parent.viewModel.upload(draft: self.parent.viewModel.reportDraft)
              }
            }
          } catch {
            print("[SimplifiedReportFlow] Error checking video duration: \(error)")
            await MainActor.run {
              self.parent.viewModel.showError(
                "Error processing video: \(error.localizedDescription)")
            }
          }
        }
      }
    }
  }
}

// Custom notification for when incident type is selected
extension Notification.Name {
  static let incidentTypeSelected = Notification.Name("incidentTypeSelected")
}
