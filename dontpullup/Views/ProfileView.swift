import FirebaseAuth
import FirebaseFirestore
import StoreKit
import SwiftUI

struct ProfileView: View {
  @EnvironmentObject private var authState: AuthState
  @Environment(\.dismiss) private var dismiss
  @State private var showSignOutConfirmation = false
  @State private var showDeleteAccountConfirmation = false
  @State private var showDeletionError = false
  @State private var deletionErrorMessage = ""
  @State private var isDeletingAccount = false
  @State private var showDeletionSuccess = false

  // Add zip code editing state
  @State private var isEditingZipCode = false
  @State private var newZipCode = ""
  @State private var isUpdatingZipCode = false
  @State private var zipCodeError = ""
  @State private var showZipCodeError = false

  // Computed property for original zip code
  private var originalZipCode: String {
    return authManager.currentUserProfile?.originalZipCode ?? ""
  }

  // Premium upgrade state
  @State private var showPremiumUpgrade = false
  @State private var showPurchaseError = false
  @State private var purchaseErrorMessage = ""
  @State private var showPremiumSuccess = false

  // Access managers
  @StateObject private var premiumManager = PremiumManager.shared
  @ObservedObject private var authManager = AuthenticationManager.shared

  // Computed property for premium status
  private var isPremium: Bool {
    return authManager.currentUserProfile?.isPremium ?? false
  }

  var body: some View {
    // Content wrapped in the universal scroll view
    NoBounceScrollView {
      VStack(spacing: 20) {
        Spacer().frame(height: 8)
        // Profile header
        DPUCard {
          VStack(spacing: 16) {
            // Profile icon
            Image(systemName: "person.circle.fill")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 80, height: 80)
              .foregroundColor(.white)

            // User email
            if let email = authState.currentUser?.email {
              Text(email)
                .font(.headline)
                .foregroundColor(.white)
            } else {
              Text("Anonymous User")
                .font(.headline)
                .foregroundColor(.white)
            }

            // User ID (shortened for display)
            if let uid = authState.currentUser?.uid {
              Text("ID: \(String(uid.prefix(8)))...")
                .font(.caption)
                .foregroundColor(.gray)
            }

            // Premium badge if applicable
            if isPremium {
              HStack {
                Image(systemName: "star.fill")
                  .foregroundColor(.yellow)
                Text("Premium Member")
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundColor(.yellow)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(Color.black.opacity(0.6))
              .cornerRadius(15)
            }
          }
        }

        // Premium upgrade card (only show if not premium)
        if !isPremium {
          DPUCard {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Image(systemName: "star.fill")
                  .foregroundColor(.yellow)
                Text("Premium Features")
                  .font(.headline)
                  .foregroundColor(.white)
                Spacer()
              }
              .padding(.top, 4)

              Text(
                "Upgrade to premium for only $0.99 to unlock changing between different zip codes and viewing incidents from anywhere."
              )
              .font(.subheadline)
              .foregroundColor(.white)
              .padding(.bottom, 4)

              Button(action: {
                showPremiumUpgrade = true
              }) {
                Text("Upgrade Now - $0.99")
                  .fontWeight(.semibold)
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.yellow)
                  .foregroundColor(.black)
                  .cornerRadius(8)
              }
            }
          }
        }

        // Zip code section
        DPUCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Your Location")
              .font(.headline)
              .foregroundColor(.white)
              .padding(.top, 4)

            Text("Enter your zip code to receive notifications about incidents in your area.")
              .font(.subheadline)
              .foregroundColor(.gray)
              .padding(.bottom, 4)

            // Current zip code display
            VStack(alignment: .leading, spacing: 8) {
              Text("Current Zip Code")
                .font(.caption)
                .foregroundColor(.gray)

              Text(authManager.currentUserProfile?.zipCode ?? "")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            }
            .padding(.bottom, 16)

