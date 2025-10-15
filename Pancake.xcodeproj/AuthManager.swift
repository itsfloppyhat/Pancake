import Foundation
import AuthenticationServices
import CryptoKit
import Observation

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userIdentifier: String?
    @Published var lastError: Error?

    private let userDefaultsKey = "appleSignInUserID"
    private var currentNonce: String?

    private override init() {
        super.init()
        // Load persisted user identifier to auto sign-in
        if let id = UserDefaults.standard.string(forKey: userDefaultsKey) {
            self.userIdentifier = id
            self.isSignedIn = true
        }
    }

    func startSignInWithAppleFlow() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        self.isSignedIn = false
        self.userIdentifier = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let userID = credential.user
            // Persist the user identifier to remember sign-in
            UserDefaults.standard.set(userID, forKey: userDefaultsKey)
            self.userIdentifier = userID
            self.isSignedIn = true
            self.lastError = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.lastError = error
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Best-effort to find a key window for presentation
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

// MARK: - Nonce helpers
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var random: UInt8 = 0
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        if random < charset.count {
            result.append(charset[Int(random % UInt8(charset.count))])
            remainingLength -= 1
        }
    }
    return result
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}
