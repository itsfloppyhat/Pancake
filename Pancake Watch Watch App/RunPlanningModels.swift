import Foundation
import Combine

final class RunPlanViewModel: ObservableObject {
    @Published var segments: [RunSegment] = []
    
    func addSegment(_ segment: RunSegment) {
        segments.append(segment)
    }
    
    func removeSegments(at offsets: IndexSet) {
        segments.remove(atOffsets: offsets)
    }
    
    func moveSegments(from source: IndexSet, to destination: Int) {
        segments.move(fromOffsets: source, toOffset: destination)
    }
    
    func clearAllSegments() {
        segments.removeAll()
    }
    
    /// Total time for all time-based segments in seconds
    var totalTimeSeconds: Int {
        segments.reduce(0) {
            switch $1.target {
            case .time(let seconds):
                return $0 + seconds
            case .distance:
                return $0
            }
        }
    }
    
    /// Total distance for all distance-based segments in meters
    var totalDistanceMeters: Int {
        segments.reduce(0) {
            switch $1.target {
            case .distance(let meters):
                return $0 + meters
            case .time:
                return $0
            }
        }
    }
    
    /// Number of segments in the plan
    var segmentCount: Int {
        segments.count
    }
    
    /// Whether the plan has any segments
    var hasSegments: Bool {
        !segments.isEmpty
    }
    
    /// Estimated total workout duration (time-based segments only)
    var estimatedDuration: TimeInterval {
        TimeInterval(totalTimeSeconds)
    }
    
    /// Estimated total distance (distance-based segments only)
    var estimatedDistance: Double {
        Double(totalDistanceMeters) / 1000.0 // Convert to kilometers
    }
    
    func addDefaultSegment() {
        let segment = RunSegment()
        segments.append(segment)
    }
    
    /// Creates a quick interval workout template
    func addIntervalTemplate() {
        clearAllSegments()
        
        // Warm-up
        addSegment(RunSegment(intensity: .easy, target: .time(seconds: 300))) // 5 min
        
        // Intervals (3x)
        for _ in 0..<3 {
            addSegment(RunSegment(intensity: .hard, target: .time(seconds: 120))) // 2 min hard
            addSegment(RunSegment(intensity: .easy, target: .time(seconds: 120))) // 2 min easy
        }
        
        // Cool-down
        addSegment(RunSegment(intensity: .easy, target: .time(seconds: 300))) // 5 min
    }
    
    /// Creates a long run template
    func addLongRunTemplate() {
        clearAllSegments()
        addSegment(RunSegment(intensity: .easy, target: .distance(meters: 5000))) // 5K easy
    }
}

extension Int {
    /// Formats seconds as MM:SS
    func formattedTime() -> String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formats seconds as a more readable time string (e.g., "5 min", "1 hr 30 min")
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
