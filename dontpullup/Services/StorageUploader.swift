@preconcurrency import AVFoundation
import Combine
import CoreLocation
import FirebaseAuth
import FirebaseStorage
import Foundation
import Network
import SwiftUI
import UIKit

/// Utility class for handling Firebase Storage uploads
enum StorageUploader {

  // Network monitor for adaptive quality
  private static let networkMonitor = NWPathMonitor()
  private static var isExpensiveConnection = false
  private static var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  // Actor to isolate non-Sendable AVAssetExportSession
  private actor ExportSessionActor {
      let session: AVAssetExportSession
      
      init(session: AVAssetExportSession) {
          self.session = session
      }
      
      func getError() -> Error? {
          return session.error
      }
      
      func export() async {
          await withCheckedContinuation { continuation in
              session.exportAsynchronously {
                  continuation.resume()
              }
          }
      }
  }

  // Initialize network monitoring
  static func setupNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { path in
      isExpensiveConnection = path.isExpensive
      print(
        "[StorageUploader] Network connection type: \(isExpensiveConnection ? "Cellular/Expensive" : "WiFi/Cheap")"
      )
    }
    networkMonitor.start(queue: .global(qos: .background))
  }

  /// Compresses a video to reduce file size before uploading
  /// - Parameter inputURL: Local URL of the video to compress
  /// - Returns: URL of the compressed video
  /// - Throws: Error if compression fails
  static func compressVideo(inputURL: URL) async throws -> URL {
    print("[StorageUploader] Starting video compression")

    // Get original file size
    let originalFileAttributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
    let originalFileSize = originalFileAttributes[.size] as? Int64 ?? 0
    let sizeString = ByteCountFormatter.string(fromByteCount: originalFileSize, countStyle: .file)
    print("[StorageUploader] Original video size: \(sizeString)")

    // Skip compression if video is already small (under 3MB) - saves time!
    if originalFileSize < 3 * 1024 * 1024 {
      print("[StorageUploader] Video already small enough, skipping compression for faster upload")
      return inputURL
    }

    let asset = AVAsset(url: inputURL)

    // Use aggressive compression for fast uploads - 50%+ faster
    // Use low quality preset for all connections
    let preset = AVAssetExportPreset640x480  // Low quality for fast uploads

    // Get video duration using modern API
    var videoDuration: CMTime = .zero

    if #available(iOS 16.0, *) {
      // Use modern async/await API in iOS 16+
      videoDuration = try await asset.load(.duration)
    } else {
      // Use older API for iOS 15 and below
      let durationKey = "duration"
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        asset.loadValuesAsynchronously(forKeys: [durationKey]) {
          var error: NSError?
          let status = asset.statusOfValue(forKey: durationKey, error: &error)

          if status == .loaded {
            videoDuration = asset.duration
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

    // Check if video is too long (30 seconds max)
    let maxDuration: Double = 30.0
    if videoDuration.seconds > maxDuration {
      print(
        "[StorageUploader] Video too long: \(videoDuration.seconds) seconds, max is \(maxDuration)")
      throw NSError(
        domain: "VideoCompression",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Video is too long. Please record a video that is \(Int(maxDuration)) seconds or less."
        ])
    }

    // Create temp output URL
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "compressed_\(UUID().uuidString).mp4")

    // Configure exporter
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw NSError(
        domain: "VideoCompression",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Could not create export session."])
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = AVFileType.mp4
    exportSession.shouldOptimizeForNetworkUse = true

    // Aggressive optimization: Reduce frame rate to 10fps and add bitrate limits
    let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
    videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 10)  // Reduced from 15fps to 10fps
    
    // Add scale transform to limit resolution to 640x480 max
    let videoTrack: AVAssetTrack?
    if #available(iOS 16.0, *) {
      let tracks = try await asset.loadTracks(withMediaType: .video)
      videoTrack = tracks.first
    } else {
      videoTrack = asset.tracks(withMediaType: .video).first
    }

    if let track = videoTrack {
      let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRangeMake(start: .zero, duration: videoDuration)
      instruction.layerInstructions = [transformer]
      videoComposition.instructions = [instruction]
    }
    
    exportSession.videoComposition = videoComposition
    
    // Set file length limit for faster uploads (5MB target)
    exportSession.fileLengthLimit = 5 * 1024 * 1024

    // Export the video using a helper function to avoid Sendable warnings
    return try await performExport(exportSession: exportSession, originalFileSize: originalFileSize)
  }

  // Helper class to handle export session without capturing it in closures
  private class ExportSessionHandler {
    private var exportSession: AVAssetExportSession
    private var originalFileSize: Int64

    init(exportSession: AVAssetExportSession, originalFileSize: Int64) {
      self.exportSession = exportSession
      self.originalFileSize = originalFileSize
    }

    func export() async throws -> URL {
      return try await withCheckedThrowingContinuation { continuation in
        // Check if output URL exists without assigning it
        guard self.exportSession.outputURL != nil else {
          continuation.resume(
            throwing: NSError(
              domain: "VideoCompression",
              code: 2,
              userInfo: [NSLocalizedDescriptionKey: "Export session has no output URL."]
            ))
          return
        }

        // Store the needed properties before starting the export
        let outputURL = self.exportSession.outputURL!  // Safe to force unwrap after guard
        let originalSize = self.originalFileSize

        // Create an actor to isolate the export session
        let sessionActor = ExportSessionActor(session: self.exportSession)
        
        // Start a task to handle the export
        Task {
            // Wait for export to complete
            await sessionActor.export()
            
            // Check for errors after export is complete
            if let error = await sessionActor.getError() {
                continuation.resume(throwing: error)
                return
            }
            
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                continuation.resume(
                    throwing: NSError(
                        domain: "VideoCompression",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Export completed but file doesn't exist."
                        ]
                    ))
                return
            }
            
            // Get compressed file size
            do {
                let compressedAttributes = try FileManager.default.attributesOfItem(
                    atPath: outputURL.path)
                let compressedSize = compressedAttributes[.size] as? Int64 ?? 0
                let compressedSizeString = ByteCountFormatter.string(
                    fromByteCount: compressedSize, countStyle: .file)
                let compressionRatio = Double(originalSize) / Double(max(1, compressedSize))
                print("[StorageUploader] Compressed video size: \(compressedSizeString)")
                print(
                    "[StorageUploader] Compression ratio: \(String(format: "%.1fx", compressionRatio))")
            } catch {
                print("[StorageUploader] Could not get compressed file size: \(error)")
            }
            
            continuation.resume(returning: outputURL)
        }
      }
    }
  }

  // Helper function to perform the export without capturing exportSession in a @Sendable closure
  private static func performExport(exportSession: AVAssetExportSession, originalFileSize: Int64)
    async throws -> URL
  {
    // Use the handler class to avoid capturing exportSession in closures
    let handler = ExportSessionHandler(
      exportSession: exportSession, originalFileSize: originalFileSize)
    return try await handler.export()
  }

  /// Uploads a video to Firebase Storage if a local URL is provided
  /// - Parameters:
  ///   - pinId: The ID of the pin associated with this video
  ///   - localURL: Optional local URL of the video to upload
  ///   - useChunks: Whether to use chunked uploads for larger files
  ///   - convertToGif: Whether to convert video to GIF for even faster uploads
  /// - Returns: Remote URL as String (empty if no local URL was provided)
  /// - Throws: Error if upload fails
  static func uploadIfNeeded(
    pinId: String, localURL: URL?, useChunks: Bool = true, convertToGif: Bool = false
  ) async throws -> String {
    // Start background task to allow upload to complete if app goes to background
    let taskID = await UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

    // If no local URL provided, return empty string (no video)
    guard let videoURL = localURL else {
      // End background task if no upload needed
      if taskID != .invalid {
        await UIApplication.shared.endBackgroundTask(taskID)
      }
      return ""
    }

    print("[StorageUploader] Starting upload process for pin: \(pinId)")

    // Compress the video before uploading
    let compressedURL = try await compressVideo(inputURL: videoURL)

    // If requested, convert to GIF instead for even smaller file size
    if convertToGif {
      let gifURL = try await convertVideoToGIF(videoURL: compressedURL)

      // Upload the GIF
      let storage = Storage.storage()
      storage.maxUploadRetryTime = 10
      storage.maxOperationRetryTime = 5
      storage.maxDownloadRetryTime = 5

      let timestamp = Int(Date().timeIntervalSince1970)
      let storageRef = storage.reference().child("g/\(timestamp)-\(pinId.prefix(8)).gif")

      // Create metadata
      let metadata = StorageMetadata()
      metadata.contentType = "image/gif"
      metadata.cacheControl = "public, max-age=31536000"

      if let currentUserId = Auth.auth().currentUser?.uid {
        metadata.customMetadata = [
          "userId": currentUserId,
          "timestamp": String(Date().timeIntervalSince1970),
        ]
      }

      // Upload GIF
      let uploadTask = storageRef.putFile(from: gifURL, metadata: metadata)

      // Wait for upload to complete
      let result = try await withCheckedThrowingContinuation { continuation in
        // Set up progress monitoring
        let progressHandle = uploadTask.observe(.progress) { snapshot in
          if let progress = snapshot.progress {
            let percentComplete =
              Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100
            print(
              "[StorageUploader] GIF Upload progress: \(String(format: "%.1f", percentComplete))%")

            // Post notification for UI updates
            NotificationCenter.default.post(
              name: Notification.Name("UploadProgressUpdated"),
              object: nil,
              userInfo: ["progress": percentComplete]
            )
          }
        }

        // Create a task to handle the upload completion
        Task {
          do {
            // Wait for the upload to complete using a continuation-based approach
            let snapshot = await withCheckedContinuation {
              (continuation: CheckedContinuation<StorageTaskSnapshot, Never>) in
              uploadTask.observe(.success) { snapshot in
                continuation.resume(returning: snapshot)
              }

              uploadTask.observe(.failure) { snapshot in
                continuation.resume(returning: snapshot)
              }
            }

            // Check for errors
            if let error = snapshot.error {
              throw error
            }

            // Remove the progress observer
            uploadTask.removeObserver(withHandle: progressHandle)

            // Log upload time
            print("[StorageUploader] GIF Upload completed")

            // Clean up temporary files
            try? FileManager.default.removeItem(at: compressedURL)
            try? FileManager.default.removeItem(at: gifURL)

            // Get the download URL
            let downloadURL = try await storageRef.downloadURL()
            print("[StorageUploader] Got GIF download URL: \(downloadURL.absoluteString)")

            // End background task
            if taskID != .invalid {
              await UIApplication.shared.endBackgroundTask(taskID)
            }

            continuation.resume(returning: downloadURL.absoluteString)
          } catch {
            // Remove the progress observer
            uploadTask.removeObserver(withHandle: progressHandle)

            // Clean up temporary files
            try? FileManager.default.removeItem(at: compressedURL)
            try? FileManager.default.removeItem(at: gifURL)

            print("[StorageUploader] Upload failed with error: \(error)")

            // End background task in case of error
            if taskID != .invalid {
              await UIApplication.shared.endBackgroundTask(taskID)
            }

            continuation.resume(throwing: error)
          }
        }
      }

      return result
    }

    // Check file size to determine if we should use chunked upload
    let attributes = try FileManager.default.attributesOfItem(atPath: compressedURL.path)
    let fileSize = attributes[.size] as? Int64 ?? 0

    // Disable chunked upload for faster simple uploads - direct upload is faster
    // Use chunked upload only for files larger than 10MB (increased from 5MB)
    if useChunks && fileSize > 10 * 1024 * 1024 {
      let downloadURL = try await uploadInChunks(videoURL: compressedURL, pinId: pinId)

      // Clean up temporary compressed file
      try? FileManager.default.removeItem(at: compressedURL)

      // End background task
      if taskID != .invalid {
        await UIApplication.shared.endBackgroundTask(taskID)
      }

      return downloadURL
    }

    // Reference to Firebase Storage
    let storage = Storage.storage()
    storage.maxUploadRetryTime = 10  // Reduce retry time from default 600 seconds to 10
    storage.maxOperationRetryTime = 5  // Reduce operation retry time
    storage.maxDownloadRetryTime = 5  // Reduce download retry time

    // Generate a smaller filename to reduce overhead
    let timestamp = Int(Date().timeIntervalSince1970)
    let storageRef = storage.reference().child("v/\(timestamp)-\(pinId.prefix(8)).mp4")

    // Create metadata with required fields from Storage rules
    let metadata = StorageMetadata()
    metadata.contentType = "video/mp4"

    // Set cacheControl for faster delivery
    metadata.cacheControl = "public, max-age=31536000"

    // Add userId to metadata as required by Storage rules
    if let currentUserId = Auth.auth().currentUser?.uid {
      metadata.customMetadata = [
        "userId": currentUserId,
        "timestamp": String(Date().timeIntervalSince1970),
      ]
    }

    let uploadStart = Date()
    print("[StorageUploader] Upload started at: \(uploadStart)")

    // Create a new approach that avoids circular references
    return try await withCheckedThrowingContinuation { continuation in
      // Start the upload task
      let uploadTask = storageRef.putFile(from: compressedURL, metadata: metadata)

      // Enable resumable uploads
      uploadTask.enqueue()

      // Set up progress monitoring without circular references
      let progressHandle = uploadTask.observe(.progress) { snapshot in
        if let progress = snapshot.progress {
          let percentComplete =
            Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100
          print("[StorageUploader] Upload progress: \(String(format: "%.1f", percentComplete))%")

          // Post notification for UI updates
          NotificationCenter.default.post(
            name: Notification.Name("UploadProgressUpdated"),
            object: nil,
            userInfo: ["progress": percentComplete]
          )
        }
      }

      // Create a task to handle the upload completion
      Task {
        do {
          // Wait for the upload to complete using a continuation-based approach
          let snapshot = await withCheckedContinuation {
            (continuation: CheckedContinuation<StorageTaskSnapshot, Never>) in
            uploadTask.observe(.success) { snapshot in
              continuation.resume(returning: snapshot)
            }

            uploadTask.observe(.failure) { snapshot in
              continuation.resume(returning: snapshot)
            }
          }

          // Check for errors
          if let error = snapshot.error {
            throw error
          }

          // Remove the progress observer
          uploadTask.removeObserver(withHandle: progressHandle)

          // Log upload time
          let uploadEnd = Date()
          let uploadTime = uploadEnd.timeIntervalSince(uploadStart)
          print(
            "[StorageUploader] Upload completed in \(String(format: "%.2f", uploadTime)) seconds")

          // Clean up temporary compressed file
          try? FileManager.default.removeItem(at: compressedURL)

          // Get the download URL
          let downloadURL = try await storageRef.downloadURL()
          print("[StorageUploader] Got download URL: \(downloadURL.absoluteString)")

          // End background task
          if taskID != .invalid {
            await UIApplication.shared.endBackgroundTask(taskID)
          }

          continuation.resume(returning: downloadURL.absoluteString)
        } catch {
          // Remove the progress observer
          uploadTask.removeObserver(withHandle: progressHandle)

          // Clean up temporary compressed file
          try? FileManager.default.removeItem(at: compressedURL)

          print("[StorageUploader] Upload failed with error: \(error)")

          // End background task in case of error
          if taskID != .invalid {
            await UIApplication.shared.endBackgroundTask(taskID)
          }

          continuation.resume(throwing: error)
        }
    }
    }

  }

  /// Creates an instant pin with video upload
  /// - Parameters:
  ///   - pinId: The ID of the pin
  ///   - coordinate: The coordinate of the pin
  ///   - incidentType: The type of incident
  ///   - localURL: Local URL of the video to upload
  /// - Returns: True if successful
  static func createInstantPin(
    pinId: String,
    coordinate: CLLocationCoordinate2D,
    incidentType: IncidentType,
    localURL: URL?
  ) async throws -> Bool {
    // Upload the video if provided
    if let videoURL = localURL {
      _ = try await uploadIfNeeded(pinId: pinId, localURL: videoURL)
    }
    return true
  }

  /// Uploads a video in chunks to improve reliability for large files
  /// - Parameters:
  ///   - videoURL: URL of the compressed video to upload
  ///   - pinId: ID of the pin associated with this video
  ///   - chunkSize: Size of each chunk in bytes (default: 1MB)
  /// - Returns: Download URL of the uploaded video
  static func uploadInChunks(videoURL: URL, pinId: String, chunkSize: Int = 1024 * 1024)
    async throws -> String
  {
    print("[StorageUploader] Starting chunked upload for pin: \(pinId)")

    // Get file data
    let data = try Data(contentsOf: videoURL)
    let totalSize = data.count
    let chunksCount = Int(ceil(Double(totalSize) / Double(chunkSize)))

    print("[StorageUploader] File size: \(totalSize) bytes, will upload in \(chunksCount) chunks")

    // Generate a unique upload ID
    let uploadId = UUID().uuidString
    let timestamp = Int(Date().timeIntervalSince1970)
    let finalPath = "v/\(timestamp)-\(pinId.prefix(8)).mp4"

    // Upload each chunk
    var uploadedChunks = 0

    for chunkIndex in 0..<chunksCount {
      let start = chunkIndex * chunkSize
      let end = min(start + chunkSize, totalSize)
      let chunkData = data.subdata(in: start..<end)

      // Create a reference for this chunk
      let chunkRef = Storage.storage().reference().child("chunks/\(uploadId)/chunk\(chunkIndex)")

      // Upload the chunk
      _ = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"

        let uploadTask = chunkRef.putData(chunkData, metadata: metadata)

        uploadTask.observe(.success) { _ in
          uploadedChunks += 1
          let progress = Double(uploadedChunks) / Double(chunksCount) * 100
          print(
            "[StorageUploader] Chunk \(chunkIndex+1)/\(chunksCount) uploaded (\(Int(progress))%)")

          // Post notification for UI updates
          NotificationCenter.default.post(
            name: Notification.Name("UploadProgressUpdated"),
            object: nil,
            userInfo: ["progress": progress]
          )

          continuation.resume()
        }

        uploadTask.observe(.failure) { snapshot in
          if let error = snapshot.error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(
              throwing: NSError(
                domain: "StorageUploader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown error uploading chunk"]))
          }
        }
      }
    }

    // All chunks uploaded, now trigger server-side composition (in a real app)
    // For this implementation, we'll just upload the full file to the final destination
    // as a demonstration
    let finalRef = Storage.storage().reference().child(finalPath)

    // Add metadata
    let metadata = StorageMetadata()
    metadata.contentType = "video/mp4"
    metadata.cacheControl = "public, max-age=31536000"

    if let currentUserId = Auth.auth().currentUser?.uid {
      metadata.customMetadata = [
        "userId": currentUserId,
        "timestamp": String(Date().timeIntervalSince1970),
      ]
    }

    // Upload the final file using withCheckedThrowingContinuation instead of try await
    let downloadURL = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<URL, Error>) in
      let uploadTask = finalRef.putData(data, metadata: metadata)

      uploadTask.observe(.success) { _ in
        // Get download URL after successful upload
        finalRef.downloadURL { url, error in
          if let error = error {
            continuation.resume(throwing: error)
          } else if let url = url {
            continuation.resume(returning: url)
          } else {
            continuation.resume(
              throwing: NSError(
                domain: "StorageUploader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]
              ))
          }
        }
      }

      uploadTask.observe(.failure) { snapshot in
        if let error = snapshot.error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(
            throwing: NSError(
              domain: "StorageUploader",
              code: -1,
              userInfo: [NSLocalizedDescriptionKey: "Unknown error uploading final file"]
            ))
        }
      }
    }

    print("[StorageUploader] Chunked upload complete: \(downloadURL.absoluteString)")

    // Clean up chunks (would be handled server-side in production)
    // This is simplified for demonstration

    return downloadURL.absoluteString
  }

  /// Converts a video to an animated GIF for smaller file size
  /// - Parameter videoURL: URL of the video to convert
  /// - Returns: URL of the generated GIF
  static func convertVideoToGIF(videoURL: URL) async throws -> URL {
    print("[StorageUploader] Starting GIF conversion")

    let asset = AVAsset(url: videoURL)

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

    // Limit GIF to 5 seconds
    let gifDuration = min(5.0, duration.seconds)

    // Extract frames (simplified implementation)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 240, height: 180)  // Reduced from 320x240 for faster upload

    // Lower frame rate for smaller GIF (8 frames per second, reduced from 10)
    let frameRate: Double = 8
    let frameCount = Int(gifDuration * frameRate)
    var images: [UIImage] = []

    for frameIndex in 0..<frameCount {
      let time = CMTime(seconds: Double(frameIndex) / frameRate, preferredTimescale: 600)

      // Extract the image at the specified time
      let cgImage: CGImage

      if #available(iOS 16.0, *) {
        // Use modern async API for iOS 16+
        cgImage = try await generator.image(at: time).image
      } else {
        // Use older API for iOS 15 and below
        cgImage = try await withCheckedThrowingContinuation { continuation in
          generator.generateCGImageAsynchronously(for: time) { image, actualTime, error in
            if let error = error {
              continuation.resume(throwing: error)
              return
            }

            guard let image = image else {
              continuation.resume(
                throwing: NSError(
                  domain: "GIFConversion",
                  code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Failed to generate image"]
                ))
              return
            }

            continuation.resume(returning: image)
          }
        }
      }

      // Add the image to our array
      images.append(UIImage(cgImage: cgImage))
    }

    // Create GIF
    let gifURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).gif")

    // Use a GIF creation library or implement your own GIF creation here
    // For simplicity, we'll just create a basic animated GIF
    try createGIF(from: images, fileURL: gifURL, delay: 1.0 / frameRate)

    return gifURL
  }

  static func uploadVideoWithProgress(
    videoURL: URL, pinID: String, incidentType: String
  ) async throws -> URL {
    print("[StorageUploader] Starting video upload process")

    // Start background task to allow upload to continue when app is in background
    let taskID = await UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

    do {
      // First compress the video to reduce upload size and time
      let compressedURL = try await compressVideo(inputURL: videoURL)

      // Attempt upload with the compressed video
      let downloadURL = try await performUpload(
        fileURL: compressedURL, pinID: pinID, incidentType: incidentType)

      // End background task when upload is complete
      await UIApplication.shared.endBackgroundTask(taskID)

      return downloadURL
    } catch {
      // End background task if there's an error
      await UIApplication.shared.endBackgroundTask(taskID)
      throw error
    }
  }

  /// Helper function to create a GIF from an array of UIImages
  /// - Parameters:
  ///   - images: Array of UIImages to include in the GIF
  ///   - fileURL: Destination URL for the GIF file
  ///   - delay: Delay between frames in seconds
  private static func createGIF(from images: [UIImage], fileURL: URL, delay: TimeInterval) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        fileURL as CFURL, "com.compuserve.gif" as CFString, images.count, nil
      )
    else {
      throw NSError(
        domain: "GIFCreation",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImageDestination"]
      )
    }

    // Set GIF properties for looping
    let gifProperties =
      [
        kCGImagePropertyGIFDictionary as String: [
          kCGImagePropertyGIFLoopCount as String: 0  // Loop forever
        ]
      ] as CFDictionary

    CGImageDestinationSetProperties(destination, gifProperties)

    // Add each frame with delay
    let frameProperties =
      [
        kCGImagePropertyGIFDictionary as String: [
          kCGImagePropertyGIFDelayTime as String: delay
        ]
      ] as CFDictionary

    for image in images {
      if let cgImage = image.cgImage {
        CGImageDestinationAddImage(destination, cgImage, frameProperties)
      }
    }

    // Finalize the GIF
    if !CGImageDestinationFinalize(destination) {
      throw NSError(
        domain: "GIFCreation",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF"]
      )
    }

    print("[StorageUploader] GIF created successfully at: \(fileURL.path)")
  }

  // Add the performUpload method
  private static func performUpload(fileURL: URL, pinID: String, incidentType: String) async throws
    -> URL
  {
    print("[StorageUploader] Starting upload to Firebase Storage")

    let storageRef = Storage.storage().reference()
    let videoRef = storageRef.child("videos/\(pinID)/\(UUID().uuidString).mp4")

    // Set metadata
    let metadata = StorageMetadata()
    metadata.contentType = "video/mp4"
    metadata.customMetadata = [
      "pinID": pinID,
      "incidentType": incidentType,
      "uploadDate": ISO8601DateFormatter().string(from: Date()),
      "compressed": "true",
    ]

    // Upload the file
    let uploadTask = videoRef.putFile(from: fileURL, metadata: metadata)

    // Return a URL when complete
    return try await withCheckedThrowingContinuation { continuation in
      uploadTask.observe(.success) { snapshot in
        // Get download URL
        videoRef.downloadURL { url, error in
          if let error = error {
            continuation.resume(throwing: error)
            return
          }

          guard let downloadURL = url else {
            continuation.resume(
              throwing: NSError(
                domain: "StorageUploader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]
              ))
            return
          }

          print("[StorageUploader] Upload successful: \(downloadURL)")
          continuation.resume(returning: downloadURL)
        }
      }

      uploadTask.observe(.failure) { snapshot in
        if let error = snapshot.error {
          print("[StorageUploader] Upload failed: \(error)")
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
