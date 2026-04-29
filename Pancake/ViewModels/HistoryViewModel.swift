import Foundation
import Combine

// MARK: - History ViewModel
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var events: [RunEvent] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var isImportingFromHealthKit: Bool = false
    @Published var importResult: String?
    
    private let runHistoryStore = RunHistoryStore.shared
    private let healthKitManager = HealthKitManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        runHistoryStore.$events
            .assign(to: &$events)
    }
    
    // MARK: - Computed Properties
    var hasEvents: Bool {
        !events.isEmpty
    }
    
    var totalDistanceKm: Double {
        runHistoryStore.totalDistanceKm
    }
    
    var totalDurationSeconds: Int {
        runHistoryStore.totalDurationSeconds
    }
    
    var averagePacePerKm: TimeInterval? {
        runHistoryStore.averagePacePerKm
    }
    
    var runCount: Int {
        runHistoryStore.runCount
    }
    
    var mostRecentRunDate: Date? {
        runHistoryStore.mostRecentRunDate
    }
    
    // MARK: - Actions
    func addEvent(_ event: RunEvent) {
        runHistoryStore.add(event: event)
    }
    
    func removeEvent(_ event: RunEvent) {
        runHistoryStore.remove(event: event)
    }
    
    func refreshHistory() {
        // The history store automatically loads from UserDefaults
        // This method can be used for future network sync if needed
    }
    
    // MARK: - Statistics
    func getFormattedTotalDistance() -> String {
        if totalDistanceKm >= 1.0 {
            return String(format: "%.1f km", totalDistanceKm)
        } else {
            return String(format: "%.0f m", totalDistanceKm * 1000)
        }
    }
    
    func getFormattedTotalDuration() -> String {
        let hours = totalDurationSeconds / 3600
        let minutes = (totalDurationSeconds % 3600) / 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    func getFormattedAveragePace() -> String? {
        guard let pace = averagePacePerKm else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
    
    // MARK: - HealthKit Integration
    
    /// Check if HealthKit is authorized
    var isHealthKitAuthorized: Bool {
        healthKitManager.isAuthorized
    }
    
    /// Request HealthKit authorization
    func requestHealthKitAuthorization() {
        healthKitManager.requestAuthorization()
    }
    
    /// Import outdoor running workouts from HealthKit
    func importFromHealthKit() async {
        guard !isImportingFromHealthKit else { return }
        
        isImportingFromHealthKit = true
        error = nil
        importResult = nil
        
        do {
            let importedCount = try await runHistoryStore.importFromHealthKit()
            
            if importedCount > 0 {
                importResult = "Successfully imported \(importedCount) outdoor runs from HealthKit"
            } else {
                importResult = "No new outdoor runs found in HealthKit (minimum 0.5km)"
            }
        } catch {
            self.error = error
            importResult = "Failed to import from HealthKit: \(error.localizedDescription)"
        }
        
        isImportingFromHealthKit = false
    }
    
    /// Clear all imported data
    func clearAllData() {
        runHistoryStore.clearHealthKitData()
        importResult = nil
        error = nil
    }
}
