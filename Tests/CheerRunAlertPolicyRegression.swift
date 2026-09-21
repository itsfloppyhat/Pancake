import Foundation

@main
struct CheerRunAlertPolicyRegression {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func shouldNotify(
            id: String? = "run-1", age: TimeInterval = 30,
            running: Bool = true, enabled: Bool = true, lastID: String? = nil
        ) -> Bool {
            CheerRunAlertPolicy.shouldNotify(
                runID: id, startedAt: now.addingTimeInterval(-age),
                isRunning: running, alertsEnabled: enabled,
                lastNotifiedRunID: lastID, now: now
            )
        }

        try expect(shouldNotify(), "A freshly authorized, current run should notify.")
        try expect(!shouldNotify(lastID: "run-1"), "Repeated background pushes must not repeat an alert.")
        try expect(shouldNotify(id: "run-2", lastID: "run-1"), "A subsequent run must remain eligible.")
        try expect(!shouldNotify(running: false), "An ended run must not notify.")
        try expect(!shouldNotify(enabled: false), "The runner's opt-out must be honored.")
        try expect(!shouldNotify(age: 901) && !shouldNotify(age: -1), "Stale and future run starts must not notify.")
        try expect(!shouldNotify(id: nil) && !shouldNotify(id: ""), "Legacy records without a run ID must not notify.")
        try expect(!CheerRunAlertPolicy.shouldNotify(
            runID: "run-1", startedAt: nil, isRunning: true,
            alertsEnabled: true, lastNotifiedRunID: nil, now: now
        ), "Records without a start date must not notify.")

        let ended = CheerRunBroadcast(id: "run-1", startedAt: now, isRunning: false, alertsEnabled: true)
        let restored = try JSONDecoder().decode(CheerRunBroadcast.self, from: JSONEncoder().encode(ended))
        try expect(restored == ended, "An offline finish must preserve its identity and ended state across launches.")
        print("All 9 Cheer Squad run-alert regressions passed.")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "CheerRunAlertPolicyRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
