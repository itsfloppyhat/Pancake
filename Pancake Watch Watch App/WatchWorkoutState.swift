import Foundation

enum WorkoutAlertTiming {
    static let displayDuration: TimeInterval = 4
}

/// Keeps a single start attempt and its plan intact through the music choice
/// and countdown. Nothing here creates a workout or starts music.
struct WatchWorkoutStartFlow {
    enum Phase: Equatable {
        case idle
        case choosingMusic
        case countingDown(Int)
        case starting
    }

    struct StartRequest {
        let segments: [RunSegment]
        let startAdaptiveMix: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var attemptID: UUID?
    private var segments: [RunSegment] = []
    private var startAdaptiveMix = false

    var countdownAttemptID: UUID? {
        guard case .countingDown = phase else { return nil }
        return attemptID
    }

    @discardableResult
    mutating func begin(segments: [RunSegment]) -> Bool {
        guard phase == .idle, !segments.isEmpty else { return false }
        self.segments = segments
        startAdaptiveMix = false
        attemptID = UUID()
        phase = .choosingMusic
        return true
    }

    mutating func chooseMusic(_ enabled: Bool) {
        guard phase == .choosingMusic else { return }
        startAdaptiveMix = enabled
        phase = .countingDown(3)
    }

    /// Called after each visible number has been on screen for one second.
    /// A cancelled or superseded countdown cannot start another attempt.
    mutating func advanceCountdown(attemptID: UUID) -> StartRequest? {
        guard self.attemptID == attemptID,
              case .countingDown(let remaining) = phase else { return nil }
        if remaining > 1 {
            phase = .countingDown(remaining - 1)
            return nil
        }
        phase = .starting
        return StartRequest(segments: segments, startAdaptiveMix: startAdaptiveMix)
    }

    mutating func cancelPreparation() {
        switch phase {
        case .choosingMusic, .countingDown:
            reset()
        case .idle, .starting:
            break
        }
    }

    mutating func reset() {
        self = WatchWorkoutStartFlow()
    }
}

/// A durable copy of the result, independent of the HealthKit session's lifetime.
struct WorkoutSummary: Codable, Identifiable {
    let id: UUID
    let totalSeconds: Int
    let totalDistanceKm: Double
    let activeCalories: Double
    let segmentCount: Int
    let interruptionMessage: String?
    var healthSaveMessage: String?

    var formattedPace: String? {
        guard totalDistanceKm > 0 else { return nil }
        let paceSeconds = Double(totalSeconds) / totalDistanceKm
        return DistanceUnit.preferred.formattedPace(secondsPerKm: paceSeconds)
    }
}

struct IntervalChangePrompt: Identifiable, Equatable {
    let runID: UUID
    let segmentIndex: Int
    let intensity: Intensity
    let target: Target

    var id: String { "\(runID.uuidString):\(segmentIndex)" }

    var targetDescription: String {
        switch target {
        case .time(let seconds): return seconds.formattedDuration()
        case .distance(let meters): return meters.formattedDistanceMeters()
        }
    }

    func isCurrent(runID: UUID?, segmentIndex: Int, isRunning: Bool) -> Bool {
        isRunning && self.runID == runID && self.segmentIndex == segmentIndex
    }
}

struct PendingWatchRunPlan: Codable {
    let id: String
    let sentAt: Date
    let segments: [RunSegment]

    func isUsable(at date: Date, expiry: TimeInterval) -> Bool {
        !segments.isEmpty && date.timeIntervalSince(sentAt) < expiry
    }
}
