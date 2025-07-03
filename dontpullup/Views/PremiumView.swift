import FirebaseAuth
import StoreKit
import SwiftUI

struct PremiumView: View {
  @Environment(\.presentationMode) var presentationMode
  @Environment(\.dismiss) private var dismiss
  @StateObject private var premiumManager = PremiumManager.shared
  @State private var showAlert = false
  @State private var showThankYouView = false
  @State private var starScale: CGFloat = 1.0

  var body: some View {
    ZStack {
      // Background
      Color.black.opacity(0.9).ignoresSafeArea()

      VStack(spacing: 25) {
        // Header with close button
        HStack {
          Spacer()
          Button(action: {
            dismiss()
          }) {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .foregroundColor(.white.opacity(0.7))
              .padding(.trailing, 20)
              .padding(.top, 10)
          }
          .accessibilityLabel("Close")
        }

        // Star icon with animation
        Image(systemName: "star.fill")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 80, height: 80)
          .foregroundColor(.yellow)
          .shadow(color: .yellow.opacity(0.5), radius: 10)
          .scaleEffect(starScale)
          .onAppear {
            // Create a pulsing animation that works on iOS 15+
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
              starScale = 1.1
            }
          }

        // Title with improved styling
        Text("Premium Upgrade")
          .font(.system(size: 32, weight: .bold, design: .rounded))
          .foregroundColor(.white)

        // Subtitle
        Text("Unlock full access to incidents across all zip codes")
          .font(.headline)
          .foregroundColor(.white.opacity(0.8))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 20)
          .padding(.bottom, 10)

        // Features list with improved styling
        VStack(alignment: .leading, spacing: 18) {
          PremiumFeatureRow(icon: "mappin.and.ellipse", text: "View incidents from any location")
          PremiumFeatureRow(icon: "mappin.circle", text: "Change your zip code anytime")
          PremiumFeatureRow(icon: "bell", text: "Get notifications from multiple areas")
          PremiumFeatureRow(icon: "dollarsign.circle", text: "One-time purchase, no subscription")
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15)
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
        .padding(.horizontal, 20)

        Spacer()

        // Price display
        Group {
          if let product = premiumManager.products.first {
            Text("Unlock Premium for \(product.displayPrice)")
              .font(.headline)
              .foregroundColor(.white)
              .padding(.bottom, 5)
          } else {
            // Check if TestFlight or debug build
            #if DEBUG
              VStack(spacing: 5) {
                Text("Debug Build - Free Premium Access")
                  .font(.headline)
                  .foregroundColor(.green)
                Text("(Test mode enabled)")
                  .font(.caption)
                  .foregroundColor(.green.opacity(0.7))
              }
              .padding(.bottom, 5)
            #else
              if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
                VStack(spacing: 5) {
                  Text("TestFlight Beta - Free Premium Access")
                    .font(.headline)
                    .foregroundColor(.yellow)
                  Text("(No charge for beta testers)")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.7))
                }
                .padding(.bottom, 5)
              } else {
              Text("Unlock Premium for $0.99")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 5)
              }
            #endif
          }
        }

        // Purchase button with improved styling
        Button(action: {
          print("[PremiumView] Purchase button tapped")
          Task {
            if let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous {
              print("[PremiumView] Registered user initiating purchase - calling purchasePremium()")
              await premiumManager.purchasePremium()
              print("[PremiumView] purchasePremium() completed")
            } else {
              print("[PremiumView] Anonymous user cannot purchase - show sign in prompt")
              premiumManager.purchaseError = "Please sign in to make purchases"
              showAlert = true
            }
          }
        }) {
          HStack {
            if premiumManager.isLoading {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                .scaleEffect(1.2)
            } else {
              // Check if TestFlight for button text
              #if DEBUG
                Text("Activate Free Premium (Debug)")
                  .fontWeight(.bold)
                  .font(.title3)
              #else
                if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
                  Text("Activate Free Premium (TestFlight)")
                    .fontWeight(.bold)
                    .font(.title3)
            } else {
              Text("Upgrade Now")
                .fontWeight(.bold)
                .font(.title3)
                }
              #endif
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(
            LinearGradient(
              gradient: Gradient(colors: [Color.yellow, Color.yellow.opacity(0.8)]),
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .foregroundColor(.black)
          .cornerRadius(16)
          .shadow(color: Color.yellow.opacity(0.5), radius: 5)
        }
        .padding(.horizontal, 20)
        .disabled(premiumManager.isLoading || premiumManager.isPremium)

        // Already purchased message
        if premiumManager.isPremium {
          Text("You already have Premium access!")
            .foregroundColor(.green)
            .padding(.top, 10)
        }

        // Restore button with improved styling
        Button(action: {
          Task {
            await premiumManager.restorePurchases()
          }
        }) {
          Text("Restore Purchases")
            .foregroundColor(.blue)
            .padding(.vertical, 10)
        }
        .padding(.bottom, 20)
        .disabled(premiumManager.isLoading)

        // Privacy note
        Text("All purchases are processed securely by Apple")
          .font(.caption)
          .foregroundColor(.gray)
          .padding(.bottom, 10)
      }
      .padding()

      // Thank you overlay when purchase is successful
      if showThankYouView {
        Color.black.opacity(0.9)
          .ignoresSafeArea()
          .overlay(
            VStack(spacing: 25) {
              Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.green)

              Text("Thank You!")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)

              Text("Premium features are now unlocked")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))

              Button(action: {
                dismiss()
              }) {
                Text("Continue")
                  .fontWeight(.bold)
                  .frame(maxWidth: .infinity)
                  .frame(height: 56)
                  .background(Color.green)
                  .foregroundColor(.white)
                  .cornerRadius(16)
              }
              .padding(.horizontal, 40)
              .padding(.top, 20)
            }
          )
          .transition(.opacity)
          .zIndex(2)
      }
    }
    .alert(isPresented: $showAlert) {
      Alert(
        title: Text("Purchase Error"),
        message: Text(premiumManager.purchaseError ?? "An unknown error occurred"),
        dismissButton: .default(Text("OK")) {
          premiumManager.resetPurchaseState()
        }
      )
    }
    .onReceive(premiumManager.$purchaseError) { error in
      if error != nil {
        showAlert = true
      }
    }
    .onReceive(premiumManager.$purchaseSuccess) { success in
      if success {
        withAnimation(.easeInOut(duration: 0.5)) {
          showThankYouView = true
        }
        // Dismiss after showing thank you for 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
          dismiss()
        }
      }
    }
    .task {
      // Load products when the view appears
      await premiumManager.fetchProducts()
      await premiumManager.checkPurchaseStatus()
    }
    .onAppear {
      print("[PremiumView] didAppear – current isPremium = \(premiumManager.isPremium)")
      print(
        "[PremiumView] Button disabled state: \(premiumManager.isLoading || premiumManager.isPremium)"
      )
    }
  }
}

struct PremiumFeatureRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 15) {
      Image(systemName: icon)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)
        .foregroundColor(.yellow)
        .shadow(color: .yellow.opacity(0.5), radius: 3)

      Text(text)
        .font(.body)
        .foregroundColor(.white)

      Spacer()
    }
  }
}

#Preview {
  PremiumView()
}
