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
  private let pendingFCMTokenKey = "PendingFCMTokenKey"
  private var handle: AuthStateDidChangeListenerHandle?
  private lazy var db: Firestore = { Firestore.firestore() }()

  init() {
    setupAuthStateListener()
    setupPremiumStatusListener()
  }

  private func setupAuthStateListener() {
    handle = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
      Task { @MainActor in
        self?.currentUser = user
        self?.isAuthenticated = user != nil

        // Load user profile if user exists
        if let user = user {
          await self?.loadUserProfile(userId: user.uid)
          await self?.syncPendingFCMTokenIfNeeded()
          await self?.refreshCurrentFCMToken()
        } else {
          self?.currentUserProfile = nil
        }

        #if DEBUG
        print("AuthenticationManager: Auth state changed - User: \(user?.uid ?? "none")")
        #endif
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
    await syncPendingFCMTokenIfNeeded()
    await refreshCurrentFCMToken()

    #if DEBUG
    print("AuthenticationManager: Sign in successful - User: \(result.user.uid)")
    #endif
  }

  func signUp(email: String, password: String, zipCode: String) async throws {
    let result = try await Auth.auth().createUser(withEmail: email, password: password)
    self.currentUser = result.user
    self.isAuthenticated = true
    self.errorMessage = nil
    #if DEBUG
    print("AuthenticationManager: Sign up successful - User: \(result.user.uid)")
    #endif

    // Create user profile in Firestore with zip code
    try await createUserProfile(for: result.user, email: email, zipCode: zipCode)
    await syncPendingFCMTokenIfNeeded()
    await refreshCurrentFCMToken()
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
    #if DEBUG
    print("AuthenticationManager: Anonymous sign in successful - User: \(result.user.uid)")
    #endif

    // Create anonymous user profile (no email or zip code)
    try await createAnonymousUserProfile(for: result.user)
    await syncPendingFCMTokenIfNeeded()
    await refreshCurrentFCMToken()
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
    #if DEBUG
    print("AuthenticationManager: Anonymous user profile created in Firestore - User: \(user.uid)")
    #endif
  }

  func signOut() throws {
    try Auth.auth().signOut()
    self.currentUser = nil
    self.isAuthenticated = false
    self.errorMessage = nil
    #if DEBUG
    print("AuthenticationManager: Sign out successful")
    #endif
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

    // Ensure user is added to their zip code bucket for notifications (scalable buckets)
    let zipBucketRef = Firestore.firestore().collection("zipcodes").document(zipCode).collection("users").document(user.uid)
    let userInfo: [String: Any] = [
      "email": email,
      "fcmToken": Messaging.messaging().fcmToken ?? "",
      "joined": FieldValue.serverTimestamp()
    ]
    try? await zipBucketRef.setData(userInfo, merge: true)
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
            #if DEBUG
            print("AuthenticationManager: FCM token missing, requesting update from AppDelegate")
            #endif
            // Request current token from Messaging
            Task {
              if let token = Messaging.messaging().fcmToken {
                #if DEBUG
                print("AuthenticationManager: Retrieved current FCM token, updating profile")
                #endif
                await updateFCMToken(token)
              }
            }
          }
        } else {
          #if DEBUG
          print("AuthenticationManager: Failed to parse user profile data")
          #endif
        }
      } else {
        #if DEBUG
        print("AuthenticationManager: User profile document not found")
        #endif
        // For existing users without profiles, create one with a default zip code
        await createMissingUserProfile(userId: userId)
      }
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error loading user profile: \(error.localizedDescription)")
      #endif
    }
  }

  /// Creates a user profile for existing users who don't have one
  private func createMissingUserProfile(userId: String) async {
    guard let user = currentUser else { return }

    // Use a default zip code (you can change this later in profile settings)
    let defaultZipCode = "10001"  // Default to NYC zip code
    let email = user.email ?? ""

    #if DEBUG
    print("AuthenticationManager: Creating missing profile for existing user: \(userId)")
    #endif

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

      // Ensure user is added to their zip code bucket for notifications (scalable buckets)
      let zipBucketRef = Firestore.firestore().collection("zipcodes").document(defaultZipCode).collection("users").document(userId)
      let userInfo: [String: Any] = [
        "email": email,
        "fcmToken": fcmToken ?? "",
        "joined": FieldValue.serverTimestamp()
      ]
      try? await zipBucketRef.setData(userInfo, merge: true)

    } catch {
      #if DEBUG
      print("AuthenticationManager: Error creating missing profile: \(error.localizedDescription)")
      #endif
    }
  }

  func updateFCMToken(_ token: String) async {
    guard let userId = currentUser?.uid else {
      UserDefaults.standard.set(token, forKey: pendingFCMTokenKey)
      #if DEBUG
      print("AuthenticationManager: Stored pending FCM token for future update")
      #endif
      return
    }

    do {
      #if DEBUG
      print("AuthenticationManager: Updating FCM token to: \(token.prefix(8))...")
      #endif

      // Update FCM token in Firestore
      try await db.collection("users").document(userId).updateData(["fcmToken": token])
      UserDefaults.standard.removeObject(forKey: pendingFCMTokenKey)

      // Update local profile
      if currentUserProfile != nil {
        currentUserProfile?.updateFCMToken(token)
      } else {
        #if DEBUG
        print("AuthenticationManager: Creating profile since none exists during FCM update")
        #endif
        await loadUserProfile(userId: userId)
      }

      #if DEBUG
      print("AuthenticationManager: FCM token updated for user: \(userId)")
      #endif
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error updating FCM token: \(error.localizedDescription)")
      print("AuthenticationManager: Error details - Domain: \((error as NSError).domain), Code: \((error as NSError).code)")
      #endif

      // If the document doesn't exist, create it
      if let nsError = error as NSError?, nsError.domain == FirestoreErrorDomain, nsError.code == 5
      {
        #if DEBUG
        print("AuthenticationManager: User document doesn't exist, creating it")
        #endif
        await createMissingUserProfile(userId: userId)
      } else {
        // For other Firestore errors, retry once after a short delay
        #if DEBUG
        print("AuthenticationManager: Retrying FCM token update after delay...")
        #endif
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        do {
          try await db.collection("users").document(userId).updateData(["fcmToken": token])
          #if DEBUG
          print("AuthenticationManager: FCM token updated successfully on retry")
          #endif
        } catch let retryError {
          #if DEBUG
          print("AuthenticationManager: FCM token update failed on retry: \(retryError.localizedDescription)")
          #endif
        }
      }
    }
  }

  private func syncPendingFCMTokenIfNeeded() async {
    guard let pendingToken = UserDefaults.standard.string(forKey: pendingFCMTokenKey) else { return }
    #if DEBUG
    print("AuthenticationManager: Applying pending FCM token")
    #endif
    await updateFCMToken(pendingToken)
  }

  private func refreshCurrentFCMToken() async {
    guard let freshToken = await fetchCurrentFCMToken() else { return }
    await updateFCMToken(freshToken)
  }

  private func fetchCurrentFCMToken() async -> String? {
    await withCheckedContinuation { continuation in
      Messaging.messaging().token { token, error in
        if let error = error {
          #if DEBUG
          print("AuthenticationManager: Failed to fetch FCM token: \(error.localizedDescription)")
          #endif
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: token)
      }
    }
  }

  /// Updates the user's zip code for notifications
  /// For premium users, this allows changing to any zip code
  /// For free users, this only allows changing back to their original zip code
  func updateZipCode(_ newZipCode: String) async throws {
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
    #if DEBUG
    print("AuthenticationManager: Checking if user can change to zip code \(newZipCode)")
    print("AuthenticationManager: User isPremium: \(profile.isPremium)")
    print("AuthenticationManager: User originalZipCode: \(profile.originalZipCode)")
    #endif

    if !profile.canChangeToZipCode(newZipCode) {
      #if DEBUG
      print("AuthenticationManager: canChangeToZipCode returned false - denying zip code change")
      #endif
      throw NSError(
        domain: "AuthenticationManager", code: -3,
        userInfo: [NSLocalizedDescriptionKey: "Premium upgrade required to change zip codes"])
    }

    #if DEBUG
    print("AuthenticationManager: canChangeToZipCode returned true - proceeding with zip code change")
    #endif

    do {
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
        originalZipCode: profile.originalZipCode,
        purchasedZipCodes: profile.purchasedZipCodes,
        currentZipCode: profile.currentZipCode ?? newZipCode,
        currentZipUpdatedAt: profile.currentZipUpdatedAt,
        zipCodeNotifications: profile.zipCodeNotifications
      )
      self.currentUserProfile = updatedProfile

      #if DEBUG
      print("AuthenticationManager: Zip code updated to: \(newZipCode)")
      #endif

      // Ensure user is added to their zip code bucket for notifications (scalable buckets)
      let zipBucketRef = Firestore.firestore().collection("zipcodes").document(newZipCode).collection("users").document(userId)
      let userInfo: [String: Any] = [
        "email": profile.email,
        "fcmToken": Messaging.messaging().fcmToken ?? "",
        "joined": FieldValue.serverTimestamp()
      ]
      try? await zipBucketRef.setData(userInfo, merge: true)

    } catch {
      #if DEBUG
      print("AuthenticationManager: Error updating zip code: \(error.localizedDescription)")
      #endif
      throw error
    }
  }

  func updateHomeZipCode(_ newZipCode: String) async throws {
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

    try await db.collection("users").document(userId).updateData([
      "zipCode": newZipCode,
      "originalZipCode": newZipCode
    ])

    let updatedProfile = UserProfile(
      id: profile.id,
      email: profile.email,
      zipCode: newZipCode,
      fcmToken: profile.fcmToken,
      createdAt: profile.createdAt,
      lastActive: Date(),
      isPremium: profile.isPremium,
      originalZipCode: newZipCode,
      purchasedZipCodes: profile.purchasedZipCodes,
      currentZipCode: profile.currentZipCode ?? newZipCode,
      currentZipUpdatedAt: Date(),
      zipCodeNotifications: profile.zipCodeNotifications
    )
    self.currentUserProfile = updatedProfile
  }

  func addUnlockedZipCode(_ zipCode: String) async throws {
    guard let userId = currentUser?.uid else {
      throw NSError(
        domain: "AuthenticationManager", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No user is currently signed in"])
    }

    guard var profile = currentUserProfile else {
      throw NSError(
        domain: "AuthenticationManager", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "User profile not loaded"])
    }

    if profile.purchasedZipCodes.contains(zipCode) {
      return
    }

    var updatedZips = profile.purchasedZipCodes
    updatedZips.append(zipCode)

    try await db.collection("users").document(userId).updateData([
      "purchasedZipCodes": FieldValue.arrayUnion([zipCode])
    ])

    profile = UserProfile(
      id: profile.id,
      email: profile.email,
      zipCode: profile.zipCode,
      fcmToken: profile.fcmToken,
      createdAt: profile.createdAt,
      lastActive: Date(),
      isPremium: profile.isPremium,
      originalZipCode: profile.originalZipCode,
      purchasedZipCodes: updatedZips,
      currentZipCode: profile.currentZipCode,
      currentZipUpdatedAt: profile.currentZipUpdatedAt,
      zipCodeNotifications: profile.zipCodeNotifications
    )
    self.currentUserProfile = profile
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
    #if DEBUG
    print("AuthenticationManager: Starting complete account deletion for user: \(userId)")
    #endif

    // Step 1: Delete all user's pins from Firestore
    do {
      let pinsSnapshot = try await db.collection("pins")
        .whereField("userId", isEqualTo: userId)
        .getDocuments()

      for document in pinsSnapshot.documents {
        try await document.reference.delete()
        #if DEBUG
        print("AuthenticationManager: Deleted pin: \(document.documentID)")
        #endif
      }
      #if DEBUG
      print("AuthenticationManager: Deleted \(pinsSnapshot.documents.count) user pins")
      #endif
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error deleting user pins: \(error)")
      #endif
      // Continue with deletion even if pins can't be deleted
    }

    // Step 2: Delete any flagged video reports by this user
    do {
      let reportsSnapshot = try await db.collection("flaggedVideos")
        .whereField("email", isEqualTo: user.email ?? "")
        .getDocuments()

      for document in reportsSnapshot.documents {
        try await document.reference.delete()
        #if DEBUG
        print("AuthenticationManager: Deleted report: \(document.documentID)")
        #endif
      }
      #if DEBUG
      print("AuthenticationManager: Deleted \(reportsSnapshot.documents.count) user reports")
      #endif
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error deleting user reports: \(error)")
      #endif
      // Continue with deletion
    }

    // Step 3: Delete user profile from Firestore
    do {
      try await db.collection("users").document(userId).delete()
      #if DEBUG
      print("AuthenticationManager: Deleted user profile from Firestore")
      #endif
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error deleting user profile: \(error)")
      #endif
      // Continue with deletion
    }

    // Step 4: Delete Firebase Auth account
    try await user.delete()
    #if DEBUG
    print("AuthenticationManager: Deleted Firebase Auth account")
    #endif

    // Step 5: Clear local state
    await MainActor.run {
      self.currentUser = nil
      self.currentUserProfile = nil
      self.isAuthenticated = false
      self.errorMessage = nil
    }

    #if DEBUG
    print("AuthenticationManager: Account deletion completed successfully")
    #endif
  }

  // Listen for premium status updates
  private func setupPremiumStatusListener() {
    NotificationCenter.default.addObserver(
      forName: Notification.Name("UserPremiumStatusUpdated"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        #if DEBUG
        print("AuthenticationManager: Received premium status update notification")
        #endif
        // Reload user profile to get updated premium status
        if let userId = self?.currentUser?.uid {
          #if DEBUG
          print("AuthenticationManager: Reloading user profile after premium update")
          #endif
          await self?.loadUserProfile(userId: userId)
        }
      }
    }
  }

  /// Updates user's premium status (called by PremiumManager)
  func updatePremiumStatus(_ isPremium: Bool) async {
    #if DEBUG
    print("AuthenticationManager: updatePremiumStatus called with isPremium: \(isPremium)")
    #endif
    guard let userId = currentUser?.uid else {
      #if DEBUG
      print("AuthenticationManager: Cannot update premium status - no current user")
      #endif
      return
    }

    do {
      // Update premium status in Firestore
      try await db.collection("users").document(userId).updateData(["isPremium": isPremium])
      #if DEBUG
      print("AuthenticationManager: Updated premium status in Firestore to: \(isPremium)")
      #endif

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
            originalZipCode: profile.originalZipCode,
            purchasedZipCodes: profile.purchasedZipCodes,
            currentZipCode: profile.currentZipCode,
            currentZipUpdatedAt: profile.currentZipUpdatedAt,
            zipCodeNotifications: profile.zipCodeNotifications
          )
          self.currentUserProfile = updatedProfile
          #if DEBUG
          print("AuthenticationManager: Updated local premium status to: \(isPremium)")
          #endif
          print(
            "AuthenticationManager: New profile isPremium: \(self.currentUserProfile?.isPremium ?? false)"
          )
        } else {
          #if DEBUG
          print("AuthenticationManager: No current user profile to update")
          #endif
        }
      }

      #if DEBUG
      print("AuthenticationManager: Premium status update completed")
      #endif
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error updating premium status: \(error.localizedDescription)")
      #endif
    }
  }

  /// Validates and refreshes FCM token if needed
  func validateAndRefreshFCMToken() async {
    #if DEBUG
    print("AuthenticationManager: Validating FCM token")
    #endif

    guard let currentToken = Messaging.messaging().fcmToken else {
      #if DEBUG
      print("AuthenticationManager: No current FCM token available")
      #endif
      return
    }

    // Check if stored token matches current token
    if currentUserProfile?.fcmToken != currentToken {
      #if DEBUG
      print("AuthenticationManager: FCM token mismatch detected, updating...")
      #endif
      await updateFCMToken(currentToken)
    } else {
      #if DEBUG
      print("AuthenticationManager: FCM token is current")
      #endif
    }
  }

  /// Updates notification preference for a specific zip code
  func updateNotificationPreference(_ enabled: Bool, for zipCode: String) async {
    #if DEBUG
    print("AuthenticationManager: updateNotificationPreference called for zipCode: \(zipCode), enabled: \(enabled)")
    #endif
    guard let userId = currentUser?.uid else {
      #if DEBUG
      print("AuthenticationManager: Cannot update notification preference - no current user")
      #endif
      return
    }

    do {
      // Update notification preference in Firestore
      try await db.collection("users").document(userId).updateData([
        "zipCodeNotifications.\(zipCode)": enabled
      ])
      #if DEBUG
      print("AuthenticationManager: Updated notification preference in Firestore for zipCode: \(zipCode) to: \(enabled)")
      #endif

      // Update local profile on main actor
      await MainActor.run {
        if var profile = self.currentUserProfile {
          profile.setNotifications(enabled, for: zipCode)
          self.currentUserProfile = profile
          #if DEBUG
          print("AuthenticationManager: Updated local notification preference for zipCode: \(zipCode) to: \(enabled)")
          #endif
        } else {
          #if DEBUG
          print("AuthenticationManager: No current user profile to update")
          #endif
        }
      }

      #if DEBUG
      print("AuthenticationManager: Notification preference update completed")
      #endif
    } catch {
      #if DEBUG
      print("AuthenticationManager: Error updating notification preference: \(error.localizedDescription)")
      #endif
    }
  }

  deinit {
    if let handle = handle {
      Auth.auth().removeStateDidChangeListener(handle)
    }
    NotificationCenter.default.removeObserver(self)
  }
}

