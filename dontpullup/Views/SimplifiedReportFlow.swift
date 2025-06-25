@preconcurrency import AVFoundation
import MapKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
            // When incident type is selected:
            // 1. Save the type to the draft
            viewModel.reportDraft.incidentType = type
            // 2. Dismiss this sheet
            dismiss()
            // 3. Present the photo picker (this is called from the parent view)
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
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = windowScene.windows.first?.rootViewController
    else {
      return
    }

    let incidentPicker = UIHostingController(rootView: IncidentPickerView(viewModel: viewModel))
    incidentPicker.modalPresentationStyle = .formSheet

    rootVC.present(incidentPicker, animated: true)

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

    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = windowScene.windows.first?.rootViewController
    else {
      return
    }

    rootVC.present(picker, animated: true)
  }
}

// MARK: - Video Picking Implementation - Move to Coordinator class
extension Coordinator: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    // Dismiss picker immediately
    picker.dismiss(animated: true)

    // Handle video selection
    guard let result = results.first else {
      // User canceled selection, abort the flow
      parent.viewModel.reportStep = nil
      return
    }

    // Check video metadata first
    guard let assetId = result.assetIdentifier,
      let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
    else {
      Task { @MainActor in
        self.parent.viewModel.showError("Could not load video metadata.")
      }
      return
    }

    let draftCoord = self.parent.viewModel.reportDraft.coordinate
    let pinLocation = CLLocation(latitude: draftCoord.latitude, longitude: draftCoord.longitude)

    Task { @MainActor in
      let isValid = await self.parent.viewModel.checkVideoMetadata(
        asset: asset,
        pinLocation: pinLocation
      )

      guard isValid else {
        self.parent.viewModel.showError(
          "Video must be ≤5 hours old and ≤200 ft from the pin location."
        )
        return
      }

      // Continue with the rest of the process if metadata check passes
      // Get the video URL from the result
      result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) {
        url, error in
        guard let url = url else {
          Task { @MainActor in
            self.parent.viewModel.showError("Could not load video")
          }
          return
        }

        // Check video duration (limit to 3 minutes)
        Task {
          do {
            let asset = AVAsset(url: url)
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
              print("[SimplifiedReportFlow] Video too long: \(duration.seconds) seconds")
              await MainActor.run {
                self.parent.viewModel.showError("Video must be under 3 minutes")
              }
              return
            }

            // Video is acceptable
            await MainActor.run {
              self.parent.viewModel.reportDraft.videoURL = url
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
