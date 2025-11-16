import SwiftUI
import StoreKit

struct ZipCodePurchaseView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var premiumManager = PremiumManager.shared
  @StateObject private var authManager = AuthenticationManager.shared
  
  @State private var zipCodeInput = ""
  @State private var showError = false
  @State private var errorMessage = ""
  
  var body: some View {
    NavigationView {
      NoBounceScrollView {
        VStack(spacing: 24) {
          Spacer().frame(height: 12)
            // Header
            VStack(spacing: 12) {
              Image(systemName: "map.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(DPUTheme.colors.electricBlue)
              
              Text("Unlock Zip Codes")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
              
              Text("Get permanent access to videos in specific areas")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Currently unlocked areas
            if let profile = authManager.currentUserProfile {
              DPUCard {
                VStack(alignment: .leading, spacing: 12) {
                  Text("Your Unlocked Areas")
                    .font(.headline)
                    .foregroundColor(.white)
                  
                  Divider().background(Color.gray)
                  
                  // Home zip
                  HStack {
                    Image(systemName: "house.fill")
                      .foregroundColor(.green)
                    Text("\(profile.originalZipCode)")
                      .foregroundColor(.white)
                    Spacer()
                    Text("Home")
                      .font(.caption)
                      .foregroundColor(.gray)
                  }
                  
                  // Purchased zips
                  if !profile.purchasedZipCodes.isEmpty {
                    ForEach(profile.purchasedZipCodes, id: \.self) { zipCode in
                      HStack {
                        Image(systemName: "checkmark.circle.fill")
                          .foregroundColor(.blue)
                        Text(zipCode)
                          .foregroundColor(.white)
                        Spacer()
                        Text("Unlocked")
                          .font(.caption)
                          .foregroundColor(.blue)
                      }
                    }
                  }
                  
                  // Premium status
                  if profile.isPremium {
                    HStack {
                      Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                      Text("All Areas")
                        .foregroundColor(.yellow)
                      Spacer()
                      Text("Premium")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    }
                    .padding(.top, 8)
                  }
                }
              }
            }
            
            // Purchase new zip code section
            if let profile = authManager.currentUserProfile, !profile.isPremium {
              DPUCard {
                VStack(alignment: .leading, spacing: 16) {
                  Text("Unlock a New Area")
                    .font(.headline)
                    .foregroundColor(.white)
                  
                  Text("Enter a zip code to unlock videos from that area permanently")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                  
                  // Zip code input
                  TextField("Enter Zip Code", text: $zipCodeInput)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .keyboardType(.numberPad)
                    .onChange(of: zipCodeInput) { newValue in
                      // Limit to 5 digits
                      if newValue.count > 5 {
                        zipCodeInput = String(newValue.prefix(5))
                      }
                      // Filter non-numeric
                      zipCodeInput = newValue.filter { "0123456789".contains($0) }
                    }
                  
                  // Purchase button
                  Button(action: {
                    purchaseZipCode()
                  }) {
                    HStack {
                      if premiumManager.isLoading {
                        ProgressView()
                          .progressViewStyle(CircularProgressViewStyle(tint: .white))
                      } else {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock for $0.99")
                          .fontWeight(.semibold)
                      }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(zipCodeInput.count == 5 ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                  }
                  .disabled(zipCodeInput.count != 5 || premiumManager.isLoading)
                  
                  Text("One-time purchase • Permanent access")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
              }
            }
            
            // Or upgrade to premium
            if let profile = authManager.currentUserProfile, !profile.isPremium {
              VStack(spacing: 12) {
                Text("Or Get Unlimited Access")
                  .font(.subheadline)
                  .foregroundColor(.gray)
                
                Button(action: {
                  // Navigate to premium view
                  NotificationCenter.default.post(name: NSNotification.Name("ShowPremiumView"), object: nil)
                  dismiss()
                }) {
                  HStack {
                    Image(systemName: "star.fill")
                    Text("Upgrade to Premium")
                      .fontWeight(.semibold)
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(
                    LinearGradient(
                      gradient: Gradient(colors: [Color.purple, Color.blue]),
                      startPoint: .leading,
                      endPoint: .trailing
                    )
                  )
                  .foregroundColor(.white)
                  .cornerRadius(10)
                }
                
                Text("Watch videos from all areas • $4.99/month")
                  .font(.caption)
                  .foregroundColor(.gray)
              }
              .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .foregroundColor(.white)
        }
      }
    }
    .dpuBackground()
    .preferredColorScheme(.dark)
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
    .alert("Success!", isPresented: $premiumManager.purchaseSuccess) {
      Button("OK") {
        dismiss()
      }
    } message: {
      let zipCode = premiumManager.zipCodeBeingPurchased ?? zipCodeInput
      if !zipCode.isEmpty {
        Text("You now have access to videos in zip code \(zipCode)!")
      }
    }
  }
  
  private func purchaseZipCode() {
    // Validate
    guard zipCodeInput.count == 5 else {
      errorMessage = "Please enter a valid 5-digit zip code"
      showError = true
      return
    }
    
    // Check if already unlocked
    if let profile = authManager.currentUserProfile {
      if profile.originalZipCode == zipCodeInput {
        errorMessage = "This is your home zip code - already unlocked!"
        showError = true
        return
      }
      
      if profile.purchasedZipCodes.contains(zipCodeInput) {
        errorMessage = "You already have access to this zip code!"
        showError = true
        return
      }
      
      if profile.isPremium {
        errorMessage = "You have Premium - all zip codes are already unlocked!"
        showError = true
        return
      }
    }
    
    // Purchase the zip code
    Task {
      await premiumManager.purchaseZipCode(zipCodeInput)
      
      // Check for errors
      if let error = premiumManager.purchaseError {
        await MainActor.run {
          errorMessage = error
          showError = true
        }
      }
    }
  }
}

