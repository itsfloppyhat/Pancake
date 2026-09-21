import Foundation

/// A snapshot of a run that is still in progress, written to disk as the run
/// accumulates so the iPhone can still save a complete run event after being
/// suspended or terminated mid-run.
struct ActiveRunSnapshot: Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var segments: [RunSegment]
    var currentSegmentIndex: Int
    var totalDistanceKm: Double
    var totalTimeSeconds: Int
    var dataPoints: [WorkoutDataPoint]
    var songHistory: [SongPeriod]

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        segments: [RunSegment],
        currentSegmentIndex: Int = 0,
        totalDistanceKm: Double = 0,
        totalTimeSeconds: Int = 0,
        dataPoints: [WorkoutDataPoint] = [],
        songHistory: [SongPeriod] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.segments = segments
        self.currentSegmentIndex = currentSegmentIndex
        self.totalDistanceKm = totalDistanceKm
        self.totalTimeSeconds = totalTimeSeconds
        self.dataPoints = dataPoints
        self.songHistory = songHistory
    }

    var hasRecordedProgress: Bool {
        totalTimeSeconds > 0 || totalDistanceKm > 0 || !dataPoints.isEmpty
    }
}

/// Decides what a run event should be saved with when the live run state and
/// the on-disk snapshot disagree — which is the normal case after the app was
/// killed mid-run and only came back to handle the completion message.
enum RunEventRecoveryPolicy {
    /// After this long with no completion message, an orphaned snapshot is
    /// flushed to history rather than waiting for one that is not coming.
    static let staleRunInterval: TimeInterval = 6 * 60 * 60

    struct Resolution: Equatable {
        let date: Date
        let totalDistanceMeters: Int
        let totalTimeSeconds: Int
        let segments: [RunSegment]
        let dataPoints: [WorkoutDataPoint]
        let songHistory: [SongPeriod]

        /// The watch's totals are authoritative, so anything with time or
        /// distance is worth keeping. Only a truly empty run is discarded.
        var isSavable: Bool {
            totalTimeSeconds > 0 || totalDistanceMeters > 0
        }
    }

    /// Live values win when present — they carry the watch's final totals —
    /// and the snapshot fills every gap the killed process left behind.
    static func resolve(
        liveSegments: [RunSegment]?,
        liveTotalDistanceKm: Double?,
        liveTotalTimeSeconds: Int?,
        liveDataPoints: [WorkoutDataPoint],
        liveSongHistory: [SongPeriod],
        snapshot: ActiveRunSnapshot?,
        completedAt: Date = Date()
    ) -> Resolution {
        Resolution(
            date: snapshot?.startedAt ?? completedAt,
            totalDistanceMeters: Int((liveTotalDistanceKm ?? snapshot?.totalDistanceKm ?? 0) * 1000.0),
            totalTimeSeconds: liveTotalTimeSeconds ?? snapshot?.totalTimeSeconds ?? 0,
            segments: liveSegments ?? snapshot?.segments ?? [],
            dataPoints: liveDataPoints.isEmpty ? (snapshot?.dataPoints ?? []) : liveDataPoints,
            songHistory: liveSongHistory.isEmpty ? (snapshot?.songHistory ?? []) : liveSongHistory
        )
    }

    static func isStale(_ snapshot: ActiveRunSnapshot, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.startedAt) >= staleRunInterval
    }
}

/// Persists the in-flight run snapshot and remembers which runs already reached
/// history, so a late completion message cannot save the same run twice.
@MainActor
final class ActiveRunStateStore {
    static let shared = ActiveRunStateStore()

    private(set) var snapshot: ActiveRunSnapshot?

    private let fileURL: URL
    private let savedRunIDsKey = "ActiveRunStateStore.savedRunIDs"
    private let maximumRememberedRunIDs = 20
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults

        let baseDirectory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        fileURL = baseDirectory.appendingPathComponent("PancakeActiveRun.json")

        load()
    }

    // MARK: - Lifecycle

    func beginRun(id: UUID = UUID(), segments: [RunSegment], startedAt: Date = Date()) {
        snapshot = ActiveRunSnapshot(id: id, startedAt: startedAt, segments: segments)
        save()
    }

    func update(
        currentSegmentIndex: Int,
        totalDistanceKm: Double,
        totalTimeSeconds: Int,
        dataPoints: [WorkoutDataPoint],
        songHistory: [SongPeriod]
    ) {
        guard var current = snapshot else { return }

        current.currentSegmentIndex = currentSegmentIndex
        current.totalDistanceKm = totalDistanceKm
        current.totalTimeSeconds = totalTimeSeconds
        current.dataPoints = dataPoints
        current.songHistory = songHistory

        snapshot = current
        save()
    }

    func clear() {
        snapshot = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Duplicate Protection

    func hasSaved(runID: UUID) -> Bool {
        savedRunIDs.contains(runID.uuidString)
    }

    func markSaved(runID: UUID) {
        var identifiers = savedRunIDs
        identifiers.removeAll { $0 == runID.uuidString }
        identifiers.append(runID.uuidString)
        defaults.set(Array(identifiers.suffix(maximumRememberedRunIDs)), forKey: savedRunIDsKey)
    }

    private var savedRunIDs: [String] {
        defaults.stringArray(forKey: savedRunIDsKey) ?? []
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            snapshot = nil
            return
        }

        do {
            snapshot = try JSONDecoder().decode(ActiveRunSnapshot.self, from: data)
        } catch {
            print("Failed to load active run snapshot: \(error)")
            snapshot = nil
        }
    }

    private func save() {
        guard let snapshot else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save active run snapshot: \(error)")
        }
    }
}
