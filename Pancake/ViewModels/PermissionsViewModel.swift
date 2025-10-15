import Foundation
import Combine

// MARK: - Permissions ViewModel
@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var healthKitAuthorized: Bool = false
    @Published var locationAuthorized: Bool = false
    @Published var healthKitError: Error?
    @Published var locationError: Error?
    @Published var isRequestingHealth: Bool = false
    @Published var isRequestingLocation: Bool = false
    
    private let healthKitManager = HealthKitManager.shared
    private let locationManager = LocationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        healthKitManager.$isAuthorized
            .assign(to: &$healthKitAuthorized)
        
        locationManager.$isAuthorized
            .assign(to: &$locationAuthorized)
        
        healthKitManager.$lastAuthorizationError
            .assign(to: &$healthKitError)
        
        locationManager.$lastError
            .assign(to: &$locationError)
    }
    
    var allPermissionsGranted: Bool {
        healthKitAuthorized && locationAuthorized
    }
    
    var hasAnyError: Bool {
        healthKitError != nil || locationError != nil
    }
    
    func requestHealthAuthorization() {
        isRequestingHealth = true
        healthKitManager.requestAuthorization()
        
        // Reset loading state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isRequestingHealth = false
        }
    }
    
    func requestLocationAuthorization() {
        isRequestingLocation = true
        locationManager.requestAuthorization()
        
        // Reset loading state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isRequestingLocation = false
        }
    }
    
    func clearErrors() {
        healthKitError = nil
        locationError = nil
    }
}
