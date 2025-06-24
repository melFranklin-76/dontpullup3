import StoreKit
import SwiftUI

struct PremiumView: View {
  @Environment(\.presentationMode) var presentationMode
  @StateObject private var premiumManager = PremiumManager.shared
  @State private var showAlert = false

  var body: some View {
    ZStack {
      // Background
      Color.black.opacity(0.9).edgesIgnoringSafeArea(.all)

      VStack(spacing: 25) {
        // Header
        HStack {
          Spacer()
          Button(action: {
            presentationMode.wrappedValue.dismiss()
          }) {
            Text("Close")
              .foregroundColor(.white)
              .padding(.trailing, 20)
          }
        }

        // Star icon
        Image(systemName: "star.fill")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 80, height: 80)
          .foregroundColor(.yellow)

        // Title
        Text("Premium Upgrade")
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.white)

        Text("Unlock full access to incidents across all zip codes")
          .font(.body)
          .foregroundColor(.white.opacity(0.8))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 20)

        // Features list
        VStack(alignment: .leading, spacing: 15) {
          FeatureRow(icon: "mappin.and.ellipse", text: "View incidents from any location")
          FeatureRow(icon: "mappin.circle", text: "Change your zip code anytime")
          FeatureRow(icon: "bell", text: "Get notifications from multiple areas")
          FeatureRow(icon: "dollarsign.circle", text: "One-time purchase, no subscription")
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)

        Spacer()

        // Purchase button
        Button(action: {
          if premiumManager.products.isEmpty {
            premiumManager.purchaseError = "Cannot connect to App Store. Please try again later."
            showAlert = true
          } else {
            premiumManager.purchasePremium()
          }
        }) {
          HStack {
            if premiumManager.isLoading {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
              Text("Upgrade Now - $0.99")
                .fontWeight(.bold)
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(Color.yellow)
          .foregroundColor(.black)
          .cornerRadius(12)
        }
        .padding(.horizontal, 20)
        .disabled(premiumManager.isLoading)

        // Restore button
        Button(action: {
          premiumManager.restorePurchases()
        }) {
          Text("Restore Purchases")
            .foregroundColor(.blue)
        }
        .padding(.bottom, 20)
        .disabled(premiumManager.isLoading)
      }
      .padding()
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
        presentationMode.wrappedValue.dismiss()
      }
    }
    .onAppear {
      premiumManager.fetchProducts()  // Refresh products when view appears
    }
  }
}

struct FeatureRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 15) {
      Image(systemName: icon)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)
        .foregroundColor(.yellow)

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
