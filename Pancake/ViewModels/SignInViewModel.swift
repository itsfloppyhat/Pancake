import Foundation
import Combine

// MARK: - Sign In ViewModel
@MainActor
final class SignInViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        authManager.$lastError
            .assign(to: &$error)
    }
    
    var isSignedIn: Bool {
        authManager.isSignedIn
    }
    
    var displayName: String {
        authManager.displayName
    }
    
    func signIn() {
        isLoading = true
        authManager.signIn()
        // Note: isLoading will be reset when auth state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isLoading = false
        }
    }
    
    func clearError() {
        error = nil
    }
}
