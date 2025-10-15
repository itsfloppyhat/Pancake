import Foundation
import Combine

// MARK: - App ViewModel
@MainActor
final class AppViewModel: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var allPermissionsGranted: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // Dependencies
    private let authManager = AuthManager.shared
    private let healthKitManager = HealthKitManager.shared
    private let locationManager = LocationManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        checkInitialState()
    }
    
    private func setupBindings() {
        // Bind authentication state
        authManager.$isSignedIn
            .assign(to: &$isSignedIn)
        
        // Bind permissions state
        Publishers.CombineLatest(
            healthKitManager.$isAuthorized,
            locationManager.$isAuthorized
        )
        .map { healthAuthorized, locationAuthorized in
            healthAuthorized && locationAuthorized
        }
        .assign(to: &$allPermissionsGranted)
        
        // Bind error states
        Publishers.Merge3(
            authManager.$lastError.compactMap { $0 },
            healthKitManager.$lastAuthorizationError.compactMap { $0 },
            locationManager.$lastError.compactMap { $0 }
        )
        .assign(to: &$error)
    }
    
    private func checkInitialState() {
        Task {
            await refreshAuthorizationState()
        }
    }
    
    func refreshAuthorizationState() async {
        isLoading = true
        await healthKitManager.refreshAuthorizationState()
        isLoading = false
    }
    
    func signIn() {
        authManager.signIn()
    }
    
    func signOut() {
        authManager.signOut()
    }
    
    func requestHealthAuthorization() {
        healthKitManager.requestAuthorization()
    }
    
    func requestLocationAuthorization() {
        locationManager.requestAuthorization()
    }
}
