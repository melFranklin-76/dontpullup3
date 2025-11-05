import FirebaseAuth
import FirebaseFirestore
import Foundation
import StoreKit

@MainActor
class PremiumManager: ObservableObject {
  static let shared = PremiumManager()

  // Reference to AuthenticationManager for updating user profiles
  private let authManager = AuthenticationManager.shared

  // Premium product identifier - would be defined in App Store Connect
  // Note: Update this if the ID in App Store Connect is different
  private let zipCodeUnlockProductID = "com.dontpullup.app.zipcode_upgrade"

  // Published properties for UI binding
  @Published var isLoading = false
  @Published var products: [Product] = []
  @Published var purchaseError: String?
  @Published var purchaseSuccess = false

  // Track if user is premium
  @Published var isPremium = false

  // Store transaction listener
  private var updateListenerTask: Task<Void, Error>?

  init() {
    // Start listening for transactions right away
    updateListenerTask = listenForTransactions()

    // Load products
    Task {
      await fetchProducts()

      // Check if user already has premium access
      await checkPurchaseStatus()
    }
  }

  deinit {
    updateListenerTask?.cancel()
  }

  // MARK: - Product Management

  func fetchProducts() async {
    isLoading = true

    // In test mode, skip product fetching since we simulate purchases anyway
    if forceTestMode {
      print("[PremiumManager] Test mode enabled - skipping real product fetch")
      await MainActor.run {
        self.isLoading = false
      }
      return
    }

    do {
      // Request products from the App Store using the new StoreKit 2 API
      let storeProducts = try await Product.products(for: [zipCodeUnlockProductID])

      // Update the published products array on the main thread
      await MainActor.run {
        self.products = storeProducts
        self.isLoading = false

        if storeProducts.isEmpty {
          print("[PremiumManager] No products found")
          self.purchaseError = "Premium upgrade temporarily unavailable. Please try again later."
        } else {
          print("[PremiumManager] Found \(storeProducts.count) products")

          // Log product details in debug mode
          #if DEBUG
            for product in storeProducts {
              print(
                "[PremiumManager] Product: \(product.id), \(product.displayName), \(product.displayPrice)"
              )
            }
          #endif
        }
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
        self.purchaseError = "Failed to load premium options. Please try again later."
        print("[PremiumManager] Product request failed: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Transaction Management

  private func listenForTransactions() -> Task<Void, Error> {
    return Task.detached {
      // Iterate through any transactions that don't come from a direct call to `purchase()`.
      for await result in StoreKit.Transaction.updates {
        do {
          // Use direct verification without the type casting that caused the compiler error
          let transaction: StoreKit.Transaction
          switch result {
          case .verified(let verifiedTransaction):
            transaction = verifiedTransaction
          case .unverified:
            throw StoreError.failedVerification
          }

          // Handle the transaction
          await self.handleTransaction(transaction)

          // Always finish a transaction
          await transaction.finish()
        } catch {
          // StoreKit has a receipt it can read but it failed verification.
          print("[PremiumManager] Transaction failed verification: \(error)")
        }
      }
    }
  }

  // MARK: - Purchase Flow

  // Use this to enable testing mode even on real devices during development
  private var forceTestMode: Bool {
    #if DEBUG
      return true  // Always use test mode in debug builds
    #else
      return false  // Use real IAP in release builds
    #endif
  }

  func purchasePremium() async {
    print(
      "[PremiumManager] ===== purchasePremium() called - products count: \(products.count) =====")

    // Clear any previous errors
    purchaseError = nil

    // Use test mode in simulator or when forced for testing
    if forceTestMode {
      print("[PremiumManager] Using test mode - simulating successful purchase")
      await simulatePurchaseForTesting()
      return
    }

    guard let product = products.first(where: { $0.id == zipCodeUnlockProductID }) else {
      print("[PremiumManager] Product not found - showing error")
      purchaseError = "Premium upgrade not available. Please try again later."
      return
    }

    do {
      isLoading = true

      // Request a purchase from StoreKit
      let result = try await product.purchase()

      // Process the result
      switch result {
      case .success(let verification):
        // Check if the transaction is verified
        let transaction: StoreKit.Transaction
        switch verification {
        case .verified(let verifiedTransaction):
          transaction = verifiedTransaction
        case .unverified:
          throw StoreError.failedVerification
        }

        // Handle the successful transaction
        await handleTransaction(transaction)

        // Finish the transaction
        await transaction.finish()

        print("[PremiumManager] Purchase successful")

      case .userCancelled:
        // User cancelled the purchase - no need for error message
        print("[PremiumManager] User cancelled purchase")
        isLoading = false

      case .pending:
        // Purchase needs approval (e.g., Ask to Buy)
        print("[PremiumManager] Purchase pending approval")
        purchaseError = "Purchase is pending approval."
        isLoading = false

      @unknown default:
        // Handle any future transaction states
        print("[PremiumManager] Unknown purchase result")
        purchaseError = "Unknown purchase result. Please try again."
        isLoading = false
      }
    } catch {
      print("[PremiumManager] Purchase failed: \(error.localizedDescription)")
      purchaseError = "Purchase failed: \(error.localizedDescription)"
      isLoading = false
    }
  }

  // Special method to simulate purchases in simulator
  func simulatePurchaseForTesting() async {
    print("[PremiumManager] Starting simulated purchase flow")
    isLoading = true

    // Reset error state first
    purchaseError = nil

    // Check if user is signed in - fix unused variable warning
    if Auth.auth().currentUser == nil {
      print("[PremiumManager] No user logged in during simulation")
      purchaseError = "Error: You must be signed in to make purchases"
      isLoading = false
      purchaseSuccess = false
      return
    }

    // Simulate network delay
    do {
      try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
    } catch {
      // This catch block is needed because Task.sleep can throw if the task is cancelled
      print("[PremiumManager] Simulated purchase was interrupted")
      isLoading = false
      return
    }

    print("[PremiumManager] Simulated purchase completed")

    // For simulator testing, call the real update function
    await updateUserPremiumStatus()

    // Print current state for debugging
    print(
      "[PremiumManager] Current state - success: \(self.purchaseSuccess), loading: \(self.isLoading), error: \(self.purchaseError ?? "none")"
    )
  }

  // MARK: - Restore Purchases

  func restorePurchases() async {
    print("[PremiumManager] Restoring purchases")
    isLoading = true

    do {
      try await AppStore.sync()

      // After syncing, check purchase status
      await checkPurchaseStatus()

      if !isPremium {
        purchaseError = "No previous purchases found to restore."
      }

      isLoading = false
    } catch {
      print("[PremiumManager] Restore failed: \(error.localizedDescription)")
      purchaseError = "Failed to restore purchases: \(error.localizedDescription)"
      isLoading = false
    }
  }

  // MARK: - Purchase Verification

  func checkPurchaseStatus() async {
    // Check if user has premium access based on App Store receipt
    if let transaction = await getLatestTransaction() {
      // If we have a valid transaction, update the user's premium status
      await handleTransaction(transaction)
    } else {
      print("[PremiumManager] No previous transactions found")
      isPremium = false
    }
  }

  private func getLatestTransaction() async -> StoreKit.Transaction? {
    // Get the most recent transaction for our product
    var latestTransaction: StoreKit.Transaction? = nil

    // Get all transactions for the user
    for await result in StoreKit.Transaction.currentEntitlements {
      // Extract verified transaction directly
      if case .verified(let transaction) = result {
        // Check if this transaction is for our product
        if transaction.productID == zipCodeUnlockProductID {
          // If we found a transaction for our product, keep it
          latestTransaction = transaction
        }
      } else {
        print("[PremiumManager] Transaction verification failed")
      }
    }

    return latestTransaction
  }

  // MARK: - Transaction Handling

  private func handleTransaction(_ transaction: StoreKit.Transaction) async {
    // Process the transaction
    print("[PremiumManager] Processing transaction: \(transaction.productID)")

    // Check if the transaction is for our product
    guard transaction.productID == zipCodeUnlockProductID else {
      print("[PremiumManager] Transaction is not for our product: \(transaction.productID)")
      return
    }

    // Check if the transaction is active (not expired, revoked, or consumed)
    guard transaction.revocationDate == nil else {
      print("[PremiumManager] Transaction was revoked")
      isPremium = false
      return
    }

    // Check if the user is entitled to this product
    if transaction.productType == .nonRenewable && !transaction.isUpgraded {
      // User is entitled to this product
      print("[PremiumManager] User is entitled to premium access")

      // Update the user's premium status
      await updateUserPremiumStatus()
    }
  }

  // Update user's premium status in Firestore
  func updateUserPremiumStatus() async {
    guard let currentUser = Auth.auth().currentUser else {
      print("[PremiumManager] No user logged in")
      purchaseError = "Error: You must be signed in to make purchases"
      isLoading = false
      return
    }

    let db = Firestore.firestore()
    let userRef = db.collection("users").document(currentUser.uid)

    do {
      // First check if the user document exists
      let docSnapshot = try await userRef.getDocument()

      if docSnapshot.exists {
        // Document exists, update it
        try await userRef.updateData(["isPremium": true])
        print("[PremiumManager] User premium status updated successfully")
      } else {
        // Document doesn't exist, create it with premium status
        try await userRef.setData([
          "id": currentUser.uid,
          "email": currentUser.email ?? "",
          "isPremium": true,
          "createdAt": FieldValue.serverTimestamp(),
          "lastActive": FieldValue.serverTimestamp(),
          "zipCode": UserDefaults.standard.string(forKey: "userZipCode") ?? "",
          "originalZipCode": UserDefaults.standard.string(forKey: "userZipCode") ?? "",
        ])
        print("[PremiumManager] Created new user document with premium status")
      }

      // Update local state
      isPremium = true
      purchaseSuccess = true
      isLoading = false

      // Update AuthenticationManager's local profile
      print("[PremiumManager] Calling authManager.updatePremiumStatus(true)")
      await authManager.updatePremiumStatus(true)
      print("[PremiumManager] AuthenticationManager premium status update completed")

      // Post notification so other views can update
      print("[PremiumManager] Posting UserPremiumStatusUpdated notification")
      NotificationCenter.default.post(
        name: Notification.Name("UserPremiumStatusUpdated"), object: nil)
      print("[PremiumManager] Notification posted successfully")

    } catch {
      print("[PremiumManager] Error updating user premium status: \(error.localizedDescription)")
      purchaseError = "Failed to update premium status: \(error.localizedDescription)"
      isLoading = false
    }
  }

  // MARK: - Helper Methods

  func resetPurchaseState() {
    purchaseError = nil
    purchaseSuccess = false
  }

  // MARK: - Error Handling

  enum StoreError: Error {
    case failedVerification
  }
}
