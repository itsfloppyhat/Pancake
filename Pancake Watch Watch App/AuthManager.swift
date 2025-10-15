import Foundation
import AuthenticationServices
import Combine

enum AuthError: LocalizedError {
    case signInUnavailable
    case signInFailed
    case signOutFailed
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .signInUnavailable:
            return "Sign in is unavailable on this device"
        case .signInFailed:
            return "Sign in failed. Please try again"
        case .signOutFailed:
            return "Sign out failed. Please try again"
        case .userCancelled:
            return "Sign in was cancelled"
        }
    }
}

final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    private let userDefaultsKey = "appleSignInUserID"
    private let userIDKey = "appleSignInUserIDValue"

    @Published var isSignedIn: Bool = false
    @Published var lastError: Error?
    @Published var userID: String?

    private override init() {
        super.init()
        loadSignInState()
    }
    
    private func loadSignInState() {
        isSignedIn = UserDefaults.standard.bool(forKey: userDefaultsKey)
        userID = UserDefaults.standard.string(forKey: userIDKey)
        
        print("🔐 Watch AuthManager: Loaded sign-in state - isSignedIn: \(isSignedIn), userID: \(userID ?? "nil")")
    }

    /// Sign in with Apple (currently simulated)
    func signIn() {
        print("🔐 Watch AuthManager: Sign in requested")
        
        // Clear any previous errors
        lastError = nil
        
        #if os(watchOS)
        // On watchOS, Sign in with Apple UI is limited; simulate success for now.
        print("🔐 Watch AuthManager: Using simulated sign-in for watchOS")
        simulateSignIn()
        #else
        // If integrating real Sign in with Apple on iOS/macOS, kick off ASAuthorizationController here.
        // For now, simulate a successful sign-in.
        print("🔐 Watch AuthManager: Using simulated sign-in for iOS")
        simulateSignIn()
        #endif
    }
    
    private func simulateSignIn() {
        print("🔐 Watch AuthManager: Starting simulated sign-in...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Simulate successful sign-in
            let simulatedUserID = "user_\(UUID().uuidString.prefix(8))"
            print("🔐 Watch AuthManager: Simulated sign-in successful with ID: \(simulatedUserID)")
            
            self.isSignedIn = true
            self.userID = simulatedUserID
            self.lastError = nil
            
            // Persist state
            UserDefaults.standard.set(true, forKey: self.userDefaultsKey)
            UserDefaults.standard.set(simulatedUserID, forKey: self.userIDKey)
            
            print("🔐 Watch AuthManager: Sign-in state saved to UserDefaults")
        }
    }

    /// Sign out the current user
    func signOut() {
        isSignedIn = false
        userID = nil
        lastError = nil
        
        // Clear persisted state
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }
    
    /// Check if the user is currently signed in
    var isAuthenticated: Bool {
        return isSignedIn && userID != nil
    }
    
    /// Get a display name for the current user
    var displayName: String {
        if let userID = userID {
            return "User \(userID.suffix(4))"
        }
        return "Guest"
    }
}
