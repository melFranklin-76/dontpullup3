import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftUI

struct DataDeletionView: View {
  @Environment(\.presentationMode) var presentationMode
  @EnvironmentObject var authState: AuthState
  @State private var isDeleting = false
  @State private var showConfirmation = false
  @State private var confirmationText = ""
  @State private var showSuccess = false
  @State private var showError = false
  @State private var errorMessage = ""

  private let requiredConfirmationText = "DELETE MY DATA"

  var body: some View {
    NavigationView {
      ScrollView(.vertical, showsIndicators: true) {
        VStack(spacing: 24) {
          // Warning header
          VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 60))
              .foregroundColor(.red)

            Text("Delete All Data")
              .font(.title)
              .fontWeight(.bold)
              .foregroundColor(.red)

            Text("This action cannot be undone")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .padding(.top)

          // What will be deleted
          DPUCard(backgroundColor: Color.red.opacity(0.1), cornerRadius: 12, useShadow: true) {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Image(systemName: "trash.fill")
                  .foregroundColor(.red)
                Text("Data to be permanently deleted:")
                  .font(.headline)
                  .fontWeight(.bold)
                Spacer()
              }

              VStack(alignment: .leading, spacing: 8) {
                dataItem("Your user account")
                dataItem("All pins you've created")
                dataItem("All videos you've uploaded")
                dataItem("Your profile information")
                dataItem("Your zip code and location data")
                dataItem("Your premium subscription status")
                dataItem("All app preferences and settings")
              }
            }
            .padding()
          }

          // Process explanation
          DPUCard(backgroundColor: Color.blue.opacity(0.1), cornerRadius: 12, useShadow: true) {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Image(systemName: "info.circle.fill")
                  .foregroundColor(.blue)
                Text("Deletion Process:")
                  .font(.headline)
                  .fontWeight(.bold)
                Spacer()
              }

              VStack(alignment: .leading, spacing: 8) {
                Text("1. All your pins will be removed from the map immediately")
                Text("2. Your videos will be deleted from cloud storage")
                Text("3. Your user account will be permanently deleted")
                Text("4. You will be signed out of the app")
                Text("5. This process takes 1-2 minutes to complete")
              }
              .font(.body)
            }
            .padding()
          }

          // Important notices
          DPUCard(backgroundColor: Color.orange.opacity(0.1), cornerRadius: 12, useShadow: true) {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Image(systemName: "bell.fill")
                  .foregroundColor(.orange)
                Text("Important Notices:")
                  .font(.headline)
                  .fontWeight(.bold)
                Spacer()
              }

              VStack(alignment: .leading, spacing: 8) {
                Text("• This deletion is immediate and irreversible")
                Text("• Other users will no longer see your pins")
                Text("• You can create a new account later if desired")
                Text("• Premium subscriptions should be canceled separately in App Store")
                Text("• Some anonymized analytics may be retained for legal compliance")
              }
              .font(.body)
            }
            .padding()
          }

          // Confirmation section
          if !showConfirmation {
            Button("Begin Data Deletion") {
              showConfirmation = true
            }
            .buttonStyle(RectangleButtonStyle(isSelected: false))
            .foregroundColor(.red)
          } else {
            // Confirmation text entry
            DPUCard(backgroundColor: Color.gray.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(spacing: 16) {
                Text("Type '\(requiredConfirmationText)' to confirm:")
                  .font(.headline)
                  .fontWeight(.bold)

                TextField("Type here...", text: $confirmationText)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
                  .autocapitalization(.allCharacters)
                  .disableAutocorrection(true)

                HStack(spacing: 16) {
                  Button("Cancel") {
                    showConfirmation = false
                    confirmationText = ""
                  }
                  .buttonStyle(RectangleButtonStyle(isSelected: false))
                  .foregroundColor(.gray)

                  Button("DELETE ALL DATA") {
                    deleteAllUserData()
                  }
                  .buttonStyle(
                    RectangleButtonStyle(isSelected: confirmationText == requiredConfirmationText)
                  )
                  .foregroundColor(.red)
                  .disabled(confirmationText != requiredConfirmationText || isDeleting)
                }
              }
              .padding()
            }
          }

          if isDeleting {
            VStack(spacing: 16) {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .red))
                .scaleEffect(1.5)

              Text("Deleting your data...")
                .font(.headline)
                .foregroundColor(.red)

              Text("Please don't close the app")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
          }
        }
        .padding(.horizontal)
      }
      .navigationTitle("Delete Data")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarItems(
        trailing:
          Button("Close") {
            presentationMode.wrappedValue.dismiss()
          }
          .disabled(isDeleting)
      )
    }
    .alert("Data Deleted Successfully", isPresented: $showSuccess) {
      Button("OK") {
        // Sign out and close
        try? Auth.auth().signOut()
        presentationMode.wrappedValue.dismiss()
      }
    } message: {
      Text("All your data has been permanently deleted. You have been signed out.")
    }
    .alert("Deletion Failed", isPresented: $showError) {
      Button("OK") {
        isDeleting = false
      }
    } message: {
      Text(errorMessage)
    }
  }

  private func dataItem(_ text: String) -> some View {
    HStack {
      Image(systemName: "minus.circle.fill")
        .foregroundColor(.red)
        .font(.caption)
      Text(text)
        .font(.body)
      Spacer()
    }
  }

  private func deleteAllUserData() {
    guard let currentUser = Auth.auth().currentUser else {
      errorMessage = "No user is currently signed in"
      showError = true
      return
    }

    isDeleting = true

    Task {
      do {
        let userId = currentUser.uid
        let db = Firestore.firestore()
        let storage = Storage.storage()

        // 1. Delete all user's pins and associated videos
        print("[DataDeletion] Deleting user pins...")
        let pinsQuery = db.collection("pins").whereField("userId", isEqualTo: userId)
        let pinsSnapshot = try await pinsQuery.getDocuments()

        for document in pinsSnapshot.documents {
          let pinData = document.data()

          // Delete associated video if exists
          if let videoURL = pinData["videoURL"] as? String, !videoURL.isEmpty {
            let videoRef = storage.reference(forURL: videoURL)
            try? await videoRef.delete()
            print("[DataDeletion] Deleted video: \(videoURL)")
          }

          // Delete pin document
          try await document.reference.delete()
          print("[DataDeletion] Deleted pin: \(document.documentID)")
        }

        // 2. Delete user profile document if exists
        print("[DataDeletion] Deleting user profile...")
        try await db.collection("users").document(userId).delete()

        // 3. Delete any flagged video reports by this user
        print("[DataDeletion] Deleting flag reports...")
        let flagsQuery = db.collection("flaggedVideos").whereField("videoId", isEqualTo: userId)
        let flagsSnapshot = try await flagsQuery.getDocuments()

        for document in flagsSnapshot.documents {
          try await document.reference.delete()
        }

        // 4. Delete user account from Firebase Auth
        print("[DataDeletion] Deleting user account...")
        try await currentUser.delete()

        // 5. Clear local data
        UserDefaults.standard.hasAcceptedContentGuidelines = false
        UserDefaults.standard.removeObject(forKey: "userDeclinedLocationPermissions")

        await MainActor.run {
          isDeleting = false
          showSuccess = true
        }

        print("[DataDeletion] All user data deleted successfully")

      } catch {
        print("[DataDeletion] Error deleting user data: \(error.localizedDescription)")
        await MainActor.run {
          isDeleting = false
          errorMessage = "Failed to delete data: \(error.localizedDescription)"
          showError = true
        }
      }
    }
  }
}

#Preview {
  DataDeletionView()
    .environmentObject(AuthState.shared)
}
