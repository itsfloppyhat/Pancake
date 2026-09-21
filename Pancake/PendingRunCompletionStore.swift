import Foundation

/// Keeps completed Watch runs recoverable until their history commits succeed.
/// A separate inbox lets a delayed completion coexist with a newer active run.
final class PendingRunCompletionStore {
    private(set) var events: [RunEvent]
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("PancakePendingCompletions.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            events = try JSONDecoder().decode([RunEvent].self, from: Data(contentsOf: fileURL))
                .sorted { $0.date > $1.date }
        } else {
            events = []
        }
    }

    /// The latest completion replaces an earlier payload for the same run ID.
    /// Returns only after the new payload has been written successfully.
    func upsert(_ event: RunEvent) throws {
        var updated = events.filter { $0.id != event.id }
        updated.append(event)
        try replace(with: updated)
    }

    /// Call only after this run has reached durable history. Other pending runs
    /// remain available for retry, even when completions arrive out of order.
    func remove(runID: UUID) throws {
        try replace(with: events.filter { $0.id != runID })
    }

    private func replace(with updated: [RunEvent]) throws {
        let sorted = updated.sorted { $0.date > $1.date }
        let data = try JSONEncoder().encode(sorted)
        try data.write(to: fileURL, options: .atomic)
        events = sorted
    }
}
