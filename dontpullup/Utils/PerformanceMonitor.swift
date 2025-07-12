import Foundation
import UIKit
import os.signpost

/// Monitors application performance metrics including memory, CPU, and timing
class PerformanceMonitor: ObservableObject {
    
    // MARK: - Properties
    static let shared = PerformanceMonitor()
    
    @Published var currentMemoryUsage: UInt64 = 0
    @Published var peakMemoryUsage: UInt64 = 0
    @Published var appLaunchTime: TimeInterval = 0
    
    // Signposts for performance tracking
    private let performanceLog = OSLog(subsystem: "com.dontpullup", category: "Performance")
    private var memoryTimer: Timer?
    private var launchStartTime: CFAbsoluteTime = 0
    
    // Performance thresholds
    private let memoryWarningThreshold: UInt64 = 150 * 1024 * 1024 // 150MB
    private let targetLaunchTime: TimeInterval = 2.0 // 2 seconds
    
    // MARK: - Initialization
    
    private init() {
        setupLaunchTimeTracking()
        startMemoryMonitoring()
        setupMemoryWarningObserver()
    }
    
    // MARK: - Launch Time Tracking
    
    private func setupLaunchTimeTracking() {
        launchStartTime = CFAbsoluteTimeGetCurrent()
        
        // Listen for when the app becomes fully loaded
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFirstMeaningfulPaint),
            name: .firstMeaningfulPaint,
            object: nil
        )
    }
    
    @objc private func handleAppDidFinishLaunching() {
        let launchTime = CFAbsoluteTimeGetCurrent() - launchStartTime
        print("[PerformanceMonitor] App finished launching in: \(launchTime)s")
    }
    
    @objc private func handleFirstMeaningfulPaint() {
        appLaunchTime = CFAbsoluteTimeGetCurrent() - launchStartTime
        print("[PerformanceMonitor] First meaningful paint in: \(appLaunchTime)s")
        
        if appLaunchTime > targetLaunchTime {
            print("[PerformanceMonitor] ⚠️ Launch time exceeded target (\(targetLaunchTime)s)")
        }
        
        // Log signpost
        os_signpost(.event, log: performanceLog, name: "App Launch", 
                   "Launch completed in %.2fs", appLaunchTime)
    }
    
    // MARK: - Memory Monitoring
    
    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.updateMemoryUsage()
        }
    }
    
    private func updateMemoryUsage() {
        let memoryUsage = getMemoryUsage()
        
        DispatchQueue.main.async {
            self.currentMemoryUsage = memoryUsage
            
            if memoryUsage > self.peakMemoryUsage {
                self.peakMemoryUsage = memoryUsage
            }
            
            // Check for memory warnings
            if memoryUsage > self.memoryWarningThreshold {
                self.handleHighMemoryUsage(memoryUsage)
            }
        }
    }
    
    /// Gets current memory usage in bytes
    static func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func getMemoryUsage() -> UInt64 {
        return Self.getMemoryUsage()
    }
    
    private func handleHighMemoryUsage(_ usage: UInt64) {
        let usageMB = Double(usage) / (1024 * 1024)
        print("[PerformanceMonitor] ⚠️ High memory usage: \(String(format: "%.1f", usageMB))MB")
        
        // Trigger memory cleanup
        NotificationCenter.default.post(name: .memoryPressure, object: usage)
        
        // Log signpost
        os_signpost(.event, log: performanceLog, name: "Memory Warning", 
                   "High memory usage: %.1fMB", usageMB)
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        print("[PerformanceMonitor] System memory warning received")
        
        // Force immediate memory cleanup
        VideoManager.shared.clearCache()
        FirebaseOptimizer.shared.clearCache()
        
        // Log event
        os_signpost(.event, log: performanceLog, name: "System Memory Warning")
    }
    
    // MARK: - Performance Metrics
    
    /// Records a custom performance event
    /// - Parameters:
    ///   - name: Event name
    ///   - duration: Event duration
    ///   - metadata: Additional metadata
    func recordEvent(name: String, duration: TimeInterval, metadata: [String: Any] = [:]) {
        print("[PerformanceMonitor] Event: \(name) - Duration: \(duration)s")
        
        // Log signpost
        os_signpost(.event, log: performanceLog, name: StaticString(name.utf8), 
                   "Duration: %.3fs", duration)
        
        // Check for performance issues
        let thresholds: [String: TimeInterval] = [
            "Video Upload": 30.0,
            "Map Load": 2.0,
            "Pin Load": 1.0,
            "Location Fix": 5.0
        ]
        
        if let threshold = thresholds[name], duration > threshold {
            print("[PerformanceMonitor] ⚠️ Performance issue: \(name) took \(duration)s (threshold: \(threshold)s)")
        }
    }
    
    /// Records the start of a timed operation
    /// - Parameter operation: Operation name
    /// - Returns: Start time for later completion
    func startTiming(_ operation: String) -> CFAbsoluteTime {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[PerformanceMonitor] Started timing: \(operation)")
        
        // Begin signpost interval
        os_signpost(.begin, log: performanceLog, name: StaticString(operation.utf8))
        
        return startTime
    }
    
    /// Records the completion of a timed operation
    /// - Parameters:
    ///   - operation: Operation name
    ///   - startTime: Start time from startTiming
    func endTiming(_ operation: String, startTime: CFAbsoluteTime) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // End signpost interval
        os_signpost(.end, log: performanceLog, name: StaticString(operation.utf8))
        
        recordEvent(name: operation, duration: duration)
    }
    
    // MARK: - Performance Reports
    
    /// Generates a performance report
    /// - Returns: Performance report string
    func generatePerformanceReport() -> String {
        let memoryMB = Double(currentMemoryUsage) / (1024 * 1024)
        let peakMemoryMB = Double(peakMemoryUsage) / (1024 * 1024)
        
        return """
        📊 Performance Report
        ==================
        🚀 Launch Time: \(String(format: "%.2f", appLaunchTime))s
        📱 Current Memory: \(String(format: "%.1f", memoryMB))MB
        📈 Peak Memory: \(String(format: "%.1f", peakMemoryMB))MB
        
        Targets:
        - Launch time: < \(targetLaunchTime)s (\(appLaunchTime <= targetLaunchTime ? "✅" : "❌"))
        - Memory usage: < \(memoryWarningThreshold / 1024 / 1024)MB (\(currentMemoryUsage <= memoryWarningThreshold ? "✅" : "❌"))
        """
    }
    
    /// Logs current performance metrics
    func logCurrentMetrics() {
        print(generatePerformanceReport())
        
        // Log to signpost
        os_signpost(.event, log: performanceLog, name: "Performance Report",
                   "Memory: %.1fMB, Launch: %.2fs", 
                   Double(currentMemoryUsage) / (1024 * 1024), appLaunchTime)
    }
    
    // MARK: - Memory Optimization Helpers
    
    /// Gets memory usage in a formatted string
    func getFormattedMemoryUsage() -> String {
        let memoryMB = Double(currentMemoryUsage) / (1024 * 1024)
        return String(format: "%.1f MB", memoryMB)
    }
    
    /// Checks if memory usage is within acceptable limits
    func isMemoryUsageHealthy() -> Bool {
        return currentMemoryUsage <= memoryWarningThreshold
    }
    
    /// Forces garbage collection and memory cleanup
    func forceMemoryCleanup() {
        print("[PerformanceMonitor] Forcing memory cleanup")
        
        // Clear various caches
        VideoManager.shared.clearCache()
        FirebaseOptimizer.shared.clearCache()
        
        // Force garbage collection (iOS will handle this automatically, but we can suggest it)
        autoreleasepool {
            // Perform cleanup operations
        }
        
        // Update memory usage after cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateMemoryUsage()
            print("[PerformanceMonitor] Memory after cleanup: \(self.getFormattedMemoryUsage())")
        }
    }
    
    // MARK: - CPU Monitoring
    
    /// Gets current CPU usage (simplified)
    func getCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var cpuMsgCount: mach_msg_type_number_t = 0
        var cpuLoad: host_cpu_load_info_data_t = host_cpu_load_info_data_t()
        
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuMsgCount, &cpuInfo, $0)
            }
        }
        
        if result != KERN_SUCCESS {
            return 0.0
        }
        
        let userTime = Double(cpuLoad.cpu_ticks.0)
        let systemTime = Double(cpuLoad.cpu_ticks.1)
        let idleTime = Double(cpuLoad.cpu_ticks.2)
        let totalTime = userTime + systemTime + idleTime
        
        return totalTime > 0 ? ((userTime + systemTime) / totalTime) * 100 : 0.0
    }
    
    // MARK: - Cleanup
    
    deinit {
        memoryTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let memoryPressure = Notification.Name("MemoryPressure")
    static let firstMeaningfulPaint = Notification.Name("FirstMeaningfulPaint")
}

// MARK: - Performance Extensions

extension PerformanceMonitor {
    
    /// Tracks view load time
    /// - Parameters:
    ///   - viewName: Name of the view
    ///   - startTime: When the view started loading
    func trackViewLoadTime(viewName: String, startTime: CFAbsoluteTime) {
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        recordEvent(name: "\(viewName) Load", duration: loadTime)
    }
    
    /// Tracks network request time
    /// - Parameters:
    ///   - requestName: Name/type of the request
    ///   - startTime: When the request started
    ///   - success: Whether the request succeeded
    func trackNetworkRequest(requestName: String, startTime: CFAbsoluteTime, success: Bool) {
        let requestTime = CFAbsoluteTimeGetCurrent() - startTime
        let eventName = "\(requestName) \(success ? "Success" : "Failure")"
        recordEvent(name: eventName, duration: requestTime)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

extension PerformanceMonitor {
    
    /// Modifier for tracking view appear times
    static func trackViewAppear<Content: View>(
        viewName: String,
        content: () -> Content
    ) -> some View {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        return content()
            .onAppear {
                PerformanceMonitor.shared.trackViewLoadTime(
                    viewName: viewName,
                    startTime: startTime
                )
            }
    }
}