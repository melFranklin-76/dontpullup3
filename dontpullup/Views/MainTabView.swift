import AVKit
import Combine
import MapKit
import SwiftUI
import UIKit

struct MainTabView: View {
  @EnvironmentObject private var networkMonitor: NetworkMonitor
  @EnvironmentObject private var authState: AuthState
  @StateObject private var mapViewModel: MapViewModel
  @State private var showingTutorial = false

  // Custom init to pass AuthState to MapViewModel
  init() {
    // Initialize mapViewModel using the shared AuthState instance.
    // This assumes AuthState.shared is available and configured when MainTabView is created.
    // If authState EnvironmentObject is preferred, a different pattern is needed (e.g. view model factory or .onAppear configuration)
    _mapViewModel = StateObject(wrappedValue: MapViewModel(authState: AuthState.shared))
  }

  var body: some View {
    // Main map content
    MapContentView()
      .environmentObject(mapViewModel)
      .preferredColorScheme(.dark)
      .alert("Location Error", isPresented: $mapViewModel.showAlert) {
        Button("OK", role: .cancel) {
          // Call alertDismissed when alert is dismissed
          mapViewModel.alertDismissed()
        }
      } message: {
        Text(mapViewModel.alertMessage)
      }
      .sheet(isPresented: $mapViewModel.showingIncidentPicker) {
        IncidentPickerView(viewModel: mapViewModel)
      }
      .sheet(isPresented: $mapViewModel.showingHelp) {
        HelpView()
      }
      .sheet(item: $mapViewModel.reportStep) { _ in
        ReportFlowView(viewModel: mapViewModel)
      }
      .sheet(isPresented: $mapViewModel.showingContentGuidelines) {
        ContentGuidelinesView(isPresented: $mapViewModel.showingContentGuidelines) {
          mapViewModel.acceptContentGuidelines()
        }
      }
      .onAppear {
        // Check if we should show the tutorial (for anonymous users or first-time users)
        checkTutorialState()
        mapViewModel.handleLocationAction(.initialPrompt)
      }
      .onReceive(
        NotificationCenter.default.publisher(for: Notification.Name("ShowTutorialOverlay"))
      ) { _ in
        // Direct trigger from settings page
        print("MainTabView: Received ShowTutorialOverlay notification")
        presentTutorial()
      }
    // No longer using SwiftUI presentation for the tutorial
    // Instead, using direct UIKit presentation for reliability
  }

  /// Checks whether tutorial should be shown and presents it if needed
  private func checkTutorialState() {
    // Debug: Print authentication state
    let isAnonymousUser = authState.currentUser?.isAnonymous ?? false
    print(
      "AUTH DEBUG: isAuthenticated = \(authState.isAuthenticated), isAnonymous = \(isAnonymousUser)"
    )
    print("AUTH DEBUG: CurrentUser = \(String(describing: authState.currentUser))")

    var shouldShowTutorial = false

    // For anonymous users, always show tutorial
    if isAnonymousUser {
      print("AUTH DEBUG: User is anonymous, showing tutorial")
      shouldShowTutorial = true
    }

    // For email-authenticated users, check if they've seen it before
    else if authState.isAuthenticated {
      let hasSeenTutorial = UserDefaults.standard.bool(forKey: "hasSeenTutorial")
      print("AUTH DEBUG: User is authenticated, hasSeenTutorial = \(hasSeenTutorial)")
      if !hasSeenTutorial {
        shouldShowTutorial = true
        // Will mark as seen after tutorial completes
      }
    }

    // Present tutorial after a short delay if needed
    if shouldShowTutorial {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        presentTutorial()
      }
    }

    // For testing: Uncomment to force tutorial display
    // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { presentTutorial() }
  }

  /// Presents the tutorial using UIKit for guaranteed visibility
  private func presentTutorial() {
    // Find the topmost view controller to avoid constraint issues and always present from the correct context
    guard let topController = topMostViewController() else {
      print("Tutorial Error: Could not find top view controller")
      return
    }

    // Create and present the tutorial
    let tutorialVC = TutorialViewController {
      // Called when tutorial is dismissed
      print("Tutorial was dismissed")

      // For email users, mark tutorial as seen after viewing
      if !(self.authState.currentUser?.isAnonymous ?? true) {
        UserDefaults.standard.set(true, forKey: "hasSeenTutorial")
      }
    }

    topController.present(tutorialVC, animated: true) {
      print("Tutorial presented successfully")
    }
  }
}

