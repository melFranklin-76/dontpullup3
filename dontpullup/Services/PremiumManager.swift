import FirebaseAuth
import FirebaseFirestore
import Foundation
import StoreKit

class PremiumManager: NSObject, ObservableObject {
  static let shared = PremiumManager()

  // Premium product identifier - would be defined in App Store Connect
  private let zipCodeUnlockProductID = "com.dontpullup.zipcode_upgrade"

  // Published properties for UI binding
  @Published var isLoading = false
  @Published var products: [SKProduct] = []
  @Published var purchaseError: String?
  @Published var purchaseSuccess = false

  // Store the transaction observer
  private var transactionObserver: Any?

  override init() {
    super.init()
    setupPurchases()
  }

  private func setupPurchases() {
    // Add transaction observer
    SKPaymentQueue.default().add(self)

    // Load products
    fetchProducts()
  }

  func fetchProducts() {
    isLoading = true

    let request = SKProductsRequest(productIdentifiers: [zipCodeUnlockProductID])
    request.delegate = self
    request.start()
  }

  func purchasePremium() {
    print("[PremiumManager] purchasePremium() called - products count: \(products.count)")

    // Always print simulator status for debugging
    #if targetEnvironment(simulator)
      print("[PremiumManager] Running in simulator environment")
    #else
      print("[PremiumManager] Running on a real device")
    #endif

    guard let product = products.first(where: { $0.productIdentifier == zipCodeUnlockProductID })
    else {
      // Special handling for simulator or when products can't load
      #if targetEnvironment(simulator)
        print("[PremiumManager] Running in simulator - simulating successful purchase")
        simulatePurchaseForTesting()
        return
      #else
        print("[PremiumManager] Product not found and not in simulator - showing error")
        purchaseError = "Product not available. Please try again later."
        return
      #endif
    }

    isLoading = true
    print("[PremiumManager] Found product, initiating purchase: \(product.productIdentifier)")

    // Create payment request
    let payment = SKPayment(product: product)
    SKPaymentQueue.default().add(payment)
  }

  // Special method to simulate purchases in simulator
  private func simulatePurchaseForTesting() {
    print("[PremiumManager] Starting simulated purchase flow")
    isLoading = true

    // Simulate network delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self else { return }

      print("[PremiumManager] Simulated purchase completed")

      // For simulator testing, just simulate success directly
      // This ensures testing works even without Firebase connection
      DispatchQueue.main.async {
        self.purchaseSuccess = true
        self.isLoading = false

        // Also post the notification for observers
        NotificationCenter.default.post(
          name: Notification.Name("UserPremiumStatusUpdated"), object: nil)

        print("[PremiumManager] Simulated purchase notification posted")

        // Print current state for debugging
        print(
          "[PremiumManager] Current state - success: \(self.purchaseSuccess), loading: \(self.isLoading), error: \(self.purchaseError ?? "none")"
        )
      }

      // Also try the real update for completeness
      self.updateUserPremiumStatus()
    }
  }

  func restorePurchases() {
    isLoading = true
    SKPaymentQueue.default().restoreCompletedTransactions()
  }

  // Update user's premium status in Firestore
  func updateUserPremiumStatus() {
    guard let currentUser = Auth.auth().currentUser else {
      print("[PremiumManager] No user logged in")
      return
    }

    let userRef = Firestore.firestore().collection("users").document(currentUser.uid)

    Task {
      do {
        try await userRef.updateData(["isPremium": true])
        print("[PremiumManager] User premium status updated successfully")

        // Update local state
        await MainActor.run {
          self.purchaseSuccess = true
          self.isLoading = false
        }

        // Post notification so other views can update
        NotificationCenter.default.post(
          name: Notification.Name("UserPremiumStatusUpdated"), object: nil)

      } catch {
        print("[PremiumManager] Error updating user premium status: \(error.localizedDescription)")

        await MainActor.run {
          self.purchaseError = "Failed to update premium status. Please contact support."
          self.isLoading = false
        }
      }
    }
  }

  func resetPurchaseState() {
    purchaseError = nil
    purchaseSuccess = false
  }

  deinit {
    // Remove transaction observer
    if transactionObserver != nil {
      SKPaymentQueue.default().remove(self)
    }
  }
}

// MARK: - SKProductsRequestDelegate
extension PremiumManager: SKProductsRequestDelegate {
  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      self.products = response.products
      self.isLoading = false

      if response.products.isEmpty {
        print("[PremiumManager] No products found")

        #if targetEnvironment(simulator)
          // In simulator, we'll proceed with empty products and use simulation logic
          print("[PremiumManager] Running in simulator - empty product list is expected")
        // No error message needed as we'll handle it in the purchasePremium() method
        #else
          self.purchaseError = "Premium upgrade temporarily unavailable. Please try again later."
        #endif
      } else {
        print("[PremiumManager] Found \(response.products.count) products")
      }

      if !response.invalidProductIdentifiers.isEmpty {
        print("[PremiumManager] Invalid products found: \(response.invalidProductIdentifiers)")
      }
    }
  }

  func request(_ request: SKRequest, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      self.isLoading = false
      self.purchaseError = "Failed to load premium options. Please try again later."
      print("[PremiumManager] Product request failed: \(error.localizedDescription)")
    }
  }
}

// MARK: - SKPaymentTransactionObserver
extension PremiumManager: SKPaymentTransactionObserver {
  func paymentQueue(
    _ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]
  ) {
    for transaction in transactions {
      switch transaction.transactionState {
      case .purchased:
        // Purchase successful
        handlePurchased(transaction)
      case .failed:
        // Purchase failed
        handleFailed(transaction)
      case .restored:
        // Purchase restored
        handleRestored(transaction)
      case .deferred, .purchasing:
        // Still in process, wait
        break
      @unknown default:
        break
      }
    }
  }

  func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      self.isLoading = false
      if !self.purchaseSuccess {
        self.purchaseError = "No previous purchases found to restore."
      }
    }
  }

  func paymentQueue(
    _ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      self.isLoading = false
      self.purchaseError = "Failed to restore purchases. Please try again later."
    }
  }

  private func handlePurchased(_ transaction: SKPaymentTransaction) {
    print("[PremiumManager] Transaction purchased: \(transaction.payment.productIdentifier)")

    // Verify the purchase is for our product
    if transaction.payment.productIdentifier == zipCodeUnlockProductID {
      // Update user's premium status
      updateUserPremiumStatus()
    }

    // Finish the transaction
    SKPaymentQueue.default().finishTransaction(transaction)
  }

  private func handleFailed(_ transaction: SKPaymentTransaction) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      self.isLoading = false
      if let error = transaction.error as? SKError {
        if error.code != .paymentCancelled {
          self.purchaseError = "Purchase failed: \(error.localizedDescription)"
        } else {
          // User canceled, no need for error message
          print("[PremiumManager] User cancelled purchase")
        }
      } else {
        self.purchaseError = "Purchase failed. Please try again later."
      }

      // Finish the transaction
      SKPaymentQueue.default().finishTransaction(transaction)
    }
  }

  private func handleRestored(_ transaction: SKPaymentTransaction) {
    print("[PremiumManager] Transaction restored: \(transaction.payment.productIdentifier)")

    // Verify the purchase is for our product
    if transaction.payment.productIdentifier == zipCodeUnlockProductID {
      // Update user's premium status
      updateUserPremiumStatus()
    }

    // Finish the transaction
    SKPaymentQueue.default().finishTransaction(transaction)
  }
}
