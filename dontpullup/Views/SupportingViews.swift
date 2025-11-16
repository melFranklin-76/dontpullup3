import SwiftUI
import UIKit

// Define our custom behavior type with a different name to avoid conflicts
#if !swift(>=5.8)
  @available(iOS, deprecated: 16.4, message: "Use native ScrollBounceBehavior instead")
  enum DPUScrollBounceMode: Equatable {
    case automatic
    case always
    case basedOnSize
  }
#endif

// MARK: - Universal Scrollable View Modifier

/// A custom view modifier that makes any view content scrollable and centered
/// for all device sizes, especially effective for iPad screens.
struct ScrollableViewModifier: ViewModifier {
  // Maximum content width to prevent overly wide content on large screens
  var maxContentWidth: CGFloat = 600
  // Background style options
  var useBackgroundImage: Bool = true
  var backgroundOpacity: Double = 0.7
  // Padding options
  var horizontalPadding: CGFloat? = nil
  var bottomPadding: CGFloat? = nil
  // Scrolling behavior options
  var disableBounce: Bool = true

  func body(content: Content) -> some View {
    GeometryReader { geometry in
      ZStack {
        // Background with conditional image
        if useBackgroundImage {
          if let bgImage = UIImage(named: "welcome_background") {
            Image(uiImage: bgImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .edgesIgnoringSafeArea(.all)
          } else {
            // Fallback to solid color if image not found
            Color.black
              .edgesIgnoringSafeArea(.all)
          }

          Color.black.opacity(backgroundOpacity)
            .edgesIgnoringSafeArea(.all)
        }

        // Scrollable content
        ScrollViewWithBounceControl(disableBounce: disableBounce) {
          VStack(spacing: 0) {
            // Top spacing for drag indicator and safe area
            Spacer().frame(height: 20)

            // Main content wrapped in horizontally centered container with fail-safe width calculation
            content
              .frame(
                maxWidth: {
                  let padding =
                    horizontalPadding
                    ?? adaptiveHorizontalPadding(for: geometry, maxWidth: maxContentWidth)
                  let availableWidth = max(0, geometry.size.width - padding * 2)
                  return min(maxContentWidth, availableWidth)
                }()
              )
              .padding(
                .horizontal,
                horizontalPadding
                  ?? adaptiveHorizontalPadding(for: geometry, maxWidth: maxContentWidth)
              )

            // Bottom spacing for safe area and better scrolling with safe height
            Spacer().frame(height: bottomPadding ?? max(40, geometry.safeAreaInsets.bottom + 20))
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
  }

  // Adaptive padding helper with improved error handling
  private func adaptiveHorizontalPadding(for geometry: GeometryProxy, maxWidth: CGFloat) -> CGFloat
  {
    // Safety check for valid inputs
    guard geometry.size.width > 0, maxWidth > 0 else {
      return 20  // Default padding if invalid inputs
    }

    let screenWidth = geometry.size.width
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad

    // For iPads or larger screens, use a maximum width with centered content
    if isIPad || screenWidth > maxWidth {
      return max(20, (screenWidth - maxWidth) / 2)
    }

    // For smaller screens, use standard padding
    return 20
  }
}

/// A scroll view that supports disabling bounce on all iOS versions
struct ScrollViewWithBounceControl<Content: View>: View {
  let disableBounce: Bool
  let content: Content

  init(disableBounce: Bool = true, @ViewBuilder content: () -> Content) {
    self.disableBounce = disableBounce
    self.content = content()
  }

  var body: some View {
    if #available(iOS 16.4, *) {
      // Use the native API for iOS 16.4 and later
      ScrollView(.vertical, showsIndicators: true) {
        content
      }
      .scrollBounceBehavior(disableBounce ? .basedOnSize : .automatic)
    } else {
      // For earlier iOS versions, use UIScrollView delegate
      LegacyScrollView(showsIndicators: true, bounces: !disableBounce) {
        content
      }
    }
  }
}

/// A UIViewRepresentable wrapper for UIScrollView with bounce control
struct LegacyScrollView<Content: View>: UIViewRepresentable {
  let showsIndicators: Bool
  let bounces: Bool
  let content: Content

  init(showsIndicators: Bool = true, bounces: Bool = true, @ViewBuilder content: () -> Content) {
    self.showsIndicators = showsIndicators
    self.bounces = bounces
    self.content = content()
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.showsVerticalScrollIndicator = showsIndicators
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.bounces = bounces
    scrollView.backgroundColor = .clear

    // Add SwiftUI content
    let hostingController = UIHostingController(rootView: content)
    hostingController.view.backgroundColor = .clear

    // Set up constraints
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(hostingController.view)

    NSLayoutConstraint.activate([
      hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      // Ensure content width matches scrollView width
      hostingController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
    ])

    // Store the hosting controller to keep it alive
    context.coordinator.hostingController = hostingController

    return scrollView
  }

  func updateUIView(_ uiView: UIScrollView, context: Context) {
    // Update the hosting controller's rootView
    context.coordinator.hostingController?.rootView = content

    // Update scroll view properties
    uiView.bounces = bounces
    uiView.showsVerticalScrollIndicator = showsIndicators

    // Force layout update
    context.coordinator.hostingController?.view.setNeedsLayout()
    uiView.setNeedsLayout()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    var hostingController: UIHostingController<Content>?
  }
}

// MARK: - View Extension
extension View {
  /// Makes the view scrollable and centered for all device sizes
  /// - Parameters:
  ///   - maxWidth: Maximum width of the content (default: 600pt)
  ///   - useBackgroundImage: Whether to use the standard background image (default: true)
  ///   - backgroundOpacity: Opacity of the black background overlay (default: 0.7)
  ///   - horizontalPadding: Optional custom horizontal padding (default: adaptive)
  ///   - bottomPadding: Optional custom bottom padding (default: adaptive)
  ///   - disableBounce: Whether to disable the bounce effect (default: true)
  /// - Returns: A modified view that is scrollable and centered
  func universalScrollView(
    maxWidth: CGFloat = 600,
    useBackgroundImage: Bool = true,
    backgroundOpacity: Double = 0.7,
    horizontalPadding: CGFloat? = nil,
    bottomPadding: CGFloat? = nil,
    disableBounce: Bool = true
  ) -> some View {
    modifier(
      ScrollableViewModifier(
        maxContentWidth: maxWidth,
        useBackgroundImage: useBackgroundImage,
        backgroundOpacity: backgroundOpacity,
        horizontalPadding: horizontalPadding,
        bottomPadding: bottomPadding,
        disableBounce: disableBounce
      )
    )
  }
}

// MARK: - Modern Background & Glass Utilities

struct DPUBackgroundView: View {
  var body: some View {
    ZStack {
      DPUTheme.colors.backgroundGradient
      RadialGradient(
        colors: [
          DPUTheme.colors.neonPurple.opacity(0.3),
          Color.clear,
        ],
        center: .topLeading,
        startRadius: 80,
        endRadius: 400
      )
      .blur(radius: 50)

      LinearGradient(
        colors: [
          Color.white.opacity(0.08),
          Color.clear,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }
}

private struct DPUBackgroundModifier: ViewModifier {
  let edges: Edge.Set

  func body(content: Content) -> some View {
    ZStack {
      DPUBackgroundView()
        .ignoresSafeArea(edges: edges)
      content
    }
  }
}

extension View {
  /// Applies the shared Don't Pull Up gradient background behind the view hierarchy.
  func dpuBackground(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
    modifier(DPUBackgroundModifier(edges: edges))
  }
}

// Shared glass background used by cards and rows.
struct GlassCardBackground: View {
  var cornerRadius: CGFloat
  var tint: Color

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(.ultraThinMaterial)
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(DPUTheme.colors.borderHighlight, lineWidth: 0.8)
          .blendMode(.overlay)
      )
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(tint.opacity(0.35))
          .blur(radius: 25)
      )
  }
}

// Reusable container styling for glass-like modal sheets
private struct GlassSheetModifier: ViewModifier {
  var maxWidth: CGFloat = 540
  var cornerRadius: CGFloat = 28

  func body(content: Content) -> some View {
    content
      .padding(24)
      .frame(maxWidth: maxWidth, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(.ultraThinMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .stroke(DPUTheme.colors.borderHighlight, lineWidth: 1)
              .blendMode(.overlay)
          )
          .shadow(color: DPUTheme.colors.cardShadow.opacity(0.6), radius: 30, x: 0, y: 15)
      )
      .padding(.horizontal, 24)
      .padding(.vertical, 40)
  }
}

extension View {
  func glassSheetStyle(maxWidth: CGFloat = 540) -> some View {
    modifier(GlassSheetModifier(maxWidth: maxWidth))
  }
}

// MARK: - Shared Cards and Components

/// A reusable card view with consistent styling
struct DPUCard<Content: View>: View {
  var content: Content
  var backgroundColor: Color = Color.black.opacity(0.5)
  var cornerRadius: CGFloat = 12
  var useShadow: Bool = true

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  init(
    backgroundColor: Color = Color.black.opacity(0.5),
    cornerRadius: CGFloat = 12,
    useShadow: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
    self.backgroundColor = backgroundColor
    self.cornerRadius = cornerRadius
    self.useShadow = useShadow
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .padding(20)
    .background(
      GlassCardBackground(cornerRadius: cornerRadius, tint: backgroundColor)
    )
    .padding(.horizontal, 2)
    .if(useShadow) { view in
      view.shadow(color: DPUTheme.colors.cardShadow, radius: 15, x: 0, y: 10)
    }
  }
}

// Modern glassmorphism card with enhanced visual effects
struct ModernDPUCard<Content: View>: View {
  var content: Content
  var cornerRadius: CGFloat = 16
  var useShadow: Bool = true

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      // Modern glassmorphism effect
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(DPUTheme.colors.accentGradient, lineWidth: 1.2)
        )
        .background(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DPUTheme.colors.neonPurple.opacity(0.18))
            .blur(radius: 30)
        )
        .if(useShadow) { view in
          view.shadow(color: DPUTheme.colors.cardShadow, radius: 18, x: 0, y: 12)
        }

      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .padding(22)
    }
    .padding(.horizontal, 4)
  }
}

