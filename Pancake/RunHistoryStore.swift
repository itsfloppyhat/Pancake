import Foundation
import Combine

@MainActor
final class RunHistoryStore: ObservableObject {
    static let shared = RunHistoryStore()

    @Published private(set) var events: [RunEvent] = []
    @Published private(set) var persistenceError: String?

    private var repository: RunHistoryRepository?
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    private init() {
        do {
            try loadRepository()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    /// Returns only after the run is on disk, or leaves the previous history
    /// untouched on failure. Callers must retain their recovery checkpoint then.
    @discardableResult
    func add(event: RunEvent) -> Bool {
        do {
            let repository = try loadRepository()
            try repository.add(event)
            events = repository.events
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    func contains(runID: UUID) -> Bool {
        events.contains { $0.id == runID }
    }

    func remove(event: RunEvent) {
        replaceEvents(events.filter { $0.id != event.id })
    }

    @discardableResult
    private func loadRepository() throws -> RunHistoryRepository {
        if let repository { return repository }
        let loaded = try RunHistoryRepository(directory: directory)
        repository = loaded
        events = loaded.events
        return loaded
    }

    private func replaceEvents(_ updated: [RunEvent]) {
        do {
            let repository = try loadRepository()
            try repository.replace(with: updated)
            events = repository.events
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    var totalDistanceKm: Double {
        events.reduce(0) { $0 + Double($1.totalDistanceMeters) / 1000.0 }
    }

    var totalDurationSeconds: Int {
        events.reduce(0) { $0 + $1.totalTimeSeconds }
    }

    var averagePacePerKm: TimeInterval? {
        guard totalDistanceKm > 0 else { return nil }
        return Double(totalDurationSeconds) / totalDistanceKm
    }

    var runCount: Int { events.count }
    var mostRecentRunDate: Date? { events.first?.date }

    func importFromHealthKit() async throws -> Int {
        let healthKitManager = HealthKitManager.shared
        guard healthKitManager.isAuthorized else { throw HealthKitError.notAuthorized }
        let importedEvents = try await healthKitManager.importRunningHistory()
        let repository = try loadRepository()
        let existingKeys = Set(events.map { "\($0.date.timeIntervalSince1970)-\($0.totalDistanceMeters)" })
        let newEvents = importedEvents.filter {
            !existingKeys.contains("\($0.date.timeIntervalSince1970)-\($0.totalDistanceMeters)")
        }
        try repository.replace(with: events + newEvents)
        events = repository.events
        persistenceError = nil
        return newEvents.count
    }

    func clearHealthKitData() {
        replaceEvents([])
    }
}
