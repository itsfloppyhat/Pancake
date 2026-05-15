import Foundation

// MARK: - Intensity
enum Intensity: String, CaseIterable, Identifiable, Codable, Hashable {
    case zone1
    case zone2
    case zone3
    case zone4
    case zone5

    static let defaultMaxHeartRate = 190

    var id: String { rawValue }

    var zoneNumber: Int {
        switch self {
        case .zone1: return 1
        case .zone2: return 2
        case .zone3: return 3
        case .zone4: return 4
        case .zone5: return 5
        }
    }

    var label: String {
        "Zone \(zoneNumber)"
    }

    var color: String {
        switch self {
        case .zone1: return "blue"
        case .zone2: return "green"
        case .zone3: return "yellow"
        case .zone4: return "orange"
        case .zone5: return "red"
        }
    }

    var description: String {
        switch self {
        case .zone1: return "50-60% HRmax, very light recovery or warm-up"
        case .zone2: return "60-70% HRmax, easy aerobic base"
        case .zone3: return "70-80% HRmax, steady tempo effort"
        case .zone4: return "80-90% HRmax, hard threshold effort"
        case .zone5: return "90-100% HRmax, maximum short-interval effort"
        }
    }

    var percentRange: (lower: Double, upper: Double) {
        switch self {
        case .zone1: return (0.50, 0.60)
        case .zone2: return (0.60, 0.70)
        case .zone3: return (0.70, 0.80)
        case .zone4: return (0.80, 0.90)
        case .zone5: return (0.90, 1.00)
        }
    }

    var defaultTargetHeartRate: Int {
        targetHeartRate(maxHeartRate: Self.defaultMaxHeartRate)
    }

    func targetHeartRate(maxHeartRate: Int) -> Int {
        let range = percentRange
        return Int((Double(maxHeartRate) * ((range.lower + range.upper) / 2)).rounded())
    }

    static func fromStoredRawValue(_ rawValue: String) -> Intensity? {
        switch rawValue {
        case "easy":
            return .zone2
        case "medium":
            return .zone3
        case "hard":
            return .zone4
        default:
            return Intensity(rawValue: rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let intensity = Self.fromStoredRawValue(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown intensity value: \(rawValue)"
            )
        }

        self = intensity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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

    init(id: UUID = UUID(), intensity: Intensity = .zone2, target: Target = .time(seconds: 300)) {
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

// MARK: - RunEvent
struct RunEvent: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let date: Date
    let totalDistanceMeters: Int
    let totalTimeSeconds: Int
    let segments: [RunSegment]

    init(id: UUID = UUID(), date: Date = Date(), totalDistanceMeters: Int, totalTimeSeconds: Int, segments: [RunSegment]) {
        self.id = id
        self.date = date
        self.totalDistanceMeters = totalDistanceMeters
        self.totalTimeSeconds = totalTimeSeconds
        self.segments = segments
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

// MARK: - Music Models (for WatchConnectivity decoding)
struct MusicSong: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artwork: URL?
    let duration: TimeInterval
    let tempo: Int?
    let energy: Double?
    let valence: Double?

    init(id: String, title: String, artist: String, album: String? = nil, artwork: URL? = nil, duration: TimeInterval, tempo: Int? = nil, energy: Double? = nil, valence: Double? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.duration = duration
        self.tempo = tempo
        self.energy = energy
        self.valence = valence
    }
}
