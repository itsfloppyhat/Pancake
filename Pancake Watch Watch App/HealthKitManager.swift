import Foundation
import HealthKit
import Observation

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var lastAuthorizationError: Error?
    
    // MARK: - HealthKit Types
    private let readTypes: Set<HKObjectType>
    private let shareTypes: Set<HKSampleType>

    private init() {
        // Define the types we want to read and write
        var readTypes = Set<HKObjectType>()
        var shareTypes = Set<HKSampleType>()

        // Workout data
        let workoutType = HKObjectType.workoutType()
        shareTypes.insert(workoutType)
        
        // Distance data
        if let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            readTypes.insert(distanceType)
            shareTypes.insert(distanceType)
        }
        
        // Heart rate data
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRateType)
        }
        
        // Active energy data
        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergyType)
            shareTypes.insert(activeEnergyType)
        }
        
        self.readTypes = readTypes
        self.shareTypes = shareTypes
        
        // Proactively check authorization status on init
        Task { [weak self] in
            await self?.refreshAuthorizationState()
        }
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            self.lastAuthorizationError = HealthKitError.notAvailable
            return
        }

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            Task { @MainActor in
                if let error = error {
                    self?.lastAuthorizationError = error
                } else {
                    self?.lastAuthorizationError = nil
                }
                self?.isAuthorized = success && self?.hasAnyAuthorizationGranted() == true
            }
        }
    }

    func refreshAuthorizationState() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            self.isAuthorized = false
            self.lastAuthorizationError = HealthKitError.notAvailable
            return
        }

        self.isAuthorized = hasAnyAuthorizationGranted()
        if !isAuthorized {
            self.lastAuthorizationError = HealthKitError.notAuthorized
        } else {
            self.lastAuthorizationError = nil
        }
    }
    
    // MARK: - Authorization Helpers
    
    private func hasAnyAuthorizationGranted() -> Bool {
        // Check if we have authorization for any of our required types
        for type in readTypes {
            let status = healthStore.authorizationStatus(for: type)
            if status == .sharingAuthorized { return true }
        }
        for type in shareTypes {
            let status = healthStore.authorizationStatus(for: type)
            if status == .sharingAuthorized { return true }
        }
        return false
    }
    
    /// Check if we have authorization for a specific type
    func isAuthorized(for type: HKObjectType) -> Bool {
        return healthStore.authorizationStatus(for: type) == .sharingAuthorized
    }
    
    /// Get detailed authorization status for all our types
    func getAuthorizationStatus() -> [String: HKAuthorizationStatus] {
        var status: [String: HKAuthorizationStatus] = [:]
        
        for type in readTypes {
            status[type.identifier] = healthStore.authorizationStatus(for: type)
        }
        for type in shareTypes {
            status[type.identifier] = healthStore.authorizationStatus(for: type)
        }
        
        return status
    }
}

// MARK: - HealthKit Errors
enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case requestFailed
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization is required"
        case .requestFailed:
            return "Failed to request HealthKit authorization"
        }
    }
}