struct MapContentView: View {
  @EnvironmentObject private var mapViewModel: MapViewModel
  @EnvironmentObject private var networkMonitor: NetworkMonitor
  @EnvironmentObject private var authState: AuthState
  @State private var showingSettings = false
  @State private var showingProfile = false
  @State private var showingTermsOfService = false
  @State private var showingPrivacyPolicy = false
  @State private var showingPremium = false
  @State private var showingZipCodePurchase = false
  private let hapticImpact = UIImpactFeedbackGenerator(style: .medium)

  // State for marquee animation
  @State private var marqueeOffset: CGFloat = 0
  private let marqueeSpacer = "  "  // Double space at the end
  private let baseMarqueeText = "SHOW US WHO THEY ARE        WE WILL SHOW THEM WHO WE ARE NOT"
  private var marqueeText: String { baseMarqueeText + marqueeSpacer }

  // Create publishers for the notification events
  private let termsOfServicePublisher = NotificationCenter.default
    .publisher(for: Notification.Name("OpenTermsOfService"))

  private let privacyPolicyPublisher = NotificationCenter.default
    .publisher(for: Notification.Name("OpenPrivacyPolicy"))
  
  private let showPremiumPublisher = NotificationCenter.default
    .publisher(for: Notification.Name("ShowPremiumView"))
  
  private let showZipCodePurchasePublisher = NotificationCenter.default
    .publisher(for: Notification.Name("ShowZipCodePurchase"))

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // MapView should be the background with nothing behind it
        MapContentWrapper(viewModel: mapViewModel)
          .frame(minWidth: 1, minHeight: 1)
          .edgesIgnoringSafeArea(.all)
          .preferredColorScheme(.dark)

        // Custom location permission overlay removed. The native system prompt will handle first-time requests. After denial, the user must enable permissions in Settings.

        VStack(spacing: 0) {
          // Top Banner Area - Adaptively sized for different devices
          ZStack {
            // Background "DON'T PULL UP" text - adaptive sizing
            Text("DON'T PULL UP")
              .font(
                .system(
                  size: adaptiveFontSize(for: geometry, baseSize: 25, scaleFactor: 0.06),
                  weight: .heavy)
              )
              .foregroundColor(.yellow)
              .tracking(2.0)
              .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
              .frame(maxWidth: .infinity)
              .padding(.horizontal, geometry.size.width * 0.1)

            // Marquee sits visually above "ON GRANDMA!" within the ZStack
            GeometryReader { marqueeGeometry in
              let font = UIFont.systemFont(
                ofSize: adaptiveFontSize(for: geometry, baseSize: 12, scaleFactor: 0.03),
                weight: .medium)
              let textWidth = marqueeText.widthOfString(usingFont: font)
              
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                  // Use 3 copies for seamless looping
                  ForEach(0..<3, id: \.self) { index in
                    Text(marqueeText)
                      .font(
                        .system(
                          size: adaptiveFontSize(for: geometry, baseSize: 12, scaleFactor: 0.03),
                          weight: .medium)
                      )
                      .foregroundColor(.black)
                      .tracking(1.5)
                      .fixedSize(horizontal: true, vertical: false)
                  }
                }
                .offset(x: marqueeOffset)
              }
              .disabled(true)
              .clipped()
              .task {
                // Calculate animation duration for smooth scrolling
                let speed: CGFloat = 50  // pixels per second - adjust this to change speed
                let duration = Double(textWidth / speed)
                
                // Start seamless infinite animation
                // With 3 copies, when offset reaches -textWidth, copy 2 is at position 0
                // So resetting to 0 is visually seamless
                marqueeOffset = 0
                
                // Create seamless infinite loop using continuous animation
                // The reset happens instantly when the next copy is in the exact same position
                while !Task.isCancelled {
                  // Animate smoothly to -textWidth
                  withAnimation(.linear(duration: duration)) {
                    marqueeOffset = -textWidth
                  }
                  
                  // Wait for animation to complete
                  try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                  
                  // Reset instantly without animation - this happens when copy 2 is at position 0
                  // so it's completely invisible to the user
                  marqueeOffset = 0
                }
              }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)  // Fixed height to prevent layout issues
            .clipped()
            .shadow(color: .black.opacity(0.5), radius: 1)
            // Offset slightly below the vertical center for positioning between banners
            .offset(y: 5)

