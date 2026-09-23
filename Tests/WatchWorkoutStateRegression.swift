import Foundation

@main
struct WatchWorkoutStateRegression {
    static func main() throws {
        try testCompletedRunIsKeptOnceAfterReload()
        try testInterruptedSummaryKeepsMetrics()
        try testIntervalActionsRejectOldIntervalsAndRuns()
        try testPendingPlanSurvivesEncodingAndExpires()
        try testWorkoutStartWaitsForChoiceAndFullCountdown()
        try testRepeatedStartActionsKeepOneChoiceAndRequest()
        try testCancelledCountdownCannotStartRetry()
        try testWorkoutStartKeepsOriginalPlanSnapshot()
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

    private static func testWorkoutStartWaitsForChoiceAndFullCountdown() throws {
        let segments = [RunSegment(intensity: .zone2, target: .time(seconds: 1800))]
        for wantsMusic in [true, false] {
            var flow = WatchWorkoutStartFlow()
            try expect(!flow.begin(segments: []), "An empty plan must not enter workout preparation.")
            try expect(flow.begin(segments: segments), "A valid plan should open the music choice.")
            let attemptID = flow.attemptID!
            try expect(flow.phase == .choosingMusic && flow.countdownAttemptID == nil, "The workout must wait for a music choice before beginning the countdown.")
            try expect(flow.advanceCountdown(attemptID: attemptID) == nil && flow.phase == .choosingMusic, "A timer callback before the music choice must not start a workout.")

            flow.chooseMusic(wantsMusic)
            try expect(flow.phase == .countingDown(3) && flow.countdownAttemptID == attemptID, "Either music choice should show 3 first.")
            try expect(flow.advanceCountdown(attemptID: attemptID) == nil && flow.phase == .countingDown(2), "After one second, the countdown should show 2 without starting.")
            try expect(flow.advanceCountdown(attemptID: attemptID) == nil && flow.phase == .countingDown(1), "After two seconds, the countdown should show 1 without starting.")
            let request = flow.advanceCountdown(attemptID: attemptID)
            try expect(flow.phase == .starting && flow.countdownAttemptID == nil, "The third tick should finish the countdown and begin starting.")
            try expect(request?.segments == segments && request?.startAdaptiveMix == wantsMusic, "The start request must preserve the selected music choice and plan.")
        }
    }

    private static func testRepeatedStartActionsKeepOneChoiceAndRequest() throws {
        let segments = [RunSegment(intensity: .zone3, target: .distance(meters: 2000))]
        for wantsMusic in [true, false] {
            var flow = WatchWorkoutStartFlow()
            flow.begin(segments: segments)
            let attemptID = flow.attemptID!
            try expect(!flow.begin(segments: segments) && flow.attemptID == attemptID, "A double tap on Start must keep the original attempt.")
            flow.chooseMusic(wantsMusic)
            flow.chooseMusic(!wantsMusic)
            try expect(flow.phase == .countingDown(3), "A repeated music action must not restart or skip the countdown.")
            try expect(!flow.begin(segments: segments) && flow.attemptID == attemptID, "Start must remain unavailable during the countdown.")
            _ = flow.advanceCountdown(attemptID: attemptID)
            _ = flow.advanceCountdown(attemptID: attemptID)
            let request = flow.advanceCountdown(attemptID: attemptID)
            try expect(request?.startAdaptiveMix == wantsMusic, "A duplicate music action must not override the original choice.")
            try expect(flow.advanceCountdown(attemptID: attemptID) == nil, "Extra timer callbacks must not emit another start request.")
            flow.chooseMusic(!wantsMusic)
            flow.cancelPreparation()
            try expect(!flow.begin(segments: segments) && flow.phase == .starting, "Repeated controls cannot restart or cancel an already emitted workout start.")
        }
    }

    private static func testCancelledCountdownCannotStartRetry() throws {
        let segments = [RunSegment(intensity: .zone2, target: .time(seconds: 1800))]
        var flow = WatchWorkoutStartFlow()
        flow.begin(segments: segments)
        flow.cancelPreparation()
        try expect(flow.phase == .idle && flow.attemptID == nil, "Cancelling the music prompt must return to idle.")

        flow.begin(segments: segments)
        let cancelledID = flow.attemptID!
        flow.chooseMusic(true)
        _ = flow.advanceCountdown(attemptID: cancelledID)
        flow.cancelPreparation()
        try expect(flow.phase == .idle && flow.countdownAttemptID == nil, "Cancelling a countdown must clear its active attempt.")
        try expect(flow.advanceCountdown(attemptID: cancelledID) == nil, "A cancelled countdown cannot emit a start request.")

        flow.begin(segments: segments)
        let retryID = flow.attemptID!
        try expect(retryID != cancelledID && flow.phase == .choosingMusic, "Retry must create a fresh attempt and ask for music again.")
        flow.chooseMusic(false)
        try expect(flow.advanceCountdown(attemptID: cancelledID) == nil && flow.phase == .countingDown(3), "A stale callback must not advance the retry's countdown.")
        _ = flow.advanceCountdown(attemptID: retryID)
        _ = flow.advanceCountdown(attemptID: retryID)
        let request = flow.advanceCountdown(attemptID: retryID)
        try expect(request?.startAdaptiveMix == false, "The cancelled attempt's music opt-in must not carry into a retry.")

        flow.reset()
        try expect(flow.phase == .idle && flow.attemptID == nil, "A finished or failed start must be resettable for another run.")
        try expect(flow.advanceCountdown(attemptID: retryID) == nil, "Reset must invalidate the previous countdown's callbacks.")
    }

    private static func testWorkoutStartKeepsOriginalPlanSnapshot() throws {
        var receivedSegments = [RunSegment(intensity: .zone4, target: .time(seconds: 120))]
        let originalSegments = receivedSegments
        var flow = WatchWorkoutStartFlow()
        flow.begin(segments: receivedSegments)
        let attemptID = flow.attemptID!
        receivedSegments = [RunSegment(intensity: .zone2, target: .distance(meters: 5000))]
        try expect(!flow.begin(segments: receivedSegments), "A replacement phone plan must not overwrite a start attempt in progress.")
        flow.chooseMusic(false)
        _ = flow.advanceCountdown(attemptID: attemptID)
        _ = flow.advanceCountdown(attemptID: attemptID)
        let request = flow.advanceCountdown(attemptID: attemptID)
        try expect(request?.segments == originalSegments, "The workout must start with the plan shown when the user tapped Start.")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "WatchWorkoutStateRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
