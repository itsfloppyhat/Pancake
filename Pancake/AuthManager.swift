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
    }

    /// Sign in with Apple
    func signIn() {
        // Clear any previous errors
        lastError = nil
        
        #if os(watchOS)
        // On watchOS, Sign in with Apple UI is limited; simulate success for now.
        simulateSignIn()
        #else
        // Use real Sign in with Apple on iOS/macOS
        performSignInWithApple()
        #endif
    }
    
    private func performSignInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    private func simulateSignIn() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Simulate successful sign-in
            let simulatedUserID = "user_\(UUID().uuidString.prefix(8))"
            self.isSignedIn = true
            self.userID = simulatedUserID
            self.lastError = nil
            
            // Persist state
            UserDefaults.standard.set(true, forKey: self.userDefaultsKey)
            UserDefaults.standard.set(simulatedUserID, forKey: self.userIDKey)
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

// MARK: - ASAuthorizationControllerDelegate
extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let userID = appleIDCredential.user
            
            DispatchQueue.main.async { [weak self] in
                self?.isSignedIn = true
                self?.userID = userID
                self?.lastError = nil
                
                // Persist state
                UserDefaults.standard.set(true, forKey: self?.userDefaultsKey ?? "")
                UserDefaults.standard.set(userID, forKey: self?.userIDKey ?? "")
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    self?.lastError = AuthError.userCancelled
                case .failed:
                    self?.lastError = AuthError.signInFailed
                case .invalidResponse:
                    self?.lastError = AuthError.signInFailed
                case .notHandled:
                    self?.lastError = AuthError.signInFailed
                case .unknown:
                    self?.lastError = AuthError.signInFailed
                case .notInteractive:
                    self?.lastError = AuthError.signInFailed
                case .matchedExcludedCredential:
                    self?.lastError = AuthError.signInFailed
                case .credentialImport:
                    self?.lastError = AuthError.signInFailed
                case .credentialExport:
                    self?.lastError = AuthError.signInFailed
                case .preferSignInWithApple:
                    self?.lastError = AuthError.signInFailed
                case .deviceNotConfiguredForPasskeyCreation:
                    self?.lastError = AuthError.signInFailed
                @unknown default:
                    self?.lastError = AuthError.signInFailed
                }
            } else {
                self?.lastError = AuthError.signInFailed
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the current window for presentation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        
        // Fallback - this shouldn't happen in normal circumstances
        return UIWindow()
    }
}