            // Display unlocked zip codes
            if let profile = authManager.currentUserProfile {
              VStack(alignment: .leading, spacing: 12) {
                Text("Unlocked Areas")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundColor(.white)
                  .padding(.top, 8)

                // Home zip code (always unlocked)
                HStack(spacing: 12) {
                  Image(systemName: "house.fill")
                    .foregroundColor(.green)
                    .frame(width: 24)
                  
                  VStack(alignment: .leading, spacing: 2) {
                    Text(profile.originalZipCode)
                      .font(.system(size: 16, weight: .semibold))
                      .foregroundColor(.white)
                    Text("Home Area")
                      .font(.caption)
                      .foregroundColor(.gray)
                  }
                  
                  Spacer()
                  
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                // Purchased zip codes
                if !profile.purchasedZipCodes.isEmpty {
                  ForEach(profile.purchasedZipCodes, id: \.self) { zipCode in
                    HStack(spacing: 12) {
                      Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                      
                      VStack(alignment: .leading, spacing: 2) {
                        Text(zipCode)
                          .font(.system(size: 16, weight: .semibold))
                          .foregroundColor(.white)
                        Text("Purchased Area")
                          .font(.caption)
                          .foregroundColor(.gray)
                      }
                      
                      Spacer()
                      
                      Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                  }
                }

                // Premium badge showing unlimited access
                if profile.isPremium {
                  HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                      .foregroundColor(.yellow)
                      .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                      Text("All Areas")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.yellow)
                      Text("Premium Unlimited Access")
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "infinity")
                      .foregroundColor(.yellow)
                  }
                  .padding(12)
                  .background(Color.yellow.opacity(0.1))
                  .cornerRadius(8)
                } else {
                  // Show unlock more option for non-premium users
                  Button(action: {
                    // Navigate to zip code purchase view
                    NotificationCenter.default.post(name: NSNotification.Name("ShowZipCodePurchase"), object: nil)
                  }) {
                    HStack(spacing: 12) {
                      Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                      
                      Text("Unlock More Areas")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                      
                      Spacer()
                      
                      Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                  }
                }
              }
              .padding(.bottom, 8)
            }

