import Foundation

@main
struct WatchWorkoutStateRegression {
    static func main() throws {
        try testCompletedRunIsKeptOnceAfterReload()
        try testInterruptedSummaryKeepsMetrics()
        try testIntervalActionsRejectOldIntervalsAndRuns()
        try testPendingPlanSurvivesEncodingAndExpires()
        print("All Pancake Watch state regressions passed.")
    }

    private static func testCompletedRunIsKeptOnceAfterReload() throws {
        let suite = "Pancake.WatchRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let segment = RunSegment(intensity: .zone2, target: .time(seconds: 1800))
        let run = RunEvent(totalDistanceMeters: 4200, totalTimeSeconds: 1500, segments: [segment])
        let store = RunHistoryStore(defaults: defaults)
        store.add(event: run)
        // HealthKit may deliver both an error and an ended callback for one run.
        store.add(event: run)
        let relaunched = RunHistoryStore(defaults: defaults)
        relaunched.add(event: run)
        try expect(relaunched.events == [run], "An interrupted run must survive reload and must not be saved twice.")
        let nextRun = RunEvent(totalDistanceMeters: 800, totalTimeSeconds: 240, segments: [segment])
        relaunched.add(event: nextRun)
        try expect(relaunched.events.map(\.id) == [nextRun.id, run.id], "A new run must not overwrite the interrupted run.")
    }

    private static func testInterruptedSummaryKeepsMetrics() throws {
        let summary = WorkoutSummary(
            id: UUID(), totalSeconds: 1500, totalDistanceKm: 4.2, activeCalories: 275,
            segmentCount: 3, interruptionMessage: "Another workout started.", healthSaveMessage: "Saving to Health…"
        )
        let restored = try JSONDecoder().decode(WorkoutSummary.self, from: JSONEncoder().encode(summary))
        try expect(restored.id == summary.id && restored.totalSeconds == 1500 && restored.totalDistanceKm == 4.2, "The interrupted summary must retain its run identity and measured totals.")
        try expect(restored.interruptionMessage != nil && restored.formattedPace == "5:57/km", "The restored summary must explain the interruption and use the recorded duration.")
    }

    private static func testIntervalActionsRejectOldIntervalsAndRuns() throws {
        let runID = UUID()
        let interval = IntervalChangePrompt(runID: runID, segmentIndex: 1, intensity: .zone4, target: .time(seconds: 120))
        try expect(interval.isCurrent(runID: runID, segmentIndex: 1, isRunning: true), "The current interval should allow the user's explicit music choice.")
        try expect(!interval.isCurrent(runID: runID, segmentIndex: 2, isRunning: true), "A previous interval's notification must not skip music.")
        try expect(!interval.isCurrent(runID: UUID(), segmentIndex: 1, isRunning: true), "A notification from another run must not skip music.")
        try expect(!interval.isCurrent(runID: nil, segmentIndex: 1, isRunning: false), "An ended workout must reject notification actions.")
    }

    private static func testPendingPlanSurvivesEncodingAndExpires() throws {
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)
        let segments = [RunSegment(intensity: .zone3, target: .distance(meters: 2000))]
        let plan = PendingWatchRunPlan(id: UUID().uuidString, sentAt: sentAt, segments: segments)
        let restored = try JSONDecoder().decode(PendingWatchRunPlan.self, from: JSONEncoder().encode(plan))
        try expect(restored.id == plan.id && restored.segments == segments, "A relaunch must restore the complete unstarted plan, including its identity.")
        try expect(restored.isUsable(at: sentAt.addingTimeInterval(300), expiry: 21600), "A recent unstarted plan should remain usable.")
        try expect(!restored.isUsable(at: sentAt.addingTimeInterval(21600), expiry: 21600), "Expired plans must not return after relaunch.")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "WatchWorkoutStateRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
