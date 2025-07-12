import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

/// Optimizes Firebase operations with batching, caching, and connection management
class FirebaseOptimizer: ObservableObject {
    
    // MARK: - Properties
    static let shared = FirebaseOptimizer()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    // Batching
    private let batchSize = 10
    private var pendingWrites: [String: [String: Any]] = [:]
    private var batchTimer: Timer?
    private let batchDelay: TimeInterval = 2.0 // Batch operations within 2 seconds
    
    // Caching
    private var pinCache: [String: Pin] = [:]
    private var lastPinFetchTime: Date = Date.distantPast
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    // Connection management
    private var activeListeners: [ListenerRegistration] = []
    private var isOffline = false
    
    // MARK: - Initialization
    
    private init() {
        setupFirestore()
        setupNetworkMonitoring()
    }
    
    private func setupFirestore() {
        // Enable offline persistence for better performance
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        db.settings = settings
        
        // Enable network usage optimization
        db.disableNetwork { error in
            if let error = error {
                print("[FirebaseOptimizer] Error disabling network: \(error)")
            } else {
                print("[FirebaseOptimizer] Network disabled for optimization")
                self.db.enableNetwork { error in
                    if let error = error {
                        print("[FirebaseOptimizer] Error re-enabling network: \(error)")
                    } else {
                        print("[FirebaseOptimizer] Network re-enabled")
                    }
                }
            }
        }
    }
    