            // ON GRANDMA! Text
            VStack(spacing: 0) {
              Spacer()  // Pushes ON GRANDMA down within its ZStack layer
                .frame(height: 20)  // Adjust as needed based on desired banner spacing

              Text("ON GRANDMA!")
                .font(
                  .custom(
                    "BlackOpsOne-Regular",
                    size: adaptiveFontSize(for: geometry, baseSize: 18, scaleFactor: 0.045))
                )
                .foregroundColor(DPUTheme.colors.alertRed)
                .tracking(1.0)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .rotationEffect(.degrees(-15))
            }
          }
          // Dynamic top padding: keep banner clear of the status bar on small devices
          .padding(
            .top,
            {
              // On very tall phones keep the original offset, otherwise lift it
              let baseOffset = geometry.size.height > 750 ? -35.0 : -20.0
              // Never let it overlap the status bar → minimum 4-pt gap
              return max(4, geometry.safeAreaInsets.top + baseOffset)
            }()
          )
          .padding(.bottom, 8)  // Add some space below the banner

          Spacer()  // Pushes filters/bottom controls down

          // Right side indicators with adaptive sizing
          HStack {
            Spacer()
            // Dynamic spacing relative to screen height
            VStack(spacing: geometry.size.height * 0.025) {
              // Indicator buttons with adaptive sizing for iPad
              let isIPad = UIDevice.current.userInterfaceIdiom == .pad
              let buttonSpacing =
                isIPad ? geometry.size.height * 0.02 : geometry.size.height * 0.025

              VStack(spacing: buttonSpacing) {
                indicatorButton(
                  emoji: "📢",
                  action: {
                    hapticImpact.impactOccurred()
                    mapViewModel.toggleFilter(.verbal)
                  }, isSelected: mapViewModel.selectedFilters.contains(.verbal), geometry: geometry)

                indicatorButton(
                  emoji: "👊",
                  action: {
                    hapticImpact.impactOccurred()
                    mapViewModel.toggleFilter(.physical)
                  }, isSelected: mapViewModel.selectedFilters.contains(.physical),
                  geometry: geometry)

                indicatorButton(
                  emoji: "🚨",
                  action: {
                    hapticImpact.impactOccurred()
                    mapViewModel.toggleFilter(.emergency)
                  }, isSelected: mapViewModel.selectedFilters.contains(.emergency),
                  geometry: geometry
                )

                indicatorButton(
                  emoji: "🧊",
                  action: {
                    hapticImpact.impactOccurred()
                    mapViewModel.toggleFilter(.ice)
                  }, isSelected: mapViewModel.selectedFilters.contains(.ice),
                  geometry: geometry
                )

                indicatorButton(
                  emoji: "📱",
                  action: {
                    hapticImpact.impactOccurred()
                    mapViewModel.toggleMyPinsFilter()
                  }, isSelected: mapViewModel.showingOnlyMyPins, geometry: geometry)
              }

              Spacer()

              // Responsive zoom button size based on screen width
              let zoomSize = adaptiveButtonSize(for: geometry, baseSize: 40, scaleFactor: 0.11)
              Button(action: {
                hapticImpact.impactOccurred()
                // Use the enhanced zoom in function
                mapViewModel.zoomIn()
              }) {
                Image(systemName: "plus")
                  .font(
                    .system(
                      size: adaptiveFontSize(for: geometry, baseSize: 18, scaleFactor: 0.04),
                      weight: .bold)
                  )
                  .foregroundColor(.white)
                  .frame(width: zoomSize, height: zoomSize)
                  .background(Color.black.opacity(0.6))
                  .clipShape(Circle())
              }

              Button(action: {
                hapticImpact.impactOccurred()
                // Use the enhanced zoom out function
                mapViewModel.zoomOut()
              }) {
                Image(systemName: "minus")
                  .font(
                    .system(
                      size: adaptiveFontSize(for: geometry, baseSize: 18, scaleFactor: 0.04),
                      weight: .bold)
                  )
                  .foregroundColor(.white)
                  .frame(width: zoomSize, height: zoomSize)
                  .background(Color.black.opacity(0.6))
                  .clipShape(Circle())
              }
            }
            .padding(.trailing, adaptivePadding(for: geometry, baseSize: 16, scaleFactor: 0.02))
            .padding(.bottom, geometry.safeAreaInsets.bottom + 8)  // keep above Home bar
            .frame(maxHeight: .infinity, alignment: .top)
          }

          Spacer()

          // Network status indicator (if needed)
          if !networkMonitor.isConnected {
            Text("Offline Mode - Some features may be limited")
              .font(.caption2)
              .foregroundColor(.yellow)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.black.opacity(0.7))
              .cornerRadius(4)
              .padding(.bottom, 4)
          }

          // Bottom toolbar with buttons (without shaded background)
          HStack(spacing: 0) {
            // Help button
            toolbarButton(
              systemName: "questionmark.circle",
              action: {
                hapticImpact.impactOccurred()
                mapViewModel.showingHelp = true
              }, geometry: geometry)

            // Settings button
            toolbarButton(
              systemName: "gear",
              action: {
                hapticImpact.impactOccurred()
                showingSettings = true
              }, geometry: geometry)

            // Location tracking toggle button
            // Shows different icon based on tracking state:
            // - "location" = not tracking (will center once when tapped)
            // - "location.fill" = actively tracking user (like navigation)
            toolbarButton(
              systemName: mapViewModel.isTrackingUserLocation ? "location.fill" : "location",
              action: {
                hapticImpact.impactOccurred()
                // Toggle between tracking mode and one-time center
                if mapViewModel.isTrackingUserLocation {
                  // If already tracking, stop tracking
                  mapViewModel.toggleLocationTracking()
                } else {
                  // If not tracking, start tracking mode (like navigation)
                  mapViewModel.toggleLocationTracking()
                }
              },
              tint: mapViewModel.isTrackingUserLocation ? .blue : .white,
              geometry: geometry)

            // Map type cycle button - cycles through all map types
            mapStyleMenu(geometry: geometry, mapViewModel: mapViewModel)

            // Edit mode toggle button
            toolbarButton(
              systemName: mapViewModel.isEditMode ? "xmark.circle" : "pencil",
              action: {
                hapticImpact.impactOccurred()
                mapViewModel.toggleEditMode()
              },
              tint: mapViewModel.isEditMode ? .red : .white,
              geometry: geometry
            )

            // Profile button
            toolbarButton(
              systemName: "person.circle",
              action: {
                hapticImpact.impactOccurred()
                showingProfile = true
              }, geometry: geometry)
          }
          .padding(.bottom, geometry.safeAreaInsets.bottom)
        }
      }
      .onChange(of: authState.isAuthenticated) { isAuthenticated in
        if !isAuthenticated {
          print(
            "[MapContentView] authState.isAuthenticated changed to false. Dismissing profile and settings sheets."
          )
          showingProfile = false
          showingSettings = false
        }
      }
    }
    // Listen for notification events using onReceive
    .onReceive(termsOfServicePublisher) { _ in
      showingTermsOfService = true
    }
    .onReceive(privacyPolicyPublisher) { _ in
      showingPrivacyPolicy = true
    }
    .onReceive(showPremiumPublisher) { _ in
      showingPremium = true
    }
    .onReceive(showZipCodePurchasePublisher) { _ in
      showingZipCodePurchase = true
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
        .environmentObject(authState)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingProfile) {
      ProfileView()
        .environmentObject(authState)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingPremium) {
      PremiumView()
        .environmentObject(authState)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingZipCodePurchase) {
      ZipCodePurchaseView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingTermsOfService) {
      // Present the dedicated TermsOfServiceView
      NavigationView {
        TermsOfServiceView()
          .navigationBarItems(trailing: Button("Done") { showingTermsOfService = false })
      }
      .preferredColorScheme(.dark)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingPrivacyPolicy) {
      // Present the dedicated PrivacyPolicyView
      NavigationView {
        PrivacyPolicyView()
          .navigationBarItems(trailing: Button("Done") { showingPrivacyPolicy = false })
      }
      .preferredColorScheme(.dark)
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
  }

  // Helper function for indicator buttons (right side) with adaptive sizing
  private func indicatorButton(
    emoji: String, action: @escaping () -> Void, isSelected: Bool, geometry: GeometryProxy
  ) -> some View {
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let buttonSize =
      isIPad
      ? adaptiveButtonSize(for: geometry, baseSize: 60, scaleFactor: 0.1)
      : adaptiveButtonSize(for: geometry, baseSize: 50, scaleFactor: 0.13)

    return Button(action: action) {
      ZStack {
        Circle()
          .fill(isSelected ? Color.red.opacity(0.7) : Color.black.opacity(0.6))
          .frame(width: buttonSize, height: buttonSize)

        Text(emoji)
          .font(
            .system(
              size: isIPad
                ? adaptiveFontSize(for: geometry, baseSize: 28, scaleFactor: 0.05)
                : adaptiveFontSize(for: geometry, baseSize: 24, scaleFactor: 0.06)))
      }
    }
  }

  private func toolbarButtonLabel(
    systemName: String, tint: Color, geometry: GeometryProxy
  ) -> some View {
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let iconSize =
      isIPad
      ? adaptiveFontSize(for: geometry, baseSize: 26, scaleFactor: 0.04)
      : adaptiveFontSize(for: geometry, baseSize: 22, scaleFactor: 0.05)
    let buttonHeight =
      isIPad
      ? adaptiveButtonSize(for: geometry, baseSize: 60, scaleFactor: 0.06)
      : adaptiveButtonSize(for: geometry, baseSize: 44, scaleFactor: 0.07)

    return Image(systemName: systemName)
      .font(.system(size: iconSize))
      .foregroundColor(tint)
      .frame(maxWidth: .infinity)
      .frame(height: buttonHeight)
  }

  // Helper function for toolbar buttons (bottom) with adaptive sizing
  private func toolbarButton(
    systemName: String, action: @escaping () -> Void, tint: Color = .white, geometry: GeometryProxy
  ) -> some View {
    Button(action: action) {
      toolbarButtonLabel(systemName: systemName, tint: tint, geometry: geometry)
    }
  }

  @ViewBuilder
  private func mapStyleMenu(geometry: GeometryProxy, mapViewModel: MapViewModel) -> some View {
    Menu {
      ForEach(MapDisplayStyle.allCases) { style in
        Button {
          mapViewModel.setMapDisplayStyle(style)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: style.iconName)
              .foregroundColor(style == mapViewModel.mapDisplayStyle ? .accentColor : .primary)

            VStack(alignment: .leading, spacing: 2) {
              Text(style.title)
                .fontWeight(style == mapViewModel.mapDisplayStyle ? .semibold : .regular)
              Text(style.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if style == mapViewModel.mapDisplayStyle {
              Spacer()
              Image(systemName: "checkmark")
                .foregroundColor(.accentColor)
            }
          }
        }
      }
    } label: {
      toolbarButtonLabel(
        systemName: mapViewModel.mapTypeIcon(),
        tint: .white,
        geometry: geometry
      )
    }
    .frame(maxWidth: .infinity)
  }

  // Helper function to calculate adaptive font sizes based on screen size
  private func adaptiveFontSize(
    for geometry: GeometryProxy, baseSize: CGFloat, scaleFactor: CGFloat
  ) -> CGFloat {
    let screenWidth = geometry.size.width
    let screenHeight = geometry.size.height
    let smallerDimension = min(screenWidth, screenHeight)

    // Calculate size based on screen dimension, with minimum size protection
    return max(baseSize, smallerDimension * scaleFactor)
  }

  // Helper function to calculate adaptive button sizes based on screen size
  private func adaptiveButtonSize(
    for geometry: GeometryProxy, baseSize: CGFloat, scaleFactor: CGFloat
  ) -> CGFloat {
    let screenWidth = geometry.size.width
    let screenHeight = geometry.size.height
    let smallerDimension = min(screenWidth, screenHeight)

    // Calculate size based on screen dimension, with minimum size protection
    return max(baseSize, smallerDimension * scaleFactor)
  }

  // Helper function to calculate adaptive padding based on screen size
  private func adaptivePadding(for geometry: GeometryProxy, baseSize: CGFloat, scaleFactor: CGFloat)
    -> CGFloat
  {
    let screenWidth = geometry.size.width
    let screenHeight = geometry.size.height
    let smallerDimension = min(screenWidth, screenHeight)

    // Calculate padding based on screen dimension, with minimum padding protection
    return max(baseSize, smallerDimension * scaleFactor)
  }

  // Legacy filter button function - keeping for reference but not using
  private func filterButton(for type: IncidentType, size: CGSize) -> some View {
    Button(action: {
      hapticImpact.impactOccurred()
      mapViewModel.toggleFilter(type)
    }) {
      ZStack {
        Circle()
          .fill(mapViewModel.selectedFilters.contains(type) ? type.color : Color.gray.opacity(0.5))
          .frame(width: 35, height: 35)

        Text(type.emoji)
          .font(.system(size: 20))
      }
    }
  }
}

