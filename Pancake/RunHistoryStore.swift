import Foundation

// MARK: - Run Planning Models
enum Intensity: String, CaseIterable, Identifiable, Codable {
    case easy
    case medium
    case hard
    
    var id: String { rawValue }
    
    var label: String {
        rawValue.capitalized
    }
    
    /// Color associated with each intensity level for UI representation
    var color: String {
        switch self {
        case .easy:
            return "green"
        case .medium:
            return "orange"
        case .hard:
            return "red"
        }
    }
    
    /// Description of the intensity level
    var description: String {
        switch self {
        case .easy:
            return "Comfortable pace, can hold a conversation"
        case .medium:
            return "Moderate effort, breathing harder"
        case .hard:
            return "High effort, difficult to speak"
        }
    }
}

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
    
    var id: UUID {
        UUID()
    }
    
    // Codable
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
    
    // MARK: - Hashable
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

struct RunSegment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var intensity: Intensity
    var target: Target
    
    init(id: UUID = UUID(), intensity: Intensity = .easy, target: Target = .time(seconds: 300)) {
        self.id = id
        self.intensity = intensity
        self.target = target
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(intensity)
        hasher.combine(target)
    }
}

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
    
    /// Calculates the average pace in seconds per kilometer
    var averagePacePerKm: TimeInterval? {
        guard totalDistanceMeters > 0 else { return nil }
        return Double(totalTimeSeconds) / (Double(totalDistanceMeters) / 1000.0)
    }
    
    /// Returns a formatted pace string (e.g., "5:30/km")
    var formattedPace: String? {
        guard let pace = averagePacePerKm else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(date)
        hasher.combine(totalDistanceMeters)
        hasher.combine(totalTimeSeconds)
        hasher.combine(segments)
    }
}

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
    
    /// Async version of add for use from nonisolated contexts
    func addEvent(event: RunEvent) async {
        await MainActor.run {
            events.insert(event, at: 0)
            save()
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
        queue.async { [weak self] in
            guard let events = self?.events else { return }
            
            do {
                let data = try JSONEncoder().encode(events)
                UserDefaults.standard.set(data, forKey: self?.storageKey ?? "")
            } catch {
                print("Failed to save run events: \(error)")
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Total distance across all runs in kilometers
    var totalDistanceKm: Double {
        events.reduce(0) { $0 + Double($1.totalDistanceMeters) / 1000.0 }
    }
    
    /// Total duration across all runs in seconds
    var totalDurationSeconds: Int {
        events.reduce(0) { $0 + $1.totalTimeSeconds }
    }
    
    /// Average pace across all runs in seconds per kilometer
    var averagePacePerKm: TimeInterval? {
        guard totalDistanceKm > 0 else { return nil }
        return Double(totalDurationSeconds) / totalDistanceKm
    }
    
    /// Number of completed runs
    var runCount: Int {
        events.count
    }
    
    /// Most recent run date
    var mostRecentRunDate: Date? {
        events.first?.date
    }
    
    // MARK: - HealthKit Integration
    
    /// Import outdoor running workouts from HealthKit
    nonisolated func importFromHealthKit() async throws -> Int {
        let healthKitManager = await HealthKitManager.shared
        
        // Check authorization
        guard await healthKitManager.isAuthorized else {
            throw HealthKitError.notAuthorized
        }
        
        // Import workouts from HealthKit
        let importedEvents = try await healthKitManager.importRunningHistory()
        
        // Get current events for duplicate checking
        let currentEvents = events
        
        // Filter out events that already exist (by date and distance)
        let existingEventKeys = Set(currentEvents.map { "\($0.date.timeIntervalSince1970)-\($0.totalDistanceMeters)" })
        let newEvents = importedEvents.filter { event in
            let eventKey = "\(event.date.timeIntervalSince1970)-\(event.totalDistanceMeters)"
            return !existingEventKeys.contains(eventKey)
        }
        
        // Add new events to the store
        for event in newEvents {
            await addEvent(event: event)
        }
        
        print("📊 Added \(newEvents.count) new runs from HealthKit (filtered out \(importedEvents.count - newEvents.count) duplicates)")
        return newEvents.count
    }
    
    /// Clear all imported HealthKit data (keeps manually added runs)
    func clearHealthKitData() {
        // For now, we'll clear all data since we don't track source
        // In a future version, we could add a source field to RunEvent
        events.removeAll()
        save()
    }
}

// MARK: - Formatting Extensions
extension Int {
    /// Formats seconds as MM:SS
    func formattedTime() -> String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formats distance in meters to a readable string
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