    private func setupNetworkMonitoring() {
        // Monitor network connectivity
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkChange),
            name: .networkStatusChanged,
            object: nil
        )
    }
    
    // MARK: - Pin Operations (Batched)
    
    /// Adds a pin to the batch for later writing
    /// - Parameters:
    ///   - pin: Pin to add
    ///   - completion: Completion handler
    func batchAddPin(_ pin: Pin, completion: @escaping (Error?) -> Void = { _ in }) {
        let pinData: [String: Any] = [
            "id": pin.id,
            "latitude": pin.coordinate.latitude,
            "longitude": pin.coordinate.longitude,
            "type": pin.incidentType.firestoreType,
            "videoURL": pin.videoURL,
            "userId": pin.userId,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        pendingWrites[pin.id] = pinData
        
        // Update local cache immediately for optimistic updates
        pinCache[pin.id] = pin
        
        // Schedule batch write
        scheduleBatchWrite()
        
        print("[FirebaseOptimizer] Pin added to batch: \(pin.id)")
        completion(nil)
    }
    
    /// Deletes a pin with batching
    /// - Parameters:
    ///   - pinId: ID of pin to delete
    ///   - completion: Completion handler
    func batchDeletePin(_ pinId: String, completion: @escaping (Error?) -> Void = { _ in }) {
        // Mark for deletion in batch
        pendingWrites[pinId] = [:] // Empty dict indicates deletion
        
        // Remove from local cache immediately
        pinCache.removeValue(forKey: pinId)
        
        scheduleBatchWrite()
        
        print("[FirebaseOptimizer] Pin marked for deletion in batch: \(pinId)")
        completion(nil)
    }
    
    // MARK: - Batch Processing
    
    private func scheduleBatchWrite() {
        // Cancel existing timer
        batchTimer?.invalidate()
        
        // Schedule new batch write
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchDelay, repeats: false) { _ in
            Task {
                await self.executeBatchWrite()
            }
        }
    }
    
    private func executeBatchWrite() async {
        guard !pendingWrites.isEmpty else { return }
        
        let batch = db.batch()
        let writes = pendingWrites
        pendingWrites.removeAll()
        
        print("[FirebaseOptimizer] Executing batch write with \(writes.count) operations")
        
        for (pinId, data) in writes {
            let docRef = db.collection("pins").document(pinId)
            
            if data.isEmpty {
                // Deletion
                batch.deleteDocument(docRef)
            } else {
                // Addition/Update
                batch.setData(data, forDocument: docRef)
            }
        }
        
        do {
            try await batch.commit()
            print("[FirebaseOptimizer] Batch write completed successfully")
        } catch {
            print("[FirebaseOptimizer] Batch write failed: \(error.localizedDescription)")
            
            // Re-add failed operations to pending writes
            for (pinId, data) in writes {
                pendingWrites[pinId] = data
            }
            
            // Retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.scheduleBatchWrite()
            }
        }
    }
    
    // MARK: - Pin Fetching (Cached)
    
    /// Fetches pins with caching support
    /// - Parameter completion: Completion handler with pins
    func fetchPins(completion: @escaping ([Pin]) -> Void) {
        // Check cache first
        let now = Date()
        if now.timeIntervalSince(lastPinFetchTime) < cacheTimeout && !pinCache.isEmpty {
            print("[FirebaseOptimizer] Returning cached pins (\(pinCache.count))")
            completion(Array(pinCache.values))
            return
        }
        
        // Fetch from Firestore
        print("[FirebaseOptimizer] Fetching pins from Firestore")
        
        db.collection("pins")
            .order(by: "timestamp", descending: true)
            .limit(to: 100) // Limit for performance
            .getDocuments { snapshot, error in
                if let error = error {
                    print("[FirebaseOptimizer] Error fetching pins: \(error.localizedDescription)")
                    // Return cached data if available
                    completion(Array(self.pinCache.values))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let pins = documents.compactMap { document -> Pin? in
                    let data = document.data()
                    return self.createPin(from: data, id: document.documentID)
                }
                
                // Update cache
                self.pinCache.removeAll()
                for pin in pins {
                    self.pinCache[pin.id] = pin
                }
                self.lastPinFetchTime = now
                
                print("[FirebaseOptimizer] Fetched and cached \(pins.count) pins")
                completion(pins)
            }
    }
    
    // MARK: - Real-time Listeners (Optimized)
    
    /// Sets up an optimized real-time listener for pins
    /// - Parameter onUpdate: Callback for pin updates
    func setupOptimizedPinListener(onUpdate: @escaping ([Pin]) -> Void) {
        // Clean up existing listeners
        cleanupListeners()
        
        // Use a more efficient query with recent timestamp filter
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
        
        let listener = db.collection("pins")
            .whereField("timestamp", isGreaterThan: Timestamp(date: thirtyMinutesAgo))
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("[FirebaseOptimizer] Listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Process only changed documents
                for change in snapshot.documentChanges {
                    let data = change.document.data()
                    let pinId = change.document.documentID
                    
                    switch change.type {
                    case .added, .modified:
                        if let pin = self.createPin(from: data, id: pinId) {
                            self.pinCache[pinId] = pin
                        }
                    case .removed:
                        self.pinCache.removeValue(forKey: pinId)
                    }
                }
                
                print("[FirebaseOptimizer] Processed \(snapshot.documentChanges.count) changes")
                onUpdate(Array(self.pinCache.values))
            }
        
        activeListeners.append(listener)
    }
    
    // MARK: - Storage Optimization
    
    /// Uploads video with compression and optimization
    /// - Parameters:
    ///   - videoURL: Local video URL
    ///   - pinId: Pin ID for the video
    ///   - progress: Progress callback
    ///   - completion: Completion handler
    func optimizedVideoUpload(
        videoURL: URL,
        pinId: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            do {
                // Compress video first
                let compressedURL = try await VideoManager.shared.compressVideoIfNeeded(videoURL)
                
                // Upload to Firebase Storage
                let storageRef = storage.reference().child("videos/\(pinId).mp4")
                
                let metadata = StorageMetadata()
                metadata.contentType = "video/mp4"
                metadata.customMetadata = [
                    "compressed": "true",
                    "pinId": pinId
                ]
                
                // Start upload with progress monitoring
                let uploadTask = storageRef.putFile(from: compressedURL, metadata: metadata)
                
                uploadTask.observe(.progress) { snapshot in
                    let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) /
                                        Double(snapshot.progress?.totalUnitCount ?? 1)
                    DispatchQueue.main.async {
                        progress(percentComplete)
                    }
                }
                
                uploadTask.observe(.success) { _ in
                    storageRef.downloadURL { url, error in
                        if let error = error {
                            completion(.failure(error))
                        } else if let url = url {
                            completion(.success(url))
                        }
                    }
                }
                
                uploadTask.observe(.failure) { snapshot in
                    if let error = snapshot.error {
                        completion(.failure(error))
                    }
                }
                
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createPin(from data: [String: Any], id: String) -> Pin? {
        guard let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double,
              let typeString = data["type"] as? String,
              let userId = data["userId"] as? String else {
            return nil
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let videoURL = data["videoURL"] as? String ?? ""
        let incidentType = IncidentType.fromFirestoreType(typeString)
        
        return Pin(
            id: id,
            coordinate: coordinate,
            incidentType: incidentType,
            videoURL: videoURL,
            userId: userId
        )
    }
    
    private func cleanupListeners() {
        for listener in activeListeners {
            listener.remove()
        }
        activeListeners.removeAll()
        print("[FirebaseOptimizer] Cleaned up \(activeListeners.count) listeners")
    }
    
    @objc private func handleNetworkChange() {
        // Handle network status changes
        print("[FirebaseOptimizer] Network status changed")
        
        // If back online, flush pending writes
        if !isOffline {
            Task {
                await executeBatchWrite()
            }
        }
    }
    
    // MARK: - Memory Management
    
    func clearCache() {
        pinCache.removeAll()
        lastPinFetchTime = Date.distantPast
        print("[FirebaseOptimizer] Cache cleared")
    }
    
    func cleanup() {
        batchTimer?.invalidate()
        cleanupListeners()
        clearCache()
        
        // Execute any pending writes immediately
        Task {
            await executeBatchWrite()
        }
    }
    
    deinit {
        cleanup()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("NetworkStatusChanged")
}

// MARK: - Performance Monitoring

extension FirebaseOptimizer {
    
    /// Monitors Firebase performance
    func logPerformanceMetrics() {
        let cacheSize = pinCache.count
        let pendingOps = pendingWrites.count
        let activeListenerCount = activeListeners.count
        
        print("""
        [FirebaseOptimizer] Performance Metrics:
        - Cached pins: \(cacheSize)
        - Pending operations: \(pendingOps)
        - Active listeners: \(activeListenerCount)
        - Last fetch: \(lastPinFetchTime)
        """)
    }
}