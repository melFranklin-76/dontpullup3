import Firebase
import FirebaseFirestore

// Make this public to avoid redeclaration issues
public final class FirebaseManager {
  public static let shared = FirebaseManager()
  private let db: Firestore

  private init() {
    // Don't initialize Firebase here, rely on AppDelegate initialization
    // This prevents multiple initialization attempts
    self.db = Firestore.firestore()
    print("[FirebaseManager] Using existing Firebase configuration")
  }

  public func firestore() -> Firestore { db }
}
