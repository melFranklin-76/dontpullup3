import Firebase
import FirebaseFirestore

public final class FirebaseManager {
    public static let shared = FirebaseManager()
    
    private init() {}
    
    private lazy var db: Firestore = {
        // Assumes FirebaseApp.configure() has already been called in DontpullupApp.init()
        return Firestore.firestore()
    }()
    
    public func firestore() -> Firestore { db }
}