            if !isPremium {
              Text("Premium upgrade required to change your zip code")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 8)
            }

            TextField("Zip Code", text: $newZipCode)
              .padding()
              .background(Color.white.opacity(0.1))
              .cornerRadius(8)
              .foregroundColor(.white)
              .keyboardType(.numberPad)
              .onChange(of: newZipCode) { newValue in
                // Limit to 5 digits
                if newValue.count > 5 {
                  newZipCode = String(newValue.prefix(5))
                }

                // Filter non-numeric characters
                newZipCode = newValue.filter { "0123456789".contains($0) }
              }
              .disabled(!isPremium && newZipCode == originalZipCode)  // Disable if not premium and equals original
              .opacity(!isPremium ? 0.6 : 1.0)
              .padding(.vertical, 4)

            Button(action: {
              if isEditingZipCode {
                updateZipCode()
              } else {
                startEditingZipCode()
              }
            }) {
              if isUpdatingZipCode {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
              } else {
                Text(isEditingZipCode ? "Update Location" : "Edit Zip Code")
                  .fontWeight(.semibold)
              }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background((!isPremium && newZipCode != originalZipCode) ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(
              !isPremium && newZipCode != originalZipCode || isUpdatingZipCode
                || (isEditingZipCode && newZipCode.isEmpty)
            )
            .opacity(
              (!isPremium && newZipCode != originalZipCode) || isUpdatingZipCode
                || (isEditingZipCode && newZipCode.isEmpty) ? 0.6 : 1.0)
          }
        }

        // Account actions
        DPUCard {
          VStack(spacing: 16) {
            Button(action: {
              showSignOutConfirmation = true
            }) {
              Text("Sign Out")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            if !authState.isAnonymous {
              Button(action: {
                if !isDeletingAccount {
                  showDeleteAccountConfirmation = true
                }
              }) {
                Text("Delete Account")
                  .fontWeight(.semibold)
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.gray.opacity(0.3))
                  .foregroundColor(.white)
                  .cornerRadius(8)
              }
              .disabled(isDeletingAccount)
            }
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .dpuBackground()
    .alert("Sign Out", isPresented: $showSignOutConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Sign Out", role: .destructive) {
        authState.signOut()

        // Force immediate UI update while Firebase callback propagates
        authState.isAuthenticated = false
        authState.currentUser = nil

        // Immediately close the Profile sheet
        dismiss()
      }
    } message: {
      Text("Are you sure you want to sign out?")
    }
    .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Permanently", role: .destructive) {
        deleteUserAccount()
      }
    } message: {
      Text(
        "This will permanently delete your account and ALL associated data including:\n\n• Your profile information\n• All pins you've created\n• All video reports\n• Your notification preferences\n\nThis action cannot be undone. Are you sure you want to continue?"
      )
    }
    .alert("Account Deletion Error", isPresented: $showDeletionError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(deletionErrorMessage)
    }
    .alert("Account Deleted Successfully", isPresented: $showDeletionSuccess) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(
        "Your account and all associated data have been permanently deleted from our servers. Thank you for using Don't Pull Up."
      )
    }
    .alert("Zip Code Error", isPresented: $showZipCodeError) {
      Button("OK") {}
    } message: {
      Text(zipCodeError)
    }
    .alert("Purchase Error", isPresented: $showPurchaseError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(purchaseErrorMessage)
    }
    .alert("Premium Upgrade Successful", isPresented: $showPremiumSuccess) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(
        "You now have premium access! You can now change your zip code to view incidents from anywhere."
      )
    }
    .sheet(isPresented: $showPremiumUpgrade) {
      PremiumUpgradeView(showSuccess: $showPremiumSuccess)
        .preferredColorScheme(.dark)
    }
    .onAppear {
      // Set current zip code from AuthenticationManager
      if let currentZip = authManager.currentUserProfile?.zipCode {
        newZipCode = currentZip
      }
    }
  }

  // Method to start editing zip code
  private func startEditingZipCode() {
    // Set the text field to the current zip code value
    newZipCode = authManager.currentUserProfile?.zipCode ?? ""
    isEditingZipCode = true
  }

  // Method to update zip code
  private func updateZipCode() {
    // Basic validation
    if newZipCode.isEmpty {
      zipCodeError = "Please enter a zip code"
      showZipCodeError = true
      return
    }

    if newZipCode.count != 5 {
      zipCodeError = "Zip code must be 5 digits"
      showZipCodeError = true
      return
    }

    // Show loading state
    isUpdatingZipCode = true

    // Use AuthenticationManager's method which handles premium validation
    #if DEBUG
    print("[ProfileView] Attempting to update zip code to: \(newZipCode)")
    print("[ProfileView] Current user premium status: \(isPremium)")
    #endif

    Task {
      do {
        #if DEBUG
        print("[ProfileView] Calling authManager.updateZipCode(\(newZipCode))")
        #endif
        try await authManager.updateZipCode(newZipCode)

        // Update UI on main thread
        await MainActor.run {
          #if DEBUG
          print("[ProfileView] Zip code update successful")
          print("[ProfileView] New current zip code: \(authManager.currentUserProfile?.zipCode ?? "unknown")")
          #endif
          // Update the local state to reflect the new zip code
          if let updatedZip = authManager.currentUserProfile?.zipCode {
            newZipCode = updatedZip
          }
          isEditingZipCode = false
          isUpdatingZipCode = false
        }
      } catch {
        // Handle error
        await MainActor.run {
          zipCodeError = error.localizedDescription
          showZipCodeError = true
          isUpdatingZipCode = false
        }
      }
    }
  }

  // Method to delete user account
  private func deleteUserAccount() {
    guard let user = authState.currentUser, !authState.isAnonymous else {
      deletionErrorMessage = "Cannot delete anonymous account"
      showDeletionError = true
      return
    }

    // Set deleting state
    isDeletingAccount = true

    // Delete user data from Firestore first
    Task {
      do {
        // Delete user's pins
        try await deleteUserPins(userId: user.uid)

        // Delete user document
        try await Firestore.firestore().collection("users").document(user.uid).delete()

        // Delete the Firebase Auth account
        try await user.delete()

        // Show success message
        await MainActor.run {
          isDeletingAccount = false
          showDeletionSuccess = true

          // After a short delay, dismiss the profile view
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            authState.isAuthenticated = false
            authState.currentUser = nil
            dismiss()
          }
        }
      } catch {
        // Show error
        await MainActor.run {
          isDeletingAccount = false
          deletionErrorMessage =
            "Failed to delete account: \(error.localizedDescription). You may need to re-authenticate."
          showDeletionError = true
        }
      }
    }
  }

  // Helper to delete user's pins
  private func deleteUserPins(userId: String) async throws {
    let db = Firestore.firestore()

    // Query for pins created by this user
    let querySnapshot = try await db.collection("pins")
      .whereField("userId", isEqualTo: userId)
      .getDocuments()

    // Delete each pin document
    for document in querySnapshot.documents {
      try await document.reference.delete()
    }
  }
}

