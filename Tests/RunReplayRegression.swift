import Foundation

@main
struct RunReplayRegression {
    static func main() throws {
        try testOldHistoryDecodesWithoutRouteOrTarget()
        try testRouteRoundTripAndMissingMetrics()
        try testLocalPaceShowsChangeInsteadOfCumulativeAverage()
        try testStopsDoNotShowOldPace()
        try testSongBoundariesAndSilence()
        try testInvalidCoordinatesAreExcluded()
        try testGapsAreNotInterpolated()
        try testHeartRateClassification()
        try testFullAndPartialSplits()
        try testMileSplits()
        try testPartialRecordingDoesNotInventSplits()
        try testRouteInboxSurvivesReloadAndRejectsCorruption()
        print("All 12 run replay regressions passed.")
    }

    static func event(points: [WorkoutDataPoint] = [], route: [RunRoutePoint] = [], songs: [SongPeriod] = [], duration: Int = 1200) -> RunEvent {
        RunEvent(totalDistanceMeters: 2500, totalTimeSeconds: duration, segments: [], dataPoints: points, songHistory: songs, routePoints: route)
    }

    static func metric(_ time: Double, _ distance: Double) -> WorkoutDataPoint {
        WorkoutDataPoint(timestamp: time, heartRate: 140, cadence: nil, distanceMeters: distance,
                         paceSecondsPerKm: 999, currentSongTitle: nil, currentSongArtist: nil)
    }

    static func route(_ time: Double, _ distance: Double, hr: Int? = 140, speed: Double? = 3, newSection: Bool = false) -> RunRoutePoint {
        RunRoutePoint(timestamp: time, latitude: 40.78 + distance / 111_111, longitude: -73.96,
                      horizontalAccuracy: 5, distanceMeters: distance, heartRate: hr, targetHeartRate: 140,
                      speedMetersPerSecond: speed, startsNewSection: newSection)
    }

