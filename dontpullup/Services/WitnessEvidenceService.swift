import AVFoundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Thread-safe flag to prevent continuation from being resumed multiple times
private final class AtomicFlag: @unchecked Sendable {
  private var _value: Bool = false
  private let lock = NSLock()
  
  /// Attempts to set the flag to true. Returns true if successful (was false), false if already set.
  func trySet() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if _value { return false }
    _value = true
    return true
  }
}

/// Handles perspective (witness) video uploads linked to an existing pin.
final class WitnessEvidenceService {
  static let shared = WitnessEvidenceService()

  private let storage = Storage.storage()
  private let db = Firestore.firestore()

  enum UploadError: Error {
    case notAuthenticated
    case downloadURLMissing
  }

  /// Upload a perspective video and attach it to a pin's subcollection.
  /// - Parameters:
  ///   - pinId: The pin receiving the contribution.
  ///   - ownerUserId: The original pin owner (stored for audit).
  ///   - fileURL: Local video URL.
  ///   - progress: Optional progress callback (0...1).
  /// - Returns: Remote download URL string.
  func uploadPerspectiveVideo(
    pinId: String,
    ownerUserId: String,
    fileURL: URL,
    progress: @escaping (Double) -> Void = { _ in }
  ) async throws -> String {
    guard let contributorId = Auth.auth().currentUser?.uid else {
      throw UploadError.notAuthenticated
    }

    print("[WitnessUpload] Starting for pin \(pinId) by user \(contributorId). Local file: \(fileURL.lastPathComponent)")

    // Enforce 3-minute limit for privacy/compliance.
    let asset = AVURLAsset(url: fileURL)
    let durationSeconds: Double
    if #available(iOS 16.0, *) {
      let duration = try await asset.load(.duration)
      durationSeconds = duration.seconds
    } else {
      // Fallback for older iOS where load(.duration) is unavailable
      durationSeconds = asset.duration.seconds
    }

    if durationSeconds > 180 {
      throw NSError(domain: "WitnessEvidenceService", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Video must be 3 minutes or less."
      ])
    }
    print("[WitnessUpload] Duration ok: \(durationSeconds)s")

    let fileId = UUID().uuidString
    // Store in /videos to align with working rules path
    let storageRef = storage.reference(withPath: "videos/\(pinId)-\(fileId).mp4")
    print("[WitnessUpload] Storage path: videos/\(pinId)-\(fileId).mp4")

    let metadata = StorageMetadata()
    metadata.contentType = "video/mp4"
    // Satisfy storage.rules for /videos: include userId metadata; add pinId/device for audit.
    let deviceId = await MainActor.run {
      UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }
    metadata.customMetadata = [
      "userId": contributorId,
      "pinId": pinId,
      "deviceID": deviceId,
    ]

    let uploadTask = storageRef.putFile(from: fileURL, metadata: metadata)

    // Observe progress
    let progressHandle = uploadTask.observe(.progress) { snapshot in
      let percent = Double(snapshot.progress?.fractionCompleted ?? 0)
      progress(percent)
      print("[WitnessUpload] Progress: \(Int(percent * 100))%")
    }

    let urlString: String = try await withCheckedThrowingContinuation { continuation in
      // Thread-safe flag to ensure continuation is only resumed once
      let hasResumed = AtomicFlag()
      var successHandle: String?
      var failureHandle: String?
      
      successHandle = uploadTask.observe(.success) { _ in
        guard hasResumed.trySet() else { return }
        
        // Remove all observers immediately
        uploadTask.removeObserver(withHandle: progressHandle)
        if let sh = successHandle { uploadTask.removeObserver(withHandle: sh) }
        if let fh = failureHandle { uploadTask.removeObserver(withHandle: fh) }
        
        storageRef.downloadURL { url, error in
          if let error = error {
            print("[WitnessUpload] downloadURL error: \(error.localizedDescription)")
            continuation.resume(throwing: error)
            return
          }
          guard let url = url else {
            print("[WitnessUpload] downloadURL missing")
            continuation.resume(throwing: UploadError.downloadURLMissing)
            return
          }
          print("[WitnessUpload] Upload success. URL: \(url.absoluteString)")
          continuation.resume(returning: url.absoluteString)
        }
      }

      failureHandle = uploadTask.observe(.failure) { snapshot in
        guard hasResumed.trySet() else { return }
        
        // Remove all observers immediately
        uploadTask.removeObserver(withHandle: progressHandle)
        if let sh = successHandle { uploadTask.removeObserver(withHandle: sh) }
        if let fh = failureHandle { uploadTask.removeObserver(withHandle: fh) }
        
        if let error = snapshot.error {
          print("[WitnessUpload] Upload failed: \(error.localizedDescription)")
          continuation.resume(throwing: error)
        } else {
          print("[WitnessUpload] Upload failed with unknown error")
          continuation.resume(throwing: UploadError.downloadURLMissing)
        }
      }
    }

    // Persist contribution in top-level witness-evidence (matches Firestore rules)
    let doc = db.collection("witnessEvidence").document(fileId)
    print("[WitnessUpload] Writing Firestore doc witnessEvidence/\(fileId)")
    try await doc.setData([
      "id": fileId,
      "pinId": pinId,
      "videoURL": urlString,
      "ownerUserId": ownerUserId,
      "contributorUserId": contributorId,
      "userId": contributorId,  // required by rules: must equal request.auth.uid
      "submittedAt": Timestamp()
    ])
    print("[WitnessUpload] Firestore write completed for \(fileId)")

    return urlString
  }
}
