import SwiftUI

enum RunReplayPalette {
    static let songs: [Color] = [.pastelPeriwinkle, .pastelMint, .pastelPeach, .pastelLavender, .pastelRose, .pastelSky, .pastelLemon, .pastelLilac]

    static func song(_ index: Int?) -> Color {
        index.map { songs[$0 % songs.count] } ?? Color.secondary.opacity(0.35)
    }

    static func heartRate(_ sample: RunReplaySample) -> Color {
        let target = Double(sample.targetHeartRate ?? 133)
        let deviation = abs(Double(sample.heartRate ?? 0) - target) / max(1, target)
        let strength = min(1, deviation / 0.25)
        switch ReplayHeartEffort.classify(heartRate: sample.heartRate, target: sample.targetHeartRate) {
        case .below: return Color(red: 0.18, green: 0.62 - 0.30 * strength, blue: 0.98 - 0.2 * strength)
        case .onTarget: return Color(red: 0.12, green: 0.72 - 0.15 * strength, blue: 0.36)
        case .above: return Color(red: 0.98 - 0.23 * strength, green: 0.38 - 0.26 * strength, blue: 0.36 - 0.2 * strength)
        case .unknown: return .secondary.opacity(0.35)
        }
    }

    static func pace(_ pace: Double?, range: ClosedRange<Double>) -> Color {
        guard let pace else { return .secondary.opacity(0.35) }
        let speed = 1 - min(1, max(0, (pace - range.lowerBound) / max(1, range.upperBound - range.lowerBound)))
        return Color(red: 0.15 + 0.21 * speed, green: 0.78 - 0.55 * speed, blue: 0.78 + 0.15 * speed)
    }

    static func paceRange(_ samples: [RunReplaySample]) -> ClosedRange<Double> {
        let values = samples.compactMap(\.pace).sorted()
        guard let first = values.first, let last = values.last else { return 240...600 }
        return first...max(first + 30, last)
    }

    static func formatPace(_ pace: Double?) -> String {
        guard let pace, pace.isFinite, pace > 0 else { return "—" }
        let seconds = Int(pace.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
