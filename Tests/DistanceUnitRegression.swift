import Foundation

@main
struct DistanceUnitRegression {
    static func main() throws {
        try expect(abs(DistanceUnit.miles.distance(meters: 1609.344) - 1) < 0.000001, "One mile must equal 1609.344 meters.")
        try expect(abs(DistanceUnit.miles.meters(distance: 3.1) - 4988.9664) < 0.000001, "Mile plan targets must convert to meters without truncation.")
        try expect(DistanceUnit.miles.formattedDistance(meters: 5000) == "3.11 mi", "A 5K must display as 3.11 miles.")
        try expect(DistanceUnit.miles.formattedPace(secondsPerKm: 300) == "8:03/mi", "5:00/km must convert to 8:03/mi.")
        try expect(DistanceUnit.kilometers.formattedPace(secondsPerKm: 300) == "5:00/km", "Metric pace must remain supported.")
        try expect(400.formattedDistanceMeters(unit: .kilometers) == "400 m", "Short metric intervals must retain meters.")
        try expect(402.formattedDistanceMeters(unit: .miles) == "0.25 mi", "Short imperial intervals must use fractional miles.")
        try expect(DistanceUnit.miles.formattedPace(secondsPerKm: .infinity) == "--:--", "Unavailable pace must not crash formatting.")

        var tracker = DistanceMilestoneTracker(unit: .miles)
        try expect(tracker.update(meters: 1000, unit: .miles) == nil, "Miles mode must not announce a kilometer.")
        try expect(tracker.update(meters: 1609.343, unit: .miles) == nil, "Do not announce a mile early.")
        try expect(tracker.update(meters: 1609.344, unit: .miles) == 1, "Announce the first full mile.")
        try expect(tracker.update(meters: 1610, unit: .miles) == nil, "Do not repeat the same milestone.")
        try expect(tracker.update(meters: 5000, unit: .miles) == 3, "A distance jump should announce only the newest milestone.")
        try expect(tracker.update(meters: 5000, unit: .kilometers) == nil, "Changing units must not announce old distance again.")
        try expect(tracker.update(meters: 6000, unit: .kilometers) == 6, "The next milestone should follow the newly selected unit.")
        tracker = DistanceMilestoneTracker(unit: .miles)
        try expect(tracker.update(meters: 1609.344, unit: .miles) == 1, "A new run must restart milestone counting.")

        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: DistanceUnit.preferenceKey)
        defer {
            if let original { defaults.set(original, forKey: DistanceUnit.preferenceKey) }
            else { defaults.removeObject(forKey: DistanceUnit.preferenceKey) }
        }
        defaults.removeObject(forKey: DistanceUnit.preferenceKey)
        try expect(DistanceUnit.preferred == .kilometers, "Existing installations must keep kilometers by default.")
        let event = RunEvent(totalDistanceMeters: 5000, totalTimeSeconds: 1500, segments: [])
        let encoded = try JSONEncoder().encode(event)
        defaults.set("miles", forKey: DistanceUnit.preferenceKey)
        let restored = try JSONDecoder().decode(RunEvent.self, from: encoded)
        try expect(DistanceUnit.preferred == .miles && restored.formattedPace == "8:03/mi", "Saved preferences must apply to historical pace.")
        try expect(restored.totalDistanceMeters == 5000 && restored.averagePacePerKm == 300, "Changing units must not reinterpret stored measurements.")
        defaults.set("unknown", forKey: DistanceUnit.preferenceKey)
        try expect(DistanceUnit.preferred == .kilometers, "Unknown preferences must fall back safely.")
        print("All distance unit regressions passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "DistanceUnitRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
