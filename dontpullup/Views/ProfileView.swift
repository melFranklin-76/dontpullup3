import FirebaseAuth
import FirebaseFirestore
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

  var body: some View {
    // Content wrapped in the universal scroll view
    NoBounceScrollView {
      VStack(spacing: 20) {
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
                Text("Update Location")
                  .fontWeight(.semibold)
              }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isUpdatingZipCode || (isEditingZipCode && newZipCode.isEmpty))
            .opacity(isUpdatingZipCode || (isEditingZipCode && newZipCode.isEmpty) ? 0.6 : 1.0)
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
      .padding()
    }
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
    .onAppear {
      loadUserProfile()
    }
  }

  // The rest of the methods stay the same

  // Method to load the user profile
  private func loadUserProfile() {
    // Check if we have a saved zip code for this user
    if let user = authState.currentUser {
      Task {
        do {
          let docRef = Firestore.firestore().collection("users").document(user.uid)
          let document = try await docRef.getDocument()

          if let data = document.data(),
            let zipCode = data["zipCode"] as? String
          {
            // Update UI on main thread
            await MainActor.run {
              self.newZipCode = zipCode
            }
          }
        } catch {
          print("Error loading user profile: \(error.localizedDescription)")
        }
      }
    }
  }

  // Method to start editing zip code
  private func startEditingZipCode() {
    isEditingZipCode = true
  }

  // Method to update zip code
  private func updateZipCode() {
    guard let user = authState.currentUser else {
      zipCodeError = "You need to be signed in to update your zip code"
      showZipCodeError = true
      return
    }

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

    // Update user profile in Firestore
    let userRef = Firestore.firestore().collection("users").document(user.uid)

    Task {
      do {
        try await userRef.setData(["zipCode": newZipCode], merge: true)

        // Update UI on main thread
        await MainActor.run {
          isEditingZipCode = false
          isUpdatingZipCode = false
        }
      } catch {
        // Handle error
        await MainActor.run {
          zipCodeError = "Failed to update: \(error.localizedDescription)"
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
