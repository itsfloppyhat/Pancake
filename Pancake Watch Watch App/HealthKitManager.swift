import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var lastAuthorizationError: Error?
    @Published private(set) var missingRequiredShareTypeNames: [String] = []
    
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
            self.isAuthorized = false
            self.missingRequiredShareTypeNames = []
            self.lastAuthorizationError = HealthKitError.notAvailable
            return
        }

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            Task { @MainActor in
                self?.updateAuthorizationState(requestSucceeded: success)
                if let error = error {
                    self?.lastAuthorizationError = error
                }
            }
        }
    }

    func refreshAuthorizationState() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            self.isAuthorized = false
            self.missingRequiredShareTypeNames = []
            self.lastAuthorizationError = HealthKitError.notAvailable
            return
        }

        updateAuthorizationState()
    }
    
    // MARK: - Authorization Helpers

    private func updateAuthorizationState(requestSucceeded: Bool? = nil) {
        missingRequiredShareTypeNames = missingRequiredShareTypes().map(displayName(for:)).sorted()
        isAuthorized = missingRequiredShareTypeNames.isEmpty

        if isAuthorized {
            lastAuthorizationError = nil
        } else if !missingRequiredShareTypeNames.isEmpty {
            lastAuthorizationError = HealthKitError.missingRequiredShareTypes(missingRequiredShareTypeNames)
        } else if requestSucceeded == false {
            lastAuthorizationError = HealthKitError.requestFailed
        } else {
            lastAuthorizationError = HealthKitError.notAuthorized
        }
    }

    private func missingRequiredShareTypes() -> [HKSampleType] {
        // HealthKit does not expose read authorization status. Only share/write
        // status is reliable, and every share type below is required for a valid run.
        shareTypes.filter { healthStore.authorizationStatus(for: $0) != .sharingAuthorized }
    }

    private func displayName(for type: HKObjectType) -> String {
        if type.identifier == HKObjectType.workoutType().identifier {
            return "Workouts"
        }

        switch type.identifier {
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return "Walking + Running Distance"
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return "Active Energy"
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return "Heart Rate"
        default:
            return type.identifier
        }
    }
    
    /// Check if we have share authorization for a specific type.
    /// HealthKit intentionally does not expose read authorization status.
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
    case missingRequiredShareTypes([String])
    case requestFailed
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization is required"
        case .missingRequiredShareTypes(let names):
            return "HealthKit needs write access for: \(names.joined(separator: ", "))"
        case .requestFailed:
            return "Failed to request HealthKit authorization"
        }
    }
}
