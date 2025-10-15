import SwiftUI
import AuthenticationServices

struct SignInWithAppleButtonView: View {
    @Environment(\.__isPresented) private var isPresented // placeholder to prevent unused warnings
    @ObservedObject var auth = AuthManager.shared

    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                // The manager prepares the request when starting; keep minimal here
            },
            onCompletion: { _ in
                // Handled by AuthManager delegate
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 44)
        .onTapGesture {
            auth.startSignInWithAppleFlow()
        }
        .accessibilityLabel("Sign in with Apple")
    }
}

#Preview {
    SignInWithAppleButtonView()
        .padding()
}
