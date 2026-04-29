import Foundation

final class RunHistoryStore: ObservableObject {
    static let shared = RunHistoryStore()

    @Published private(set) var events: [RunEvent] = []

    private let storageKey = "RunHistoryStore.events"
    private let queue = DispatchQueue(label: "RunHistoryStore.queue")

    private init() {
        load()
    }

    func add(event: RunEvent) {
        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.events.insert(event, at: 0)
                self?.save()
            }
        }
    }

    func remove(event: RunEvent) {
        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.events.removeAll { $0.id == event.id }
                self?.save()
            }
        }
    }

    private func load() {
        queue.async { [weak self] in
            guard let data = UserDefaults.standard.data(forKey: self?.storageKey ?? "") else {
                DispatchQueue.main.async {
                    self?.events = []
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode([RunEvent].self, from: data)
                DispatchQueue.main.async {
                    self?.events = decoded
                }
            } catch {
                print("Failed to load run events: \(error)")
                DispatchQueue.main.async {
                    self?.events = []
                }
            }
        }
    }

    private func save() {
        let eventsToSave = events
        let key = storageKey
        queue.async {
            do {
                let data = try JSONEncoder().encode(eventsToSave)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                print("Failed to save run events: \(error)")
            }
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
