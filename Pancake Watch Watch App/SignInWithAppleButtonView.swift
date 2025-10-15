import SwiftUI
import AuthenticationServices

struct SignInWithAppleButtonView: View {
    @ObservedObject var authManager: AuthManager
    @State private var isPressed = false

    var body: some View {
        Group {
            #if os(watchOS)
            // watchOS fallback button (ASAuthorizationAppleIDButton isn't available on watchOS)
            Button(action: { authManager.signIn() }) {
                HStack {
                    Image(systemName: "applelogo")
                        .font(.title2)
                    Text("Sign in with Apple")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .cornerRadius(8)
            }
            #else
            // iOS/macOS/tvOS implementation using AuthenticationServices
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        let userID = appleIDCredential.user
                        DispatchQueue.main.async {
                            authManager.isSignedIn = true
                            authManager.userID = userID
                            authManager.lastError = nil
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
                            case .failed, .invalidResponse, .notHandled, .unknown, .notInteractive, .matchedExcludedCredential, .credentialImport, .credentialExport, .preferSignInWithApple, .deviceNotConfiguredForPasskeyCreation:
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
            .frame(height: 44)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            #endif
        }
        .accessibilityLabel("Sign in with Apple")
        .accessibilityHint("Tap to sign in with your Apple ID")
    }
}

#if DEBUG
#Preview {
    SignInWithAppleButtonView(authManager: AuthManager.shared)
        .padding()
}
#endif
