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
        Text("Choose your access level")
          .font(.headline)
          .foregroundColor(.white.opacity(0.8))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 20)
          .padding(.bottom, 10)

        // Option 1: Individual Zip Codes
        VStack(spacing: 16) {
          Text("Option 1: Individual Areas")
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.blue)

          ZStack {
            RoundedRectangle(cornerRadius: 16)
              .fill(Color.blue.opacity(0.1))
              .overlay(
                RoundedRectangle(cornerRadius: 16)
                  .stroke(Color.blue.opacity(0.3), lineWidth: 1)
              )

            VStack(alignment: .leading, spacing: 12) {
              PremiumFeatureRow(icon: "map.fill", text: "Unlock specific zip codes")
              PremiumFeatureRow(icon: "dollarsign.circle", text: "$0.99 per zip code")
              PremiumFeatureRow(icon: "checkmark.circle", text: "One-time purchase, keep forever")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
          }
          .padding(.horizontal, 20)

          ModernButton(
            title: "Unlock Zip Codes",
            systemImage: "map.fill",
            style: .primary
          ) {
            // Show zip code purchase view
            NotificationCenter.default.post(name: NSNotification.Name("ShowZipCodePurchase"), object: nil)
            dismiss()
          }
          .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
        
        // Divider
        Text("OR")
          .font(.headline)
          .foregroundColor(.gray)
        
        // Option 2: Premium Unlimited
        VStack(spacing: 16) {
          Text("Option 2: Premium Unlimited")
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.yellow)

          ZStack {
            RoundedRectangle(cornerRadius: 16)
              .fill(Color.yellow.opacity(0.1))
              .overlay(
                RoundedRectangle(cornerRadius: 16)
                  .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
              )

            VStack(alignment: .leading, spacing: 12) {
              PremiumFeatureRow(icon: "mappin.and.ellipse", text: "Watch videos from ALL areas")
              PremiumFeatureRow(icon: "mappin.circle", text: "Change your zip code anytime")
              PremiumFeatureRow(icon: "bell", text: "Notifications from multiple areas")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
          }
          .padding(.horizontal, 20)
        }

        Spacer()

        // Price display for premium unlimited
        Group {
          if let product = premiumManager.products.first(where: { $0.id == PremiumManager.premiumUnlimitedProductID }) {
            Text("\(product.displayPrice)")
              .font(.title2)
              .fontWeight(.bold)
              .foregroundColor(.yellow)
          } else {
            #if DEBUG
              Text("$4.99")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.yellow)
            #endif
          }
        }

        // Purchase button with modern styling
        ModernButton(
          title: premiumManager.isLoading ? "Processing..." : "Upgrade Now",
          systemImage: premiumManager.isLoading ? nil : "star.fill",
          style: .success
        ) {
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
        }
        .padding(.horizontal, 20)
        .disabled(premiumManager.isLoading || premiumManager.isPremium)

        // Already purchased message
        if premiumManager.isPremium {
          Text("You already have Premium access!")
            .foregroundColor(.green)
            .padding(.top, 10)
        }

        // Restore button with modern styling
        ModernButton(
          title: "Restore Purchases",
          systemImage: "arrow.clockwise",
          style: .secondary
        ) {
          Task {
            await premiumManager.restorePurchases()
          }
        }
        .padding(.horizontal, 20)
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

              ModernButton(
                title: "Continue",
                systemImage: "checkmark",
                style: .success
              ) {
                dismiss()
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
