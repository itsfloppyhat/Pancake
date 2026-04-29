import Foundation

// MARK: - Intensity
enum Intensity: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .easy: return "green"
        case .medium: return "orange"
        case .hard: return "red"
        }
    }

    var description: String {
        switch self {
        case .easy: return "Comfortable pace, can hold a conversation"
        case .medium: return "Moderate effort, breathing harder"
        case .hard: return "High effort, difficult to speak"
        }
    }
}

// MARK: - Target
enum Target: Codable, Identifiable, Equatable, Hashable {
    case time(seconds: Int)
    case distance(meters: Int)

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    enum TargetType: String, Codable {
        case time
        case distance
    }

    var id: String {
        switch self {
        case .time(let seconds): return "time-\(seconds)"
        case .distance(let meters): return "distance-\(meters)"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TargetType.self, forKey: .type)
        switch type {
        case .time:
            let seconds = try container.decode(Int.self, forKey: .value)
            self = .time(seconds: seconds)
        case .distance:
            let meters = try container.decode(Int.self, forKey: .value)
            self = .distance(meters: meters)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .time(let seconds):
            try container.encode(TargetType.time, forKey: .type)
            try container.encode(seconds, forKey: .value)
        case .distance(let meters):
            try container.encode(TargetType.distance, forKey: .type)
            try container.encode(meters, forKey: .value)
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .time(let seconds):
            hasher.combine("time")
            hasher.combine(seconds)
        case .distance(let meters):
            hasher.combine("distance")
            hasher.combine(meters)
        }
    }
}

// MARK: - RunSegment
struct RunSegment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var intensity: Intensity
    var target: Target

    init(id: UUID = UUID(), intensity: Intensity = .easy, target: Target = .time(seconds: 300)) {
        self.id = id
        self.intensity = intensity
        self.target = target
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(intensity)
        hasher.combine(target)
    }
}

// MARK: - WorkoutDataPoint
struct WorkoutDataPoint: Codable, Equatable, Hashable {
    let timestamp: TimeInterval      // seconds since workout start
    let heartRate: Int?
    let cadence: Double?
    let distanceMeters: Double
    let paceSecondsPerKm: Double?    // nil if distance is 0
    let currentSongTitle: String?
    let currentSongArtist: String?
}

// MARK: - SongPeriod
struct SongPeriod: Codable, Equatable, Hashable {
    let songTitle: String
    let artist: String
    let startTimestamp: TimeInterval  // seconds since workout start
    let endTimestamp: TimeInterval?   // nil if still playing when workout ended
}

// MARK: - RunEvent
struct RunEvent: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let date: Date
    let totalDistanceMeters: Int
    let totalTimeSeconds: Int
    let segments: [RunSegment]
    let dataPoints: [WorkoutDataPoint]
    let songHistory: [SongPeriod]

    enum CodingKeys: String, CodingKey {
        case id, date, totalDistanceMeters, totalTimeSeconds, segments, dataPoints, songHistory
    }

    init(id: UUID = UUID(), date: Date = Date(), totalDistanceMeters: Int, totalTimeSeconds: Int, segments: [RunSegment], dataPoints: [WorkoutDataPoint] = [], songHistory: [SongPeriod] = []) {
        self.id = id
        self.date = date
        self.totalDistanceMeters = totalDistanceMeters
        self.totalTimeSeconds = totalTimeSeconds
        self.segments = segments
        self.dataPoints = dataPoints
        self.songHistory = songHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        totalDistanceMeters = try container.decode(Int.self, forKey: .totalDistanceMeters)
        totalTimeSeconds = try container.decode(Int.self, forKey: .totalTimeSeconds)
        segments = try container.decode([RunSegment].self, forKey: .segments)
        dataPoints = try container.decodeIfPresent([WorkoutDataPoint].self, forKey: .dataPoints) ?? []
        songHistory = try container.decodeIfPresent([SongPeriod].self, forKey: .songHistory) ?? []
    }

    var effortSummary: String {
        if segments.count == 1 {
            return segments.first?.intensity.label ?? "Unknown"
        } else {
            return "Intervals"
        }
    }

    var averagePacePerKm: TimeInterval? {
        guard totalDistanceMeters > 0 else { return nil }
        return Double(totalTimeSeconds) / (Double(totalDistanceMeters) / 1000.0)
    }

    var formattedPace: String? {
        guard let pace = averagePacePerKm else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    var averageHeartRate: Int? {
        let hrPoints = dataPoints.compactMap { $0.heartRate }
        guard !hrPoints.isEmpty else { return nil }
        return hrPoints.reduce(0, +) / hrPoints.count
    }

    var hasDetailedData: Bool {
        !dataPoints.isEmpty
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(date)
        hasher.combine(totalDistanceMeters)
        hasher.combine(totalTimeSeconds)
        hasher.combine(segments)
    }
}

// MARK: - WatchMessageType
enum WatchMessageType: String, CaseIterable {
    // Run Planning
    case runPlan = "runPlan"
    case startRun = "startRun"

    // Workout Management
    case workoutStart = "workoutStart"
    case workoutStop = "workoutStop"
    case workoutUpdate = "workoutUpdate"
    case workoutCompleted = "workoutCompleted"
    case workoutStarted = "workoutStarted"

    // Music Control
    case requestMusicSuggestion = "requestMusicSuggestion"
    case playbackControl = "playbackControl"
    case currentSong = "currentSong"
    case musicSuggestion = "musicSuggestion"

    // Health Data
    case workoutHeartRate = "workoutHeartRate"
}

// MARK: - Target Convenience Extensions
extension Target {
    var isTime: Bool {
        if case .time = self { return true }
        return false
    }

    var isDistance: Bool {
        if case .distance = self { return true }
        return false
    }

    var timeSeconds: Int {
        if case .time(let seconds) = self { return seconds }
        return 0
    }

    var distanceMeters: Int {
        if case .distance(let meters) = self { return meters }
        return 0
    }
}

// MARK: - RunSegment Extensions
extension RunSegment {
    var targetDuration: TimeInterval {
        switch target {
        case .time(let seconds):
            return TimeInterval(seconds)
        case .distance:
            return 0
        }
    }
}

// MARK: - Formatting Extensions
extension Int {
    func formattedTime() -> String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func formattedDuration() -> String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60

        if hours > 0 {
            if minutes > 0 {
                return String(format: "%d hr %d min", hours, minutes)
            } else {
                return String(format: "%d hr", hours)
            }
        } else if minutes > 0 {
            return String(format: "%d min", minutes)
        } else {
            return String(format: "%d sec", seconds)
        }
    }

    func formattedDistanceMeters() -> String {
        if self >= 1000 {
            let km = Double(self) / 1000.0
            if km == floor(km) {
                return String(format: "%.0f km", km)
            } else {
                return String(format: "%.1f km", km)
            }
        } else {
            return "\(self) m"
        }
    }
}
