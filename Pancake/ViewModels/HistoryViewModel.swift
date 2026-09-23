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
    @Published var persistenceError: String?
    
    private let runHistoryStore = RunHistoryStore.shared
    private let healthKitManager = HealthKitManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        runHistoryStore.$events
            .assign(to: &$events)
        runHistoryStore.$persistenceError
            .assign(to: &$persistenceError)
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
        // The history store loads its durable local file on initialization
        // This method can be used for future network sync if needed
    }
    
    // MARK: - Statistics
    func getFormattedTotalDistance() -> String {
        DistanceUnit.preferred.formattedTarget(meters: Int((totalDistanceKm * 1000).rounded()))
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
        return DistanceUnit.preferred.formattedPace(secondsPerKm: pace)
    }
    
    // MARK: - Health Integration
    
    /// Check if Health access is ready
    var isHealthKitAuthorized: Bool {
        healthKitManager.isAuthorized
    }
    
    /// Request Health authorization
    func requestHealthKitAuthorization() {
        healthKitManager.requestAuthorization()
    }
    
    /// Import outdoor running workouts from Health
    func importFromHealthKit() async {
        guard !isImportingFromHealthKit else { return }
        
        isImportingFromHealthKit = true
        error = nil
        importResult = nil
        
        do {
            let importedCount = try await runHistoryStore.importFromHealthKit()
            
            if importedCount > 0 {
                importResult = "Successfully imported \(importedCount) outdoor runs from Health"
            } else {
                importResult = "No new outdoor runs found in Health (minimum \(DistanceUnit.preferred.formattedDistance(meters: 500)))"
            }
        } catch {
            self.error = error
            importResult = "Failed to import from Health: \(error.localizedDescription)"
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
