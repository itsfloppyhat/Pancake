// Create a reusable HealthKitManager responsible for requesting HealthKit permissions.
// This file is self-contained and does not depend on other project files.

import Foundation
import HealthKit

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    let healthStore = HKHealthStore()

    // Expose whether HealthKit is available on this device
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // Published state to reflect authorization result in UI if desired
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var lastAuthorizationError: Error?

    // The data types we intend to read
    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [
            HKObjectType.workoutType()
        ]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            set.insert(heartRate)
        }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            set.insert(distance)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            set.insert(activeEnergy)
        }
        return set
    }

    // The data types we intend to write (optional but recommended to save workouts)
    private var shareTypes: Set<HKSampleType> {
        var set: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            set.insert(distance)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            set.insert(activeEnergy)
        }
        return set
    }

    // Request authorization for the above types. Call this from the watch app when preparing to start a workout.
    func requestAuthorization(completion: ((Bool, Error?) -> Void)? = nil) {
        guard isHealthDataAvailable else {
            let err = NSError(domain: "HealthKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Health data not available on this device."])
            self.lastAuthorizationError = err
            completion?(false, err)
            return
        }

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                self?.lastAuthorizationError = error
                completion?(success, error)
            }
        }
    }
}
