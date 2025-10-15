import SwiftUI
import AuthenticationServices

struct SignInWithAppleButtonView: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            // Configure the request
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            // Handle the result
            switch result {
            case .success(let authorization):
                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    let userID = appleIDCredential.user
                    
                    DispatchQueue.main.async {
                        authManager.isSignedIn = true
                        authManager.userID = userID
                        authManager.lastError = nil
                        
                        // Persist state
                        UserDefaults.standard.set(true, forKey: "appleSignInUserID")
                        UserDefaults.standard.set(userID, forKey: "appleSignInUserIDValue")
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    if let authError = error as? ASAuthorizationError {
                        switch authError.code {
                        case .canceled:
                            authManager.lastError = AuthError.userCancelled
                        case .failed:
                            authManager.lastError = AuthError.signInFailed
                        case .invalidResponse:
                            authManager.lastError = AuthError.signInFailed
                        case .notHandled:
                            authManager.lastError = AuthError.signInFailed
                        case .unknown:
                            authManager.lastError = AuthError.signInFailed
                        case .notInteractive:
                            authManager.lastError = AuthError.signInFailed
                        case .matchedExcludedCredential:
                            authManager.lastError = AuthError.signInFailed
                        case .credentialImport:
                            authManager.lastError = AuthError.signInFailed
                        case .credentialExport:
                            authManager.lastError = AuthError.signInFailed
                        case .preferSignInWithApple:
                            authManager.lastError = AuthError.signInFailed
                        case .deviceNotConfiguredForPasskeyCreation:
                            authManager.lastError = AuthError.signInFailed
                        @unknown default:
                            authManager.lastError = AuthError.signInFailed
                        }
                    } else {
                        authManager.lastError = AuthError.signInFailed
                    }
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .accessibilityLabel("Sign in with Apple")
        .accessibilityHint("Tap to sign in with your Apple ID")
    }
}

@available(*, deprecated, message: "Use SignInWithAppleButtonView(authManager:) from SignInWithAppleButtonView.swift")
struct DeprecatedSignInWithAppleButtonView: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            // Configure the request
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            // Handle the result
            switch result {
            case .success(let authorization):
                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    let userID = appleIDCredential.user
                    
                    DispatchQueue.main.async {
                        authManager.isSignedIn = true
                        authManager.userID = userID
                        authManager.lastError = nil
                        
                        // Persist state
                        UserDefaults.standard.set(true, forKey: "appleSignInUserID")
                        UserDefaults.standard.set(userID, forKey: "appleSignInUserIDValue")
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    if let authError = error as? ASAuthorizationError {
                        switch authError.code {
                        case .canceled:
                            authManager.lastError = AuthError.userCancelled
                        case .failed:
                            authManager.lastError = AuthError.signInFailed
                        case .invalidResponse:
                            authManager.lastError = AuthError.signInFailed
                        case .notHandled:
                            authManager.lastError = AuthError.signInFailed
                        case .unknown:
                            authManager.lastError = AuthError.signInFailed
                        case .notInteractive:
                            authManager.lastError = AuthError.signInFailed
                        case .matchedExcludedCredential:
                            authManager.lastError = AuthError.signInFailed
                        case .credentialImport:
                            authManager.lastError = AuthError.signInFailed
                        case .credentialExport:
                            authManager.lastError = AuthError.signInFailed
                        case .preferSignInWithApple:
                            authManager.lastError = AuthError.signInFailed
                        case .deviceNotConfiguredForPasskeyCreation:
                            authManager.lastError = AuthError.signInFailed
                        @unknown default:
                            authManager.lastError = AuthError.signInFailed
                        }
                    } else {
                        authManager.lastError = AuthError.signInFailed
                    }
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .accessibilityLabel("Sign in with Apple")
        .accessibilityHint("Tap to sign in with your Apple ID")
    }
}
