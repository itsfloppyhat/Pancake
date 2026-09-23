import Foundation

/// Storage and HealthKit stay in meters / seconds per kilometer. Convert at the UI boundary.
enum DistanceUnit: String, CaseIterable, Codable, Identifiable {
    case kilometers
    case miles

    static let preferenceKey = "distanceUnit"
    static var preferred: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .kilometers
    }

    var id: String { rawValue }
    var label: String { self == .miles ? "Miles" : "Kilometers" }
    var singular: String { self == .miles ? "mile" : "kilometer" }
    var symbol: String { self == .miles ? "mi" : "km" }
    var metersPerUnit: Double { self == .miles ? 1609.344 : 1000 }

    func distance(meters: Double) -> Double { meters / metersPerUnit }
    func meters(distance: Double) -> Double { distance * metersPerUnit }
    func pace(secondsPerKm: Double) -> Double { secondsPerKm * metersPerUnit / 1000 }

    func formattedDistance(meters: Double, decimals: Int = 2) -> String {
        String(format: "%.*f %@", decimals, distance(meters: meters), symbol)
    }

    func formattedTarget(meters: Int) -> String {
        if self == .kilometers {
            if meters < 1000 { return "\(meters) m" }
            return formattedDistance(meters: Double(meters), decimals: meters % 1000 == 0 ? 0 : 1)
        }
        return formattedDistance(meters: Double(meters))
    }

    func formattedPace(secondsPerKm: Double, includeUnit: Bool = true) -> String {
        guard secondsPerKm.isFinite, secondsPerKm >= 0 else { return "--:--" }
        let seconds = Int(pace(secondsPerKm: secondsPerKm).rounded())
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return includeUnit ? "\(time)/\(symbol)" : time
    }
}

/// A unit change establishes a new baseline instead of announcing old milestones again.
struct DistanceMilestoneTracker {
    private(set) var unit: DistanceUnit
    private var lastMilestone = 0

    init(unit: DistanceUnit) { self.unit = unit }

    mutating func update(meters: Double, unit: DistanceUnit) -> Int? {
        guard meters.isFinite, meters >= 0 else { return nil }
        let milestone = Int(unit.distance(meters: meters))
        if self.unit != unit {
            self.unit = unit
            lastMilestone = milestone
            return nil
        }
        guard milestone > lastMilestone else { return nil }
        lastMilestone = milestone
        return milestone
    }
}
