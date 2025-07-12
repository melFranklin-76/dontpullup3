import Foundation
import AVFoundation
import UIKit

/// Manages video operations including compression, caching, and memory optimization
class VideoManager: ObservableObject {
    
    // MARK: - Properties
    static let shared = VideoManager()
    
    private var videoCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        cache.countLimit = 10 // Max 10 videos in cache
        return cache
    }()
    
    private let compressionQueue = DispatchQueue(label: "com.dontpullup.video.compression", qos: .userInitiated)
    
    // MARK: - Initialization
    private init() {
        setupMemoryWarningObserver()
    }
    
    // MARK: - Video Compression
    
    /// Compresses a video to optimize upload size and quality
    /// - Parameters:
    ///   - sourceURL: URL of the original video
    ///   - targetSizeMB: Target size in MB (default: 5MB)
    /// - Returns: URL of the compressed video
    func compressVideo(_ sourceURL: URL, targetSizeMB: Double = 5.0) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            compressionQueue.async {
                let asset = AVAsset(url: sourceURL)
                
                // Get video duration
                let duration = asset.duration.seconds
                
                // Calculate target bitrate based on desired file size
                let targetBitrate = (targetSizeMB * 8 * 1024 * 1024) / duration // bits per second
                
                // Create output URL
                let outputURL = self.createTempVideoURL()
                
                // Create export session
                guard let exportSession = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetMediumQuality
                ) else {
                    continuation.resume(throwing: VideoError.compressionFailed)
                    return
                }
                
                // Configure export session
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mp4
                exportSession.shouldOptimizeForNetworkUse = true
                
                // Apply video compression settings
                if let videoComposition = self.createVideoComposition(for: asset, targetBitrate: targetBitrate) {
                    exportSession.videoComposition = videoComposition
                }
                
                // Start export
                exportSession.exportAsynchronously {
                    switch exportSession.status {
                    case .completed:
                        print("[VideoManager] Video compression completed successfully")
                        continuation.resume(returning: outputURL)
                    case .failed:
                        let error = exportSession.error ?? VideoError.compressionFailed
                        print("[VideoManager] Video compression failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    case .cancelled:
                        print("[VideoManager] Video compression cancelled")
                        continuation.resume(throwing: VideoError.compressionCancelled)
                    default:
                        continuation.resume(throwing: VideoError.compressionFailed)
                    }
                }
            }
        }
    }
    
    // MARK: - Video Caching
    
    /// Caches video data for quick access
    /// - Parameters:
    ///   - videoURL: URL of the video to cache
    ///   - key: Cache key for the video
    func cacheVideo(from videoURL: URL, key: String) async throws {
        do {
            let data = try Data(contentsOf: videoURL)
            videoCache.setObject(data as NSData, forKey: key as NSString)
            print("[VideoManager] Cached video data for key: \(key)")
        } catch {
            print("[VideoManager] Error caching video: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Retrieves cached video data
    /// - Parameter key: Cache key for the video
    /// - Returns: Video data if cached, nil otherwise
    func getCachedVideo(for key: String) -> Data? {
        return videoCache.object(forKey: key as NSString) as Data?
    }
    
    /// Clears all cached videos
    func clearCache() {
        videoCache.removeAllObjects()
        print("[VideoManager] Video cache cleared")
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        print("[VideoManager] Memory warning received, clearing cache")
        clearCache()
    }
    
    // MARK: - Helper Methods
    
    private func createTempVideoURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "compressed_video_\(UUID().uuidString).mp4"
        return tempDir.appendingPathComponent(fileName)
    }
    
    private func createVideoComposition(for asset: AVAsset, targetBitrate: Double) -> AVVideoComposition? {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return nil }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
        videoComposition.renderSize = CGSize(width: 1280, height: 720) // 720p
        
        // Create video composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        // Create layer instruction
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // Apply transform to maintain aspect ratio
        let transform = videoTrack.preferredTransform
        let videoSize = videoTrack.naturalSize.applying(transform)
        
        let scaleX = videoComposition.renderSize.width / abs(videoSize.width)
        let scaleY = videoComposition.renderSize.height / abs(videoSize.height)
        let scale = min(scaleX, scaleY)
        
        let scaledTransform = transform.scaledBy(x: scale, y: scale)
        layerInstruction.setTransform(scaledTransform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        return videoComposition
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Error Types

enum VideoError: Error {
    case compressionFailed
    case compressionCancelled
    case invalidURL
    case cacheError
    
    var localizedDescription: String {
        switch self {
        case .compressionFailed:
            return "Video compression failed"
        case .compressionCancelled:
            return "Video compression was cancelled"
        case .invalidURL:
            return "Invalid video URL"
        case .cacheError:
            return "Video cache error"
        }
    }
}

// MARK: - Video Compression Extensions

extension VideoManager {
    
    /// Gets estimated file size for a video
    /// - Parameter url: Video URL
    /// - Returns: File size in MB
    func getVideoSize(_ url: URL) -> Double {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            return Double(fileSize) / (1024 * 1024) // Convert to MB
        } catch {
            print("[VideoManager] Error getting video size: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Checks if video needs compression based on size
    /// - Parameter url: Video URL
    /// - Returns: True if video should be compressed
    func shouldCompressVideo(_ url: URL) -> Bool {
        let maxSizeKB = 10.0 // 10MB threshold
        return getVideoSize(url) > maxSizeKB
    }
    
    /// Compresses video only if needed
    /// - Parameter url: Video URL
    /// - Returns: Compressed video URL (original if no compression needed)
    func compressVideoIfNeeded(_ url: URL) async throws -> URL {
        if shouldCompressVideo(url) {
            print("[VideoManager] Video size exceeds threshold, compressing...")
            return try await compressVideo(url)
        } else {
            print("[VideoManager] Video size is acceptable, skipping compression")
            return url
        }
    }
}