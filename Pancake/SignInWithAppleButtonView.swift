import SwiftUI
import AuthenticationServices

struct SignInWithAppleButtonView: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            authManager.handleSignInResult(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .accessibilityLabel("Sign in with Apple")
        .accessibilityHint("Tap to sign in with your Apple ID")
    }
}