    static func testOldHistoryDecodesWithoutRouteOrTarget() throws {
        let original = event(points: [metric(0, 0)])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "routePoints")
        let decoded = try JSONDecoder().decode(RunEvent.self, from: JSONSerialization.data(withJSONObject: object))
        try expect(decoded.routePoints.isEmpty && decoded.dataPoints[0].targetHeartRate == nil, "Legacy runs must remain readable without fabricated GPS or targets.")
    }

    static func testRouteRoundTripAndMissingMetrics() throws {
        let original = event(route: [route(0, 0), route(5, 15, hr: nil, speed: nil)])
        let decoded = try JSONDecoder().decode(RunEvent.self, from: JSONEncoder().encode(original))
        try expect(decoded == original, "Coordinates and missing values must survive history serialization.")
        try expect(RunReplayAnalysis(event: decoded).samples.last?.heartRate == nil, "Missing HR must not inherit an old reading.")
    }

    static func testLocalPaceShowsChangeInsteadOfCumulativeAverage() throws {
        let points: [WorkoutDataPoint] = stride(from: 0, through: 90, by: 10).map { (t: Int) in
            let distance: Double = t <= 30 ? Double(t) * 2.0 : 60.0 + Double(t - 30) * 4.0
            return metric(Double(t), distance)
        }
        let analysis = RunReplayAnalysis(event: event(points: points))
        try expect(abs((analysis.sample(at: 30)?.pace ?? 0) - 500) < 0.1, "The easy section should show 8:20/km.")
        try expect(abs((analysis.sample(at: 80)?.pace ?? 0) - 250) < 0.1, "The faster section must show 4:10/km, not its cumulative average.")
    }

    static func testStopsDoNotShowOldPace() throws {
        let analysis = RunReplayAnalysis(event: event(points: [metric(0, 0), metric(10, 30), metric(20, 30)]))
        try expect(analysis.samples.last?.pace == nil, "A stationary measurement must not display an earlier moving pace.")
    }

    static func testSongBoundariesAndSilence() throws {
        let songs = [SongPeriod(songTitle: "A", artist: "Artist", startTimestamp: 10, endTimestamp: 20),
                     SongPeriod(songTitle: "B", artist: "Artist", startTimestamp: 30, endTimestamp: nil)]
        let normalized = RunReplayAnalysis.normalizedSongs(songs, duration: 50)
        try expect(RunReplayAnalysis.songIndex(at: 19, songs: normalized) == 0, "Song A should cover its own playback.")
        try expect(RunReplayAnalysis.songIndex(at: 20, songs: normalized) == nil, "A silence gap must stay uncolored.")
        try expect(RunReplayAnalysis.songIndex(at: 30, songs: normalized) == 1, "A boundary must belong to the newly started song.")
        try expect(normalized.last?.endTimestamp == 50, "An open final period must stop at the run end.")
    }

    static func testInvalidCoordinatesAreExcluded() throws {
        let invalid = RunRoutePoint(timestamp: 4, latitude: 95, longitude: 0, horizontalAccuracy: -1,
                                    distanceMeters: 4, heartRate: nil, targetHeartRate: nil,
                                    speedMetersPerSecond: nil, startsNewSection: false)
        let analysis = RunReplayAnalysis(event: event(route: [route(0, 0), invalid, route(10, 30)]))
        try expect(analysis.samples.count == 2, "Invalid or negative-accuracy GPS must not enter the route.")
    }

    static func testGapsAreNotInterpolated() throws {
        let analysis = RunReplayAnalysis(event: event(route: [route(0, 0), route(5, 15), route(90, 30, newSection: true)]))
        try expect(analysis.sample(at: 45) == nil, "Scrubbing a missing recording must not fabricate metrics.")
        try expect(analysis.samples[1].section != analysis.samples[2].section, "GPS gaps must break the visible track.")
        try expect(analysis.splits.isEmpty, "Unmeasured split crossings must not be invented.")
    }

    static func testHeartRateClassification() throws {
        try expect(ReplayHeartEffort.classify(heartRate: 120, target: 140) == .below, "Below-target HR is blue.")
        try expect(ReplayHeartEffort.classify(heartRate: 140, target: 140) == .onTarget, "On-target HR is green.")
        try expect(ReplayHeartEffort.classify(heartRate: 165, target: 140) == .above, "Above-target HR is red.")
        try expect(ReplayHeartEffort.classify(heartRate: nil, target: 140) == .unknown, "Missing HR stays gray.")
    }

    static func testFullAndPartialSplits() throws {
        let points = stride(from: 0, through: 1000, by: 10).map { metric(Double($0), Double($0) * 2.5) }
        let analysis = RunReplayAnalysis(event: event(points: points))
        try expect(analysis.splits.count == 3 && analysis.splits.last?.isPartial == true, "A 2.5 km run should have two full splits and one partial.")
        try expect(abs(analysis.splits[0].duration - 400) < 0.01 && abs(analysis.splits[2].pace - 400) < 0.01, "Split pace must normalize partial distances.")
    }

    static func testMileSplits() throws {
        let points = stride(from: 0, through: 1000, by: 10).map { metric(Double($0), Double($0) * 2.5) }
        let analysis = RunReplayAnalysis(event: event(points: points))
        let splits = analysis.splits(in: .miles)
        try expect(splits.count == 2 && !splits[0].isPartial && splits[1].isPartial, "A 2.5 km run must contain one mile split and one partial mile.")
        try expect(abs(splits[0].distanceMeters - 1609.344) < 0.001, "Mile splits must use mile boundaries, not relabeled kilometers.")
        try expect(abs(splits[0].duration - 643.7376) < 0.001 && abs(splits[1].pace - 400) < 0.001, "Full and partial mile splits must preserve elapsed time and normalized pace.")
        try expect(analysis.splits.count == 3, "Viewing miles must not mutate canonical kilometer splits.")
    }

    static func testPartialRecordingDoesNotInventSplits() throws {
        let analysis = RunReplayAnalysis(event: event(points: [metric(200, 500), metric(210, 530)]))
        try expect(analysis.splits.isEmpty, "A recording that starts late cannot reconstruct its first kilometer.")
    }

    static func testRouteInboxSurvivesReloadAndRejectsCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RunRouteArchive(runID: UUID(), startedAt: Date(), totalDistanceMeters: 30,
                                     totalTimeSeconds: 10, segments: [], points: [route(0, 0), route(10, 30)])
        let data = try JSONEncoder().encode(archive)
        let url = try RunRouteInbox.stage(data, in: directory)
        _ = try RunRouteInbox.stage(data, in: directory)
        try expect(RunRouteInbox.pending(in: directory).count == 1, "A duplicate transfer must stage once by run ID.")
        let restored = try JSONDecoder().decode(RunRouteArchive.self, from: Data(contentsOf: url))
        try expect(restored.points == archive.points && restored.runID == archive.runID, "The staged route must survive temporary-file removal and relaunch.")
        do {
            _ = try RunRouteInbox.stage(Data("broken".utf8), in: directory)
            throw NSError(domain: "Regression", code: 1)
        } catch is DecodingError { }
        try expect(try Data(contentsOf: url) == data, "A corrupt delivery must not overwrite a staged route.")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "RunReplayRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
