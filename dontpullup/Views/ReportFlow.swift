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
    // Use photoLibrary configuration to enable assetIdentifier access for metadata validation
    var config = PHPickerConfiguration(photoLibrary: .shared())
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
    private let tempDir = FileManager.default.temporaryDirectory

    init(_ parent: VideoPicker) {
      self.parent = parent
    }

    private func copyMovieToTemp(url: URL) throws -> URL {
      let target = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
      try FileManager.default.copyItem(at: url, to: target)
      return target
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

      // Check video metadata first (if available)
      // Note: assetIdentifier requires PHPickerConfiguration(photoLibrary:) to be non-nil
      let assetId = result.assetIdentifier
      let asset: PHAsset? = assetId.flatMap {
        PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject
      }
      
      #if DEBUG
      print("[VideoPicker] assetIdentifier: \(assetId ?? "nil"), asset: \(asset != nil ? "found" : "nil")")
      #endif

      let coord = self.parent.viewModel.reportDraft.coordinate
      let pinLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

      Task { @MainActor in
        // Only validate metadata if we have asset access; otherwise allow upload
        // (the user must still be within 200ft of the pin to drop it)
        if let asset = asset {
          let validationResult = await self.parent.viewModel.validateVideoMetadata(
            asset: asset,
            pinLocation: pinLocation
          )

          guard validationResult.isValid else {
            // Show specific error message explaining the problem and how to fix it
            self.parent.viewModel.showError(validationResult.errorMessage, title: "Video Not Accepted")
            self.parent.onVideoPicked(nil)  // Properly dismiss the flow
            return
          }
        } else {
          #if DEBUG
          print("[VideoPicker] No asset metadata available - skipping validation, proceeding with upload")
          #endif
        }

        // Metadata OK—load file and call parent handler
        #if DEBUG
        print("[VideoPicker] Loading file representation for video...")
        #endif
        
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) {
          url, error in
          if let error {
            print("[VideoPicker] loadFileRepresentation error: \(error.localizedDescription)")
            DispatchQueue.main.async {
              self.parent.viewModel.showError("Failed to load video: \(error.localizedDescription)")
              self.parent.onVideoPicked(nil)
            }
            return
          }

          // Copy into our own temp file so it survives during upload
          if let url = url {
            #if DEBUG
            print("[VideoPicker] Got video URL: \(url.lastPathComponent)")
            #endif
            let tempURL: URL
            do {
              tempURL = try self.copyMovieToTemp(url: url)
              #if DEBUG
              print("[VideoPicker] Temp copy: \(tempURL.lastPathComponent)")
              #endif
            } catch {
              DispatchQueue.main.async {
                self.parent.viewModel.showError("Failed to prepare video: \(error.localizedDescription)")
                self.parent.onVideoPicked(nil)
              }
              return
            }

            // Check video duration (limit to 3 minutes)
            Task {
              do {
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
                  print("[VideoPicker] Video too long: \(duration.seconds) seconds")
                  await MainActor.run {
                    self.parent.viewModel.showError(
                      "This video is \(minutes):\(String(format: "%02d", seconds)) long.\n\nVideos must be 3 minutes or less to keep reports concise and ensure quick uploads.\n\nTip: Trim your video in the Photos app before selecting it, or record a shorter clip.",
                      title: "Video Too Long"
                    )
                    self.parent.onVideoPicked(nil)
                  }
                  return
                }

                // Video is acceptable
                await MainActor.run {
                  self.parent.onVideoPicked(tempURL)
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
