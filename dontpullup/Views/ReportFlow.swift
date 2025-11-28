@preconcurrency import AVKit
import Combine
import FirebaseAuth
import FirebaseStorage
import MapKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Minimal sheet that lets the user decide how to attach the required video evidence.
struct ReportFlowView: View {
  @ObservedObject var viewModel: MapViewModel
  @State private var showingVideoPicker = false
  @State private var showingCamera = false
  @State private var isPreparingVideo = false

  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 20) {
        Button {
          if viewModel.authState.isAnonymous {
            viewModel.showError("Guests cannot record videos.")
          } else {
            showingCamera = true
          }
        } label: {
          VStack(spacing: 8) {
            Image(systemName: "video.fill")
              .font(.system(size: 40))
            Text("Record")
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.red.opacity(0.2))
          .cornerRadius(12)
        }

        Button {
          if viewModel.authState.isAnonymous {
            viewModel.showError("Guests cannot upload videos.")
          } else {
            showingVideoPicker = true
          }
        } label: {
          VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
              .font(.system(size: 40))
            Text("Photos")
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.blue.opacity(0.2))
          .cornerRadius(12)
        }
      }
      .padding()

      if isPreparingVideo || (viewModel.uploadProgress > 0 && viewModel.uploadProgress < 1) {
        ProgressView(value: viewModel.uploadProgress)
          .progressViewStyle(LinearProgressViewStyle())
          .padding(.horizontal)
      }

      Button("Cancel") {
        viewModel.reportStep = nil
      }
      .foregroundColor(.secondary)
      .padding(.top, 8)
    }
    .presentationDetents([.height(200)])
    .presentationBackground(.ultraThinMaterial)
    .preferredColorScheme(.dark)
    .sheet(isPresented: $showingVideoPicker) {
      VideoPicker(onVideoPicked: { handleVideoSelection($0) }, viewModel: viewModel)
    }
    .fullScreenCover(isPresented: $showingCamera) {
      VideoRecorderView(maxDuration: 180) { url in
        handleVideoSelection(url)
      }
      .ignoresSafeArea()
    }
  }

  private func handleVideoSelection(_ url: URL?) {
    guard let url = url else {
      isPreparingVideo = false
      viewModel.reportStep = nil
      return
    }

    isPreparingVideo = true
    viewModel.reportDraft.videoURL = url

    Task {
      await viewModel.upload(draft: viewModel.reportDraft)
      await MainActor.run {
        isPreparingVideo = false
        if viewModel.reportStep != nil {
          viewModel.reportStep = nil
        }
      }
    }
  }
}


/// A proper video picker implementation using PHPickerViewController
struct VideoPicker: UIViewControllerRepresentable {
  let onVideoPicked: (URL?) -> Void
  let viewModel: MapViewModel

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var config = PHPickerConfiguration()
    config.selectionLimit = 1
    config.filter = .videos

    let picker = PHPickerViewController(configuration: config)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let parent: VideoPicker

    init(_ parent: VideoPicker) {
      self.parent = parent
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      // Dismiss picker immediately
      picker.dismiss(animated: true)

      // Handle video selection
      guard let result = results.first else {
        // User canceled selection, abort the flow
        parent.onVideoPicked(nil)
        return
      }

      // Check video metadata first
      guard let assetId = result.assetIdentifier,
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
      else {
        DispatchQueue.main.async {
          self.parent.viewModel.showError("Could not load video metadata.")
        }
        return
      }

      let coord = self.parent.viewModel.reportDraft.coordinate
      let pinLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

      Task { @MainActor in
        let valid = await self.parent.viewModel.checkVideoMetadata(
          asset: asset,
          pinLocation: pinLocation
        )

        guard valid else {
          self.parent.viewModel.showError("Video must be ≤5h old and ≤200 ft away.")
          return
        }

        // Metadata OK—load file and call parent handler
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) {
          url, _ in
          if let url = url {
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
                  print("[VideoPicker] Video too long: \(duration.seconds) seconds")
                  await MainActor.run {
                    self.parent.viewModel.showError("Video must be under 3 minutes")
                    self.parent.onVideoPicked(nil)
                  }
                  return
                }

                // Video is acceptable
                await MainActor.run {
                  self.parent.onVideoPicked(url)
                }
              } catch {
                print("[VideoPicker] Error checking video duration: \(error)")
                await MainActor.run {
                  self.parent.viewModel.showError(
                    "Error processing video: \(error.localizedDescription)")
                  self.parent.onVideoPicked(nil)
                }
              }
            }
          } else {
            DispatchQueue.main.async {
              self.parent.viewModel.showError("Failed to load video file.")
              self.parent.onVideoPicked(nil)
            }
          }
        }
      }
    }
  }
}

// CameraVideoPicker has been replaced by VideoRecorderView for better camera control
// and to eliminate UIImagePickerController warnings

// MARK: - Preview
struct ReportFlowView_Previews: PreviewProvider {
  static var previews: some View {
    ReportFlowView(viewModel: MapViewModel(authState: AuthState.shared))
  }
}
