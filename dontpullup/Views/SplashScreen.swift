import MapKit
import SwiftUI

// Map styling extension is now the single implementation
extension View {
  func withMapStyle() -> some View {
    self.preferredColorScheme(.dark)
      .background(Color.black)
  }
}

struct SplashScreen: View {
  @EnvironmentObject private var authState: AuthState
  @EnvironmentObject private var networkMonitor: NetworkMonitor
  @State private var isLoading = true
  @State private var scale = 0.7
  @State private var opacity = 0.0

  var body: some View {
    GeometryReader { geometry in
      ZStack {  // Background ZStack
        // Background Image
        Image("welcome_background")
          .resizable()
          .aspectRatio(contentMode: .fill)
          .edgesIgnoringSafeArea(.all)

        // Semi-transparent overlay
        Color.black.opacity(0.7)
          .edgesIgnoringSafeArea(.all)

        // Content with safe area padding
        VStack {
          // Add top safe area padding
          Spacer().frame(height: geometry.safeAreaInsets.top)

          // Original ZStack content
          ZStack {
            // Only show splash content, controlled by RootView's isLoading
            SplashContent()
              .scaleEffect(scale)
              .opacity(opacity)
            // REMOVED mainContent logic from here
          }
          .padding(.top, 20)  // Ensure content doesn't crowd top of screen

          // Add bottom safe area padding
          Spacer().frame(height: geometry.safeAreaInsets.bottom)
        }
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      // Keep onAppear logic for animation
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        // RootView controls isLoading, so we don't set it here
        // Let RootView handle dismissal after its delay
      }
      withAnimation(.easeOut(duration: 0.7)) {
        scale = 1.0
        opacity = 1.0
      }
    }
  }
}

// Helper Views
private struct SplashContent: View {
  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)

      VStack(spacing: size * 0.08) {
        // App Logo/Title - Adaptive sizing
        VStack(spacing: size * 0.03) {
          Text("DON'T PULL UP")
            .font(.system(size: size * 0.09, weight: .bold))
            .foregroundColor(.yellow)
            .tracking(2.0)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

          Text("ON GRANDMA!")
            .font(.custom("BlackOpsOne-Regular", size: size * 0.07))
            .foregroundColor(DPUTheme.colors.alertRed)
            .tracking(1.0)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            .rotationEffect(.degrees(-15))
        }
      }
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
  }
}

// Renamed to avoid conflict
private struct SplashLoadingView: View {
  var body: some View {
    ProgressView()
      .progressViewStyle(CircularProgressViewStyle(tint: .white))
      .scaleEffect(1.5)  // Increase size for better visibility
      .padding()
  }
}
