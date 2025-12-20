import AVFoundation
import Foundation

extension MapViewModel {
  /// Allow a witness to attach their perspective video to an existing pin.
  func uploadPerspective(for pin: Pin, videoURL: URL) async {
    // Block duplicate uploads
    guard isUploadingPerspective == false else { return }
    print("[MapViewModel] Starting perspective upload for pin \(pin.id) file \(videoURL.lastPathComponent)")

    // Validate duration before hitting the network
    let asset = AVURLAsset(url: videoURL)
    let durationSeconds: Double
    if #available(iOS 16.0, *) {
      let duration = try? await asset.load(.duration)
      durationSeconds = duration?.seconds ?? 0
    } else {
      durationSeconds = asset.duration.seconds
    }

    if durationSeconds > 180 {
      let minutes = Int(durationSeconds / 60)
      let seconds = Int(durationSeconds) % 60
      alertTitle = "Video Too Long"
      alertMessage = "This video is \(minutes):\(String(format: "%02d", seconds)) long.\n\nPerspective videos must be 3 minutes or less to keep reports concise.\n\nTip: Trim your video in the Photos app before selecting it."
      showAlert = true
      return
    }

    isUploadingPerspective = true
    // Kick progress slightly above zero so the overlay appears immediately
    perspectiveUploadProgress = 0.01

    do {
      let _ = try await WitnessEvidenceService.shared.uploadPerspectiveVideo(
        pinId: pin.id,
        ownerUserId: pin.userId,
        fileURL: videoURL,
        progress: { [weak self] percent in
          Task { @MainActor in
            self?.perspectiveUploadProgress = percent
          }
        }
      )

      #if DEBUG
      print("[MapViewModel] Perspective upload completed for pin \(pin.id)")
      #endif

      alertTitle = "Upload Success"
      alertMessage = "Your perspective video has been uploaded to this pin."
      showAlert = true
    } catch {
      print("Error uploading perspective: \(error)")
      alertTitle = "Upload Error"
      alertMessage = "Unable to upload perspective: \(error.localizedDescription)"
      showAlert = true
    }

    isUploadingPerspective = false
  }
}
