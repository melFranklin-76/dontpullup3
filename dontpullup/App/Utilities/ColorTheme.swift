import SwiftUI

struct DPUTheme {
  // Use Swift's built-in thread-safe singleton pattern
  private static let colorTheme = ColorTheme()

  static var colors: ColorTheme {
    colorTheme
  }

  struct ColorTheme {
    // MARK: - Brand Palette
    let neonPurple = Color(red: 0.73, green: 0.29, blue: 0.98)
    let neonYellow = Color(red: 0.99, green: 0.85, blue: 0.28)
    let alertRed = Color(red: 0.99, green: 0.24, blue: 0.32)
    let electricBlue = Color(red: 0.0, green: 0.58, blue: 0.99)
    let aquaTeal = Color(red: 0.29, green: 0.91, blue: 0.84)
    let fuchsia = Color(red: 0.97, green: 0.32, blue: 0.71)

    // MARK: - Surfaces
    let darkBlack = Color(red: 0.02, green: 0.04, blue: 0.09)
    let charcoalBlack = Color(red: 0.07, green: 0.08, blue: 0.14)
    let midnightBlue = Color(red: 0.05, green: 0.08, blue: 0.22)
    let cardShadow = Color.black.opacity(0.35)
    let borderHighlight = Color.white.opacity(0.18)
    let subtleSeparator = Color.white.opacity(0.08)

    // MARK: - Typography
    let lightGray = Color(red: 0.84, green: 0.87, blue: 0.92)
    let mutedGray = Color.white.opacity(0.65)

    // MARK: - Dynamic Styles
    var backgroundGradient: LinearGradient {
      LinearGradient(
        colors: [
          Color(red: 0.03, green: 0.04, blue: 0.10),
          midnightBlue,
          Color(red: 0.05, green: 0.0, blue: 0.18),
          Color(red: 0.00, green: 0.14, blue: 0.23),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }

    var accentGradient: LinearGradient {
      LinearGradient(
        colors: [
          electricBlue,
          aquaTeal,
          neonPurple,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }

    var glassHighlightGradient: LinearGradient {
      LinearGradient(
        colors: [
          Color.white.opacity(0.35),
          Color.white.opacity(0.05),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }

    init() {}
  }
}