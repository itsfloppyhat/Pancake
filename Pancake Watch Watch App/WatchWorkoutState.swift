import Foundation

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
        return String(format: "%d:%02d/km", Int(paceSeconds) / 60, Int(paceSeconds) % 60)
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