// Enhanced toggle with haptic feedback and animations
struct EnhancedToggle: View {
  @Binding var isOn: Bool
  let label: String
  let description: String?

  init(isOn: Binding<Bool>, label: String, description: String? = nil) {
    self._isOn = isOn
    self.label = label
    self.description = description
  }

  var body: some View {
    Toggle(isOn: $isOn.animation(.spring(response: 0.3, dampingFraction: 0.7))) {
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .foregroundColor(DPUTheme.colors.lightGray)
          .font(.body.weight(.semibold))
        if let description = description {
          Text(description)
            .foregroundColor(DPUTheme.colors.mutedGray)
            .font(.caption)
        }
      }
    }
    .toggleStyle(SwitchToggleStyle(tint: DPUTheme.colors.electricBlue))
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white.opacity(0.02))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    )
    .onChange(of: isOn) { _ in
      // Haptic feedback
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
  }
}

// Modern button with enhanced styling
struct ModernButton: View {
  let title: String
  let systemImage: String?
  let style: ButtonStyle
  let action: () -> Void

  enum ButtonStyle {
    case primary, secondary, destructive, success
  }

  var body: some View {
    Button(action: {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      action()
    }) {
      HStack(spacing: 8) {
        if let image = systemImage {
          Image(systemName: image)
            .font(.system(size: 16, weight: .semibold))
        }
        Text(title)
          .font(.system(.subheadline, design: .rounded).weight(.semibold))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(buttonBackground)
      .foregroundColor(buttonForeground)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
      )
      .shadow(color: shadowColor, radius: 5, x: 0, y: 3)
    }
  }

