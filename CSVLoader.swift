import Foundation

/// Utility for robust, warning-logged CSV file loading.
struct CSVLoader {
    /// Attempts to load a CSV file from the app bundle. If not found, logs a warning and returns nil or fallback data.
    /// - Parameters:
    ///   - name: The name of the CSV file without extension (e.g. "default")
    ///   - fallback: Optional fallback data to use if the CSV is missing.
    /// - Returns: The CSV contents as a string, or the fallback if not found.
    static func loadCSV(named name: String, fallback: String? = nil) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "csv") {
            return try? String(contentsOf: url)
        } else {
            print("[Warning] CSV file \(name).csv not found in bundle. Using fallback.")
            return fallback
        }
    }
}

// Example usage:
// let data = CSVLoader.loadCSV(named: "default", fallback: "header1,header2\nvalue1,value2")
