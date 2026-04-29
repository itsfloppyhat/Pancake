import Foundation
import AuthenticationServices
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum AuthError: LocalizedError {
    case signInUnavailable
    case signInFailed
    case signOutFailed
    case userCancelled
    case credentialRevoked

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
        case .credentialRevoked:
            return "Your Apple sign-in was revoked. Please sign in again."
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
        observeCredentialRevocation()
        validateCredentialState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func loadSignInState() {
        let storedUserID = UserDefaults.standard.string(forKey: userIDKey)
        userID = storedUserID
        isSignedIn = UserDefaults.standard.bool(forKey: userDefaultsKey) && storedUserID != nil
    }

    /// Handle the result from a `SignInWithAppleButton` completion.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            handleAuthorization(authorization)
        case .failure(let error):
            handleAuthorizationError(error)
        }
    }

    private func observeCredentialRevocation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCredentialRevokedNotification),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
    }

    @objc private func handleCredentialRevokedNotification() {
        validateCredentialState()
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
        clearSignInState(error: nil)
    }

    /// Validate the persisted Apple credential. Call on launch and when the app returns foreground.
    func validateCredentialState() {
        guard let userID else {
            clearSignInState(error: nil)
            return
        }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.lastError = error
                    return
                }

                switch state {
                case .authorized:
                    self.isSignedIn = true
                    self.lastError = nil
                    UserDefaults.standard.set(true, forKey: self.userDefaultsKey)
                    UserDefaults.standard.set(userID, forKey: self.userIDKey)
                case .revoked, .notFound, .transferred:
                    self.clearSignInState(error: AuthError.credentialRevoked)
                @unknown default:
                    self.clearSignInState(error: AuthError.credentialRevoked)
                }
            }
        }
    }

    private func clearSignInState(error: Error?) {
        isSignedIn = false
        userID = nil
        lastError = error

        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    private func persistSignedInUser(_ userID: String) {
        isSignedIn = true
        self.userID = userID
        lastError = nil
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
        UserDefaults.standard.set(userID, forKey: userIDKey)
    }

    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            lastError = AuthError.signInFailed
            return
        }

        persistSignedInUser(appleIDCredential.user)
        validateCredentialState()
    }

    private func handleAuthorizationError(_ error: Error) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                lastError = AuthError.userCancelled
            case .failed, .invalidResponse, .notHandled, .unknown, .notInteractive,
                    .matchedExcludedCredential, .credentialImport, .credentialExport,
                    .preferSignInWithApple, .deviceNotConfiguredForPasskeyCreation:
                lastError = AuthError.signInFailed
            @unknown default:
                lastError = AuthError.signInFailed
            }
        } else {
            lastError = AuthError.signInFailed
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.handleAuthorization(authorization)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.handleAuthorizationError(error)
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS) || os(tvOS)
        // Prefer an active foreground window scene and its key window
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        // Try key window first
        for scene in scenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
        }

        // Fall back to any window in the active scenes
        for scene in scenes {
            if let anyWindow = scene.windows.first {
                return anyWindow
            }
        }

        // If no key or any window found, create a new window with the first available scene.
        if let scene = scenes.first {
            // Create a window using the modern initializer that requires a UIWindowScene.
            let window = UIWindow(windowScene: scene)
            return window
        }

        // Last resort: use any connected scene.
        if let anyScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return UIWindow(windowScene: anyScene)
        }

        // Unreachable — all iOS apps have at least one UIWindowScene.
        fatalError("No UIWindowScene available for ASAuthorizationController presentation")
        #else
        fatalError("ASAuthorizationControllerPresentationContextProviding is not supported on this platform")
        #endif
    }
}
