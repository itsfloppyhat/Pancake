import Foundation

/// A completed run is committed atomically before callers may discard its
/// recovery checkpoint. Keeping the run ID makes a replay after a crash safe.
final class RunHistoryRepository {
    private(set) var events: [RunEvent]
    private let fileURL: URL

    init(directory: URL, defaults: UserDefaults = .standard) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("PancakeRunHistory.json")
        let legacyKey = "RunHistoryStore.events"

        if FileManager.default.fileExists(atPath: fileURL.path) {
            events = try JSONDecoder().decode([RunEvent].self, from: Data(contentsOf: fileURL))
        } else if let legacyData = defaults.data(forKey: legacyKey) {
            events = try JSONDecoder().decode([RunEvent].self, from: legacyData)
            try write(events)
            defaults.removeObject(forKey: legacyKey)
        } else {
            events = []
        }
        events.sort { $0.date > $1.date }
    }

    func add(_ event: RunEvent) throws {
        var updated = events.filter { $0.id != event.id }
        updated.append(event)
        try replace(with: updated)
    }

    func replace(with updated: [RunEvent]) throws {
        let sorted = updated.sorted { $0.date > $1.date }
        try write(sorted)
        events = sorted
    }

    private func write(_ events: [RunEvent]) throws {
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }
}
