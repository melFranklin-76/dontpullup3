import FirebaseAuth
import FirebaseFirestore
import Foundation
import StoreKit

@MainActor
class PremiumManager: ObservableObject {
  static let shared = PremiumManager()

  // Reference to AuthenticationManager for updating user profiles
  private let authManager = AuthenticationManager.shared

  // Premium product identifier - ONLY ONE PRODUCT TO MANAGE
  private let zipCodeUnlockProductID = "com.dontpullup.app.zipcode_upgrade"

  // Published properties for UI binding
  @Published var isLoading = false
  @Published var products: [Product] = []
  @Published var purchaseError: String?
  @Published var purchaseSuccess = false
  @Published var isPremium = false

  // Store transaction listener
  private var updateListenerTask: Task<Void, Error>?

  init() {
    // Start listening for transactions
    updateListenerTask = listenForTransactions()

    // Load products and check status
    Task {
      await fetchProducts()
      await checkPurchaseStatus()
    }
  }

  deinit {
    updateListenerTask?.cancel()
  }

  // MARK: - Simplified Product Management

  func fetchProducts() async {
    isLoading = true

    // In test mode, skip product fetching
    if forceTestMode {
      print("[PremiumManager] Test mode enabled - skipping real product fetch")
      await MainActor.run {
        self.isLoading = false
      }
      return
    }

    do {
      // Request ONLY our single product
      let storeProducts = try await Product.products(for: [zipCodeUnlockProductID])

      await MainActor.run {
        self.products = storeProducts
        self.isLoading = false

        if storeProducts.isEmpty {
          print("[PremiumManager] No products found")
          self.purchaseError = "Premium upgrade temporarily unavailable. Please try again later."
        } else {
          print("[PremiumManager] Found \(storeProducts.count) products")
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

  // MARK: - Simplified Transaction Management

  private func listenForTransactions() -> Task<Void, Error> {
    return Task.detached {
      for await result in StoreKit.Transaction.updates {
        do {
          let transaction: StoreKit.Transaction
          switch result {
          case .verified(let verifiedTransaction):
            transaction = verifiedTransaction
          case .unverified:
            throw StoreError.failedVerification
          }

          await self.handleTransaction(transaction)
          await transaction.finish()
        } catch {
          print("[PremiumManager] Transaction failed verification: \(error)")
        }
      }
    }
  }

  // MARK: - Simplified Purchase Flow

  private var forceTestMode: Bool {
    #if DEBUG
      print("[PremiumManager] DEBUG build detected - using test mode")
      return true  // Always use test mode in debug builds
    #else
      // Check if this is a TestFlight build
      if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
        print("[PremiumManager] TestFlight build detected - using test mode")
        return true  // TestFlight users get test mode
      }
      print("[PremiumManager] App Store build detected - using real IAP")
      return false  // Real App Store users get real IAP
    #endif
  }

  func purchasePremium() async {
    print("[PremiumManager] ===== purchasePremium() called =====")

    purchaseError = nil

    // Use test mode in simulator
    if forceTestMode {
      print("[PremiumManager] Using test mode - simulating successful purchase")
      await simulatePurchaseForTesting()
      return
    }

    guard let product = products.first(where: { $0.id == zipCodeUnlockProductID }) else {
      purchaseError = "Premium upgrade not available. Please try again later."
      return
    }

    do {
      isLoading = true

      let result = try await product.purchase()

      switch result {
      case .success(let verification):
        let transaction: StoreKit.Transaction
        switch verification {
        case .verified(let verifiedTransaction):
          transaction = verifiedTransaction
        case .unverified:
          throw StoreError.failedVerification
        }

        await handleTransaction(transaction)
        await transaction.finish()
        print("[PremiumManager] Purchase successful")

      case .userCancelled:
        print("[PremiumManager] User cancelled purchase")
        isLoading = false

      case .pending:
        print("[PremiumManager] Purchase pending approval")
        purchaseError = "Purchase is pending approval."
        isLoading = false

      @unknown default:
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

  // MARK: - Test Mode Simulation

  func simulatePurchaseForTesting() async {
    print("[PremiumManager] Starting simulated purchase flow")
    isLoading = true
    purchaseError = nil
    purchaseSuccess = false

    if Auth.auth().currentUser == nil {
      print("[PremiumManager] No user logged in during simulation")
      purchaseError = "Error: You must be signed in to make purchases"
      isLoading = false
      return
    }

    // Simulate network delay
    do {
      try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
    } catch {
      print("[PremiumManager] Simulated purchase was interrupted")
      isLoading = false
      return
    }

    print("[PremiumManager] Simulated purchase completed")
    await updateUserPremiumStatus()

    // Ensure UI is updated
    await MainActor.run {
      self.isPremium = true
      self.purchaseSuccess = true
      self.isLoading = false
      print(
        "[PremiumManager] Simulated purchase UI updated: isPremium=\(self.isPremium), purchaseSuccess=\(self.purchaseSuccess)"
      )
    }
  }

  // MARK: - Simple Restore

  func restorePurchases() async {
    print("[PremiumManager] Restoring purchases")
    isLoading = true

    do {
      try await AppStore.sync()
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

  // MARK: - Simple Status Check

  func checkPurchaseStatus() async {
    if let transaction = await getLatestTransaction() {
      await handleTransaction(transaction)
    } else {
      print("[PremiumManager] No previous transactions found")
      isPremium = false
    }
  }

  private func getLatestTransaction() async -> StoreKit.Transaction? {
    var latestTransaction: StoreKit.Transaction? = nil

    for await result in StoreKit.Transaction.currentEntitlements {
      if case .verified(let transaction) = result {
        if transaction.productID == zipCodeUnlockProductID {
          latestTransaction = transaction
        }
      }
    }

    return latestTransaction
  }

  // MARK: - Simple Transaction Handling

  private func handleTransaction(_ transaction: StoreKit.Transaction) async {
    print("[PremiumManager] Processing transaction: \(transaction.productID)")

    guard transaction.productID == zipCodeUnlockProductID else {
      print("[PremiumManager] Transaction is not for our product")
      return
    }

    guard transaction.revocationDate == nil else {
      print("[PremiumManager] Transaction was revoked")
      isPremium = false
      return
    }

    if transaction.productType == .nonRenewable && !transaction.isUpgraded {
      print("[PremiumManager] User is entitled to premium access")
      await updateUserPremiumStatus()
    }
  }

  // MARK: - Simple Status Update

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
      let docSnapshot = try await userRef.getDocument()

      if docSnapshot.exists {
        try await userRef.updateData(["isPremium": true])
        print("[PremiumManager] User premium status updated successfully")
      } else {
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

      // Update AuthenticationManager
      await authManager.updatePremiumStatus(true)

      // Post notification
      NotificationCenter.default.post(
        name: Notification.Name("UserPremiumStatusUpdated"), object: nil)

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

  enum StoreError: Error {
    case failedVerification
  }
}
