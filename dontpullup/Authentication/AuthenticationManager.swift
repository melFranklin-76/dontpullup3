import Combine
@preconcurrency import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

@MainActor
final class AuthenticationManager: ObservableObject {
  @Published var currentUser: User?
  @Published var currentUserProfile: UserProfile?
  @Published var isAuthenticated = false
  @Published var errorMessage: String?

  static let shared = AuthenticationManager()
  private var handle: AuthStateDidChangeListenerHandle?
  private let db = Firestore.firestore()

  // Store FCM token temporarily until user is authenticated
  private var pendingFCMToken: String?

  // Track token refresh attempts
  private var tokenRefreshTimer: Timer?
  private var tokenRefreshAttempts = 0

  // Track last zip code update to prevent rapid updates
  private var lastZipCodeUpdate: Date?

  init() {
    setupAuthStateListener()
    setupPremiumStatusListener()

    // Setup periodic token refresh check
    setupTokenRefreshCheck()
  }

  private func setupTokenRefreshCheck() {
    // Check token validity every 5 minutes
    tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        await self?.refreshAuthTokenIfNeeded()
      }
    }
  }

  private func refreshAuthTokenIfNeeded() async {
    guard let currentUser = Auth.auth().currentUser else {
      print("AuthenticationManager: No current user to refresh token")
      return
    }

    do {
      // Force token refresh
      let _ = try await currentUser.getIDToken(forcingRefresh: true)
      print("AuthenticationManager: Successfully refreshed auth token")
      tokenRefreshAttempts = 0
    } catch {
      tokenRefreshAttempts += 1
      print(
        "AuthenticationManager: Failed to refresh token (attempt \(tokenRefreshAttempts)): \(error.localizedDescription)"
      )

      // If we've failed multiple times, try to reauthenticate
      if tokenRefreshAttempts >= 3 {
        print("AuthenticationManager: Multiple token refresh failures, forcing reauthentication")
        NotificationCenter.default.post(
          name: Notification.Name("ForceReauthentication"), object: nil)
      }
    }
  }

  private func setupAuthStateListener() {
    handle = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
      Task { @MainActor in
        self?.currentUser = user
        self?.isAuthenticated = user != nil

        // Load user profile if user exists
        if let user = user {
          await self?.loadUserProfile(userId: user.uid)

          // Apply any pending FCM token after user is authenticated
          if let pendingToken = self?.pendingFCMToken {
            print("AuthenticationManager: Applying pending FCM token after auth")
            await self?.updateFCMToken(pendingToken)
            self?.pendingFCMToken = nil  // Clear pending token
          }

          // Reset token refresh attempts when user changes
          self?.tokenRefreshAttempts = 0
        } else {
          self?.currentUserProfile = nil
        }

        print("AuthenticationManager: Auth state changed - User: \(user?.uid ?? "none")")
      }
    }
  }

  func signIn(email: String, password: String) async throws {
    let result = try await Auth.auth().signIn(withEmail: email, password: password)
    self.currentUser = result.user
    self.isAuthenticated = true
    self.errorMessage = nil

    // Load user profile
    await loadUserProfile(userId: result.user.uid)

    print("AuthenticationManager: Sign in successful - User: \(result.user.uid)")
  }

  func signUp(email: String, password: String, zipCode: String) async throws {
    let result = try await Auth.auth().createUser(withEmail: email, password: password)
    self.currentUser = result.user
    self.isAuthenticated = true
    self.errorMessage = nil
    print("AuthenticationManager: Sign up successful - User: \(result.user.uid)")

    // Create user profile in Firestore with zip code
    try await createUserProfile(for: result.user, email: email, zipCode: zipCode)
  }

  // Legacy signUp method for backward compatibility - will prompt for zip code
  func signUp(email: String, password: String) async throws {
    // For now, use a default zip code or throw an error
    throw NSError(
      domain: "AuthenticationManager", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Zip code is required for registration"])
  }

  func signInAnonymously() async throws {
    let result = try await Auth.auth().signInAnonymously()
    self.currentUser = result.user
    self.isAuthenticated = true
    self.errorMessage = nil
    print("AuthenticationManager: Anonymous sign in successful - User: \(result.user.uid)")

    // Create anonymous user profile (no email or zip code)
    try await createAnonymousUserProfile(for: result.user)
  }

  private func createAnonymousUserProfile(for user: User) async throws {
    let userRef = db.collection("users").document(user.uid)

    let userData: [String: Any] = [
      "uid": user.uid,
      "email": "",
      "isAnonymous": true,
      "createdAt": FieldValue.serverTimestamp(),
      "lastLogin": FieldValue.serverTimestamp(),
      "zipCode": "",  // Empty zip code for anonymous users
    ]

    try await userRef.setData(userData, merge: true)
    print("AuthenticationManager: Anonymous user profile created in Firestore - User: \(user.uid)")
  }

  func signOut() throws {
    try Auth.auth().signOut()
    self.currentUser = nil
    self.isAuthenticated = false
    self.errorMessage = nil
    self.pendingFCMToken = nil  // Clear any pending FCM token
    print("AuthenticationManager: Sign out successful")
  }

  private func createUserProfile(for user: User, email: String, zipCode: String) async throws {
    // Create UserProfile object
    let userProfile = UserProfile(id: user.uid, email: email, zipCode: zipCode)

    // Save to Firestore
    try await db.collection("users").document(user.uid).setData(userProfile.toFirestoreData())

    // Update local profile
    self.currentUserProfile = userProfile

    print(
      "AuthenticationManager: User profile created in Firestore - User: \(user.uid), ZipCode: \(zipCode)"
    )
  }

  private func loadUserProfile(userId: String) async {
    do {
      let document = try await db.collection("users").document(userId).getDocument()

      if document.exists, let data = document.data() {
        if let profile = UserProfile.fromFirestoreData(id: userId, data: data) {
          self.currentUserProfile = profile
          print(
            "AuthenticationManager: User profile loaded - User: \(userId), ZipCode: \(profile.zipCode)"
          )

          // FIXED: Update FCM token if missing in the loaded profile
          if profile.fcmToken == nil || profile.fcmToken?.isEmpty == true {
            print("AuthenticationManager: FCM token missing, requesting update from AppDelegate")
            // Request current token from Messaging
            Task {
              if let token = Messaging.messaging().fcmToken {
                print("AuthenticationManager: Retrieved current FCM token, updating profile")
                await updateFCMToken(token)
              }
            }
          }
        } else {
          print("AuthenticationManager: Failed to parse user profile data")
        }
      } else {
        print("AuthenticationManager: User profile document not found")
        // For existing users without profiles, create one with a default zip code
        await createMissingUserProfile(userId: userId)
      }
    } catch {
      print("AuthenticationManager: Error loading user profile: \(error.localizedDescription)")
    }
  }

  /// Creates a user profile for existing users who don't have one
  private func createMissingUserProfile(userId: String) async {
    guard let user = currentUser else { return }

    // Use a default zip code (you can change this later in profile settings)
    let defaultZipCode = "10001"  // Default to NYC zip code
    let email = user.email ?? ""

    print("AuthenticationManager: Creating missing profile for existing user: \(userId)")

    do {
      // FIXED: Get current FCM token to include in the new profile
      let fcmToken = Messaging.messaging().fcmToken

      // Create user profile with the current FCM token
      let userProfile = UserProfile(
        id: userId, email: email, zipCode: defaultZipCode, fcmToken: fcmToken)

      // Save to Firestore
      try await db.collection("users").document(userId).setData(userProfile.toFirestoreData())

      // Update local profile
      self.currentUserProfile = userProfile

      print(
        "AuthenticationManager: Successfully created missing profile with default zip code: \(defaultZipCode) and FCM token: \(fcmToken ?? "none")"
      )
    } catch {
      print("AuthenticationManager: Error creating missing profile: \(error.localizedDescription)")
    }
  }

  func updateFCMToken(_ token: String) async {
    guard let userId = currentUser?.uid else {
      print("AuthenticationManager: No current user, storing FCM token for later")
      pendingFCMToken = token
      return
    }

    do {
      // Update Firestore document
      try await db.collection("users").document(userId).updateData([
        "fcmToken": token,
        "lastTokenUpdate": FieldValue.serverTimestamp(),
      ])

      // Update local profile
      currentUserProfile?.fcmToken = token

      print("AuthenticationManager: Updating FCM token to: \(String(token.prefix(10)))...")
    } catch {
      print("AuthenticationManager: Error updating FCM token: \(error.localizedDescription)")

      // If we get a permission error, the token might be invalid - force refresh
      if let nsError = error as NSError?, nsError.domain == FirestoreErrorDomain {
        print("AuthenticationManager: Firestore error updating token, attempting to refresh auth")
        await refreshAuthTokenIfNeeded()
      }
    }
  }

  /// Updates the user's zip code for notifications
  /// For premium users, this allows changing to any zip code
  /// For free users, this only allows changing back to their original zip code
  func updateZipCode(_ newZipCode: String) async throws {
    // Rate limiting: prevent updates more than once every 2 seconds
    let now = Date()
    if let lastUpdate = lastZipCodeUpdate, now.timeIntervalSince(lastUpdate) < 2.0 {
      print("AuthenticationManager: Rate limiting zip code update - too soon after last update")
      throw NSError(
        domain: "AuthenticationManager", code: -4,
        userInfo: [NSLocalizedDescriptionKey: "Please wait before changing zip code again"])
    }

    guard let userId = currentUser?.uid else {
      throw NSError(
        domain: "AuthenticationManager", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
    }

    guard let profile = currentUserProfile else {
      throw NSError(
        domain: "AuthenticationManager", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "User profile not loaded"])
    }

    // Check if user can change to this zip code
    if !profile.canChangeToZipCode(newZipCode) {
      throw NSError(
        domain: "AuthenticationManager", code: -3,
        userInfo: [NSLocalizedDescriptionKey: "Premium upgrade required to change zip codes"])
    }

    do {
      // Update last update time before making the change
      lastZipCodeUpdate = now

      // Update zip code in Firestore
      try await db.collection("users").document(userId).updateData(["zipCode": newZipCode])

      // Update local profile with all existing data plus new zip code
      let updatedProfile = UserProfile(
        id: profile.id,
        email: profile.email,
        zipCode: newZipCode,
        fcmToken: profile.fcmToken,
        createdAt: profile.createdAt,
        lastActive: Date(),
        isPremium: profile.isPremium,
        originalZipCode: profile.originalZipCode
      )
      self.currentUserProfile = updatedProfile

      print("AuthenticationManager: Zip code updated to: \(newZipCode)")
    } catch {
      // Reset last update time on error
      lastZipCodeUpdate = nil
      print("AuthenticationManager: Error updating zip code: \(error.localizedDescription)")
      throw error
    }
  }

  /// Completely deletes user account and all associated data
  /// This satisfies Apple's requirement for complete account deletion
  func deleteAccount() async throws {
    guard let user = currentUser else {
      throw NSError(
        domain: "AuthenticationManager", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
    }

    let userId = user.uid
    print("AuthenticationManager: Starting complete account deletion for user: \(userId)")

    // Step 1: Delete all user's pins from Firestore
    do {
      let pinsSnapshot = try await db.collection("pins")
        .whereField("userId", isEqualTo: userId)
        .getDocuments()

      for document in pinsSnapshot.documents {
        try await document.reference.delete()
        print("AuthenticationManager: Deleted pin: \(document.documentID)")
      }
      print("AuthenticationManager: Deleted \(pinsSnapshot.documents.count) user pins")
    } catch {
      print("AuthenticationManager: Error deleting user pins: \(error)")
      // Continue with deletion even if pins can't be deleted
    }

    // Step 2: Delete any flagged video reports by this user
    do {
      let reportsSnapshot = try await db.collection("flaggedVideos")
        .whereField("email", isEqualTo: user.email ?? "")
        .getDocuments()

      for document in reportsSnapshot.documents {
        try await document.reference.delete()
        print("AuthenticationManager: Deleted report: \(document.documentID)")
      }
      print("AuthenticationManager: Deleted \(reportsSnapshot.documents.count) user reports")
    } catch {
      print("AuthenticationManager: Error deleting user reports: \(error)")
      // Continue with deletion
    }

    // Step 3: Delete user profile from Firestore
    do {
      try await db.collection("users").document(userId).delete()
      print("AuthenticationManager: Deleted user profile from Firestore")
    } catch {
      print("AuthenticationManager: Error deleting user profile: \(error)")
      // Continue with deletion
    }

    // Step 4: Delete Firebase Auth account
    try await user.delete()
    print("AuthenticationManager: Deleted Firebase Auth account")

    // Step 5: Clear local state
    await MainActor.run {
      self.currentUser = nil
      self.currentUserProfile = nil
      self.isAuthenticated = false
      self.errorMessage = nil
    }

    print("AuthenticationManager: Account deletion completed successfully")
  }

  // Listen for premium status updates
  private func setupPremiumStatusListener() {
    NotificationCenter.default.addObserver(
      forName: Notification.Name("UserPremiumStatusUpdated"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        print("AuthenticationManager: Received premium status update notification")
        // Reload user profile to get updated premium status
        if let userId = self?.currentUser?.uid {
          print("AuthenticationManager: Reloading user profile after premium update")
          await self?.loadUserProfile(userId: userId)
        }
      }
    }
  }

  /// Updates user's premium status (called by PremiumManager)
  func updatePremiumStatus(_ isPremium: Bool) async {
    print("AuthenticationManager: updatePremiumStatus called with isPremium: \(isPremium)")
    guard let userId = currentUser?.uid else {
      print("AuthenticationManager: Cannot update premium status - no current user")
      return
    }

    do {
      // Update premium status in Firestore
      try await db.collection("users").document(userId).updateData(["isPremium": isPremium])
      print("AuthenticationManager: Updated premium status in Firestore to: \(isPremium)")

      // Update local profile on main actor
      await MainActor.run {
        if let profile = self.currentUserProfile {
          print(
            "AuthenticationManager: Current profile before update - isPremium: \(profile.isPremium)"
          )
          let updatedProfile = UserProfile(
            id: profile.id,
            email: profile.email,
            zipCode: profile.zipCode,
            fcmToken: profile.fcmToken,
            createdAt: profile.createdAt,
            lastActive: Date(),
            isPremium: isPremium,
            originalZipCode: profile.originalZipCode
          )
          self.currentUserProfile = updatedProfile
          print("AuthenticationManager: Updated local premium status to: \(isPremium)")
          print(
            "AuthenticationManager: New profile isPremium: \(self.currentUserProfile?.isPremium ?? false)"
          )
        } else {
          print("AuthenticationManager: No current user profile to update")
        }
      }

      print("AuthenticationManager: Premium status update completed")
    } catch {
      print("AuthenticationManager: Error updating premium status: \(error.localizedDescription)")
    }
  }

  deinit {
    if let handle = handle {
      Auth.auth().removeStateDidChangeListener(handle)
    }
    NotificationCenter.default.removeObserver(self)
  }
}