// Premium Upgrade View
struct PremiumUpgradeView: View {
  @StateObject private var premiumManager = PremiumManager.shared
  @StateObject private var authManager = AuthenticationManager.shared
  @Environment(\.dismiss) private var dismiss
  @Binding var showSuccess: Bool
  @State private var showPurchaseError = false

  private var isPremium: Bool {
    return authManager.currentUserProfile?.isPremium ?? false
  }

  var body: some View {
    NavigationView {
      NoBounceScrollView {
        VStack(spacing: 24) {
          Spacer().frame(height: 8)
          // Premium header
          VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
              .resizable()
              .scaledToFit()
              .frame(width: 80)
              .foregroundColor(.yellow)
              .padding(.top)

            Text("Premium Upgrade")
              .font(.title2)
              .fontWeight(.bold)
              .foregroundColor(.white)

            Text("Unlock full access to incidents across all zip codes")
              .font(.subheadline)
              .foregroundColor(.gray)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }

          // Feature list
          DPUCard {
            VStack(alignment: .leading, spacing: 16) {
              FeatureRow(icon: "mappin.and.ellipse", text: "View incidents from any location")
              FeatureRow(icon: "location.fill", text: "Change your zip code anytime")
              FeatureRow(icon: "bell.fill", text: "Get notifications from multiple areas")
              FeatureRow(icon: "lock.open.fill", text: "One-time purchase, no subscription")
            }
            .padding(.vertical, 8)
          }

          Spacer(minLength: 20)

          // Purchase button
          Button(action: {
            #if targetEnvironment(simulator)
              // In simulator, always use the test flow regardless of products
              Task {
                await premiumManager.simulatePurchaseForTesting()
              }
            #else
              if premiumManager.products.isEmpty {
                premiumManager.purchaseError =
                  "Cannot connect to App Store. Please check your connection or try again later."
                showPurchaseError = true
              } else {
                Task {
                  await premiumManager.purchasePremium()
                }
              }
            #endif
          }) {
            if premiumManager.isLoading {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .padding()
            } else {
              Text("Upgrade Now - $0.99")
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.yellow)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
            }
          }
          .padding(.horizontal)
          .disabled(premiumManager.isLoading)

          // Restore purchases button
          Button(action: {
            Task {
              await premiumManager.restorePurchases()
            }
          }) {
            Text("Restore Purchases")
              .font(.subheadline)
              .foregroundColor(.blue)
          }
          .padding(.bottom)
          .disabled(premiumManager.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
      }
      .navigationBarItems(trailing: Button("Close") { dismiss() })
      .navigationBarTitle("", displayMode: .inline)
      .onChange(of: premiumManager.purchaseSuccess) { success in
        if success {
          showSuccess = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
            premiumManager.resetPurchaseState()
          }
        }
      }
      .onChange(of: premiumManager.purchaseError) { error in
        if error != nil {
          // Error is shown in alert below
          showPurchaseError = true
        }
      }
      .alert("Purchase Error", isPresented: $showPurchaseError) {
        Button("OK") {
          premiumManager.resetPurchaseState()
        }
      } message: {
        Text(premiumManager.purchaseError ?? "An unknown error occurred")
      }
      .onDisappear {
        premiumManager.resetPurchaseState()
      }
    }
    .dpuBackground()
  }
}

struct FeatureRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundColor(.yellow)
        .frame(width: 24)

      Text(text)
        .font(.body)
        .foregroundColor(.white)

      Spacer()
    }
    .padding(.horizontal)
  }
}

struct StatView: View {
  let title: String
  let value: String

  var body: some View {
    VStack(spacing: 8) {
      Text(value)
        .font(.title)
        .fontWeight(.bold)
        .foregroundColor(.white)

      Text(title)
        .font(.caption)
        .foregroundColor(.gray)
    }
    .frame(minWidth: 70)  // Ensure stat views have consistent width
  }
}

#Preview {
  ProfileView()
    .environmentObject(AuthState.shared)
}