// Helper extension to estimate text width (simplistic)
extension String {
  func widthOfString(usingFont font: UIFont) -> CGFloat {
    let fontAttributes = [NSAttributedString.Key.font: font]
    let size = self.size(withAttributes: fontAttributes)
    return size.width
  }
}

// MARK: - Tutorial View Controller
/// UIKit view controller to present the tutorial overlay
class TutorialViewController: UIViewController {
  private var onDismiss: (() -> Void)?
  
  init(onDismiss: @escaping () -> Void) {
    self.onDismiss = onDismiss
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Create a binding that dismisses the view controller when set to false
    let binding = Binding<Bool>(
      get: { true },
      set: { [weak self] newValue in
        if !newValue {
          self?.handleDismiss()
        }
      }
    )
    
    // Create the SwiftUI tutorial view with the binding
    let tutorialView = TutorialOverlayView(isPresented: binding)
    let hostingController = UIHostingController(rootView: tutorialView)
    hostingController.view.backgroundColor = .clear
    
    // Add as child view controller
    addChild(hostingController)
    view.addSubview(hostingController.view)
    hostingController.view.frame = view.bounds
    hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostingController.didMove(toParent: self)
  }
  
  @objc private func handleDismiss() {
    dismiss(animated: true) { [weak self] in
      self?.onDismiss?()
    }
  }
}

struct MainTabView_Previews: PreviewProvider {
  static var previews: some View {
    MainTabView()
      .environmentObject(NetworkMonitor())
  }
}

#if DEBUG
  // ... existing code ...
#endif

// MARK: - Full Screen or Sheet Helper
extension View {
  /// Presents HelpView as a full screen cover on iOS16+
  @ViewBuilder
  func fullScreenOrSheet<Content: View>(
    isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    fullScreenCover(isPresented: isPresented) {
      content()
        .edgesIgnoringSafeArea(.all)
    }
    /*
    // Legacy fallback for iOS 13 retained for reference; with deployment target 16 this will never compile.
    sheet(isPresented: isPresented) {
        content()
            .frame(maxHeight: .infinity) // Encourage full height
            .edgesIgnoringSafeArea(.all) // Still ignore safe area within sheet
    }
    */
  }
}

