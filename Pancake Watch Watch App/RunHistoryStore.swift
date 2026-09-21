import Foundation
import Combine

final class RunHistoryStore: ObservableObject {
    static let shared = RunHistoryStore()

    @Published private(set) var events: [RunEvent] = []

    private let storageKey = "RunHistoryStore.events"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(event: RunEvent) {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        events.insert(event, at: 0)
        save()
    }

    func remove(event: RunEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            events = try JSONDecoder().decode([RunEvent].self, from: data)
        } catch {
            print("Failed to load run events: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            defaults.set(data, forKey: storageKey)
        } catch {
            print("Failed to save run events: \(error)")
        }
    }

    // MARK: - Statistics

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

    var runCount: Int {
        events.count
    }

    var mostRecentRunDate: Date? {
        events.first?.date
    }
}