  @ViewBuilder
  private var buttonBackground: some View {
    switch style {
    case .primary:
      DPUTheme.colors.accentGradient
    case .secondary:
      Color.white.opacity(0.08)
        .overlay(DPUTheme.colors.glassHighlightGradient)
    case .destructive:
      LinearGradient(
        colors: [DPUTheme.colors.alertRed, Color.red.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .success:
      LinearGradient(
        colors: [Color.green, DPUTheme.colors.aquaTeal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }

  private var buttonForeground: Color {
    switch style {
    case .primary, .destructive, .success:
      return .white
    case .secondary:
      return DPUTheme.colors.lightGray
    }
  }

  private var shadowColor: Color {
    switch style {
    case .primary:
      return DPUTheme.colors.electricBlue.opacity(0.35)
    case .destructive:
      return DPUTheme.colors.alertRed.opacity(0.35)
    case .success:
      return DPUTheme.colors.aquaTeal.opacity(0.35)
    case .secondary:
      return Color.black.opacity(0.25)
    }
  }
}

// Helper extension for conditional modifiers
extension View {
  @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content)
    -> some View
  {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}

// MARK: - Section Header
/// A reusable section header with consistent styling
struct DPUSectionHeader: View {
  var title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title.uppercased())
        .font(.caption2.weight(.semibold))
        .kerning(1.2)
        .foregroundStyle(DPUTheme.colors.accentGradient)

      Rectangle()
        .fill(DPUTheme.colors.subtleSeparator)
        .frame(height: 1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 12)
    .padding(.bottom, 4)
  }
}

// MARK: - Scroll Bounce Compatibility
extension View {
  @ViewBuilder
  func disableScrollBounce(_ disable: Bool = true) -> some View {
    if #available(iOS 16.4, *) {
      // Use the native API for iOS 16.4 and later
      self.scrollBounceBehavior(disable ? .basedOnSize : .automatic)
    } else {
      // For earlier iOS versions, use our custom implementation
      self.background(ScrollBounceDisabler(disable: disable))
    }
  }
}

// UIViewRepresentable wrapper to modify UIScrollView bounce behavior on earlier iOS versions
struct ScrollBounceDisabler: UIViewRepresentable {
  let disable: Bool

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    // Find parent UIScrollView
    DispatchQueue.main.async {
      guard let scrollView = uiView.findScrollView() else { return }

      if disable {
        // Disable bounce
        scrollView.bounces = false
      } else {
        // Enable bounce
        scrollView.bounces = true
      }
    }
  }
}

// Helper to find parent UIScrollView
extension UIView {
  func findScrollView() -> UIScrollView? {
    // Check if self is a UIScrollView
    if let scrollView = self as? UIScrollView {
      return scrollView
    }

    // Check if the superview is a UIScrollView
    if let scrollView = self.superview as? UIScrollView {
      return scrollView
    }

    // Recursively check parent views
    return self.superview?.findScrollView()
  }
}

// ... existing code follows
