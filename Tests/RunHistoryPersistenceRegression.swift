import Foundation

@main
@MainActor
struct RunHistoryPersistenceRegression {
    private static let historyFileName = "PancakeRunHistory.json"
    private static let pendingFileName = "PancakePendingCompletions.json"
    private static let legacyKey = "RunHistoryStore.events"

    static func main() {
        do {
            try testAddIsDurableBeforeReturning()
            try testReplayUpsertsTheOriginalRunID()
            try testHistoryRemainsNewestFirst()
            try testLegacyMigrationCommitsBeforeRemovingDefaults()
            try testFailedLegacyMigrationRetainsDefaults()
            try testCorruptHistoryIsPreserved()
            try testFailedWritesLeavePublishedHistoryUnchanged()
            try testCheckpointSurvivesFailedCommitAndCrashReplay()
            try testPendingCompletionIsDurableAndUpserts()
            try testPendingCompletionRemovalKeepsOtherRuns()
            try testFailedPendingWritesPreserveTheInbox()
            try testCorruptPendingCompletionsArePreserved()
            print("All 12 Pancake run history persistence regressions passed.")
        } catch {
            fputs("Run history regression failure: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func testAddIsDurableBeforeReturning() throws {
        try withFixture { directory, defaults in
            let event = sampleEvent()
            let repository = try RunHistoryRepository(directory: directory, defaults: defaults)
            try repository.add(event)

            // Read the actual file immediately, with no run-loop turn or wait.
            let data = try Data(contentsOf: directory.appendingPathComponent(historyFileName))
            try assertEqual(try JSONDecoder().decode([RunEvent].self, from: data), [event],
                            "add must commit complete run data before it returns")
            let reloaded = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(reloaded.events, [event], "a new process must recover the committed run")
        }
    }

    private static func testReplayUpsertsTheOriginalRunID() throws {
        try withFixture { directory, defaults in
            let original = sampleEvent()
            let repository = try RunHistoryRepository(directory: directory, defaults: defaults)
            try repository.add(original)

            let afterCrash = try RunHistoryRepository(directory: directory, defaults: defaults)
            try afterCrash.add(original)
            try assertEqual(afterCrash.events, [original], "a completion replay must not duplicate history")

            let finalTotals = sampleEvent(id: original.id, distance: 5_250, seconds: 1_625)
            try afterCrash.add(finalTotals)
            let reloaded = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(reloaded.events, [finalTotals],
                            "a replay with final Watch totals must update the same run")
        }
    }

    private static func testHistoryRemainsNewestFirst() throws {
        try withFixture { directory, defaults in
            let older = sampleEvent(date: Date(timeIntervalSince1970: 1_000))
            let newer = sampleEvent(date: Date(timeIntervalSince1970: 2_000))
            let repository = try RunHistoryRepository(directory: directory, defaults: defaults)
            try repository.add(newer)
            try repository.add(older)
            try assertEqual(repository.events, [newer, older], "adding an old run must preserve date order")
            try repository.replace(with: [older, newer])
            let reloaded = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(reloaded.events, [newer, older], "bulk updates must persist newest-first order")
        }
    }

    private static func testLegacyMigrationCommitsBeforeRemovingDefaults() throws {
        try withFixture { directory, defaults in
            let legacy = sampleEvent()
            defaults.set(try JSONEncoder().encode([legacy]), forKey: legacyKey)
            let repository = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(repository.events, [legacy], "migration must preserve every field")
            try assertTrue(defaults.data(forKey: legacyKey) == nil,
                           "successful migration should remove the obsolete defaults payload")
            let reloaded = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(reloaded.events, [legacy], "history must survive removal of the legacy payload")

            // An existing committed file is authoritative if stale defaults remain.
            defaults.set(try JSONEncoder().encode([sampleEvent()]), forKey: legacyKey)
            let fromFile = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(fromFile.events, [legacy], "stale defaults must never replace committed history")
        }
    }

    private static func testFailedLegacyMigrationRetainsDefaults() throws {
        try withFixture { directory, defaults in
            let legacyData = try JSONEncoder().encode([sampleEvent()])
            defaults.set(legacyData, forKey: legacyKey)
            let historyURL = directory.appendingPathComponent(historyFileName)
            var obstructionError: Error?

            // Install a directory at the file destination after the repository's
            // existence check, but before it writes the legacy data. This forces
            // an actual filesystem write failure without relying on permissions.
            defaults.onLegacyRead = {
                do {
                    try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)
                } catch {
                    obstructionError = error
                }
            }
            try assertThrows("failed migration must report its file write error") {
                _ = try RunHistoryRepository(directory: directory, defaults: defaults)
            }
            defaults.onLegacyRead = nil
            if let obstructionError { throw obstructionError }
            try assertEqual(defaults.data(forKey: legacyKey), legacyData,
                            "failed migration must retain the only durable copy")

            try FileManager.default.removeItem(at: historyURL)
            let retry = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(retry.events, try JSONDecoder().decode([RunEvent].self, from: legacyData),
                            "a later successful migration must recover the retained legacy data")
            try assertTrue(defaults.data(forKey: legacyKey) == nil,
                           "the legacy payload can be removed after the retry commits")
        }
    }

    private static func testCorruptHistoryIsPreserved() throws {
        try withFixture { directory, defaults in
            let historyURL = directory.appendingPathComponent(historyFileName)
            let corrupt = Data("{ interrupted or unsupported history }".utf8)
            try corrupt.write(to: historyURL)
            let legacyData = try JSONEncoder().encode([sampleEvent()])
            defaults.set(legacyData, forKey: legacyKey)

            try assertThrows("an unreadable history must fail instead of silently becoming empty") {
                _ = try RunHistoryRepository(directory: directory, defaults: defaults)
            }
            try assertEqual(try Data(contentsOf: historyURL), corrupt,
                            "loading corrupt history must preserve the original bytes for recovery")
            try assertEqual(defaults.data(forKey: legacyKey), legacyData,
                            "a corrupt current file must not consume or overwrite legacy history")
        }
    }

    private static func testFailedWritesLeavePublishedHistoryUnchanged() throws {
        try withFixture { directory, defaults in
            let original = sampleEvent()
            let repository = try RunHistoryRepository(directory: directory, defaults: defaults)
            try repository.add(original)
            let historyURL = directory.appendingPathComponent(historyFileName)
            let backupURL = directory.appendingPathComponent("committed-history.backup")
            try FileManager.default.moveItem(at: historyURL, to: backupURL)
            try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)

            try assertThrows("add must report a failed write") { try repository.add(sampleEvent()) }
            try assertEqual(repository.events, [original], "failed add must leave in-memory history unchanged")
            try assertThrows("replace must report a failed write") { try repository.replace(with: []) }
            try assertEqual(repository.events, [original], "failed deletion must leave in-memory history unchanged")

            try FileManager.default.removeItem(at: historyURL)
            try FileManager.default.moveItem(at: backupURL, to: historyURL)
            let reloaded = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(reloaded.events, [original], "failed changes must not alter the last committed event")
        }
    }

    private static func testCheckpointSurvivesFailedCommitAndCrashReplay() throws {
        try withFixture { directory, defaults in
            let event = sampleEvent()
            let active = ActiveRunStateStore(defaults: defaults, directory: directory)
            active.beginRun(id: event.id, segments: event.segments, startedAt: event.date)
            active.update(currentSegmentIndex: 0,
                          totalDistanceKm: Double(event.totalDistanceMeters) / 1_000,
                          totalTimeSeconds: event.totalTimeSeconds,
                          dataPoints: event.dataPoints, songHistory: event.songHistory)
            let checkpoint = active.snapshot
            let repository = try RunHistoryRepository(directory: directory, defaults: defaults)
            let historyURL = directory.appendingPathComponent(historyFileName)
            try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)
            try assertThrows("the failed completion must not be accepted") { try repository.add(event) }

            let afterFailure = ActiveRunStateStore(defaults: defaults, directory: directory)
            try assertEqual(afterFailure.snapshot, checkpoint,
                            "the active checkpoint must remain recoverable when history cannot be written")
            try assertTrue(!afterFailure.hasSaved(runID: event.id), "a failed write must not mark the run saved")

            try FileManager.default.removeItem(at: historyURL)
            try repository.add(event)
            // Simulate termination after the durable write but before the active
            // checkpoint is cleared: both files exist and the completion replays.
            let afterCrash = try RunHistoryRepository(directory: directory, defaults: defaults)
            let pending = ActiveRunStateStore(defaults: defaults, directory: directory)
            try assertEqual(pending.snapshot?.id, event.id, "recovery must keep the stable Watch run ID")
            try afterCrash.add(event)
            try assertEqual(afterCrash.events, [event], "checkpoint replay after commit must remain idempotent")
            pending.markSaved(runID: event.id)
            pending.clear()
            let completed = ActiveRunStateStore(defaults: defaults, directory: directory)
            try assertTrue(completed.snapshot == nil && completed.hasSaved(runID: event.id),
                           "successful completion may clear recovery only after durable history exists")
            let finalHistory = try RunHistoryRepository(directory: directory, defaults: defaults)
            try assertEqual(finalHistory.events, [event], "clearing the checkpoint must not remove completed history")
        }
    }

    private static func testPendingCompletionIsDurableAndUpserts() throws {
        try withFixture { directory, _ in
            let original = sampleEvent()
            let inbox = try PendingRunCompletionStore(directory: directory)
            try inbox.upsert(original)
            let data = try Data(contentsOf: directory.appendingPathComponent(pendingFileName))
            try assertEqual(try JSONDecoder().decode([RunEvent].self, from: data), [original],
                            "a pending completion must be on disk before upsert returns")

            let afterRestart = try PendingRunCompletionStore(directory: directory)
            let finalTotals = sampleEvent(id: original.id, distance: 5_250, seconds: 1_625)
            try afterRestart.upsert(finalTotals)
            try afterRestart.upsert(finalTotals)
            let reloaded = try PendingRunCompletionStore(directory: directory)
            try assertEqual(reloaded.events, [finalTotals],
                            "completion replays must retain one latest payload for the stable run ID")
        }
    }

    private static func testPendingCompletionRemovalKeepsOtherRuns() throws {
        try withFixture { directory, _ in
            let older = sampleEvent(date: Date(timeIntervalSince1970: 1_000))
            let newer = sampleEvent(date: Date(timeIntervalSince1970: 2_000))
            let inbox = try PendingRunCompletionStore(directory: directory)
            try inbox.upsert(newer)
            try inbox.upsert(older)
            try assertEqual(inbox.events, [newer, older], "out-of-order completions must coexist in the inbox")

            try inbox.remove(runID: older.id)
            let afterRemoval = try PendingRunCompletionStore(directory: directory)
            try assertEqual(afterRemoval.events, [newer],
                            "committing an old completion must not remove a newer pending run")
            try afterRemoval.remove(runID: older.id)
            try assertEqual(afterRemoval.events, [newer], "repeated acknowledgement must leave other runs intact")
            try afterRemoval.remove(runID: newer.id)
            let empty = try PendingRunCompletionStore(directory: directory)
            try assertTrue(empty.events.isEmpty, "the final removal must remain empty after restart")
        }
    }

    private static func testFailedPendingWritesPreserveTheInbox() throws {
        try withFixture { directory, _ in
            let original = sampleEvent()
            let inbox = try PendingRunCompletionStore(directory: directory)
            try inbox.upsert(original)
            let pendingURL = directory.appendingPathComponent(pendingFileName)
            let backupURL = directory.appendingPathComponent("pending-completions.backup")
            try FileManager.default.moveItem(at: pendingURL, to: backupURL)
            try FileManager.default.createDirectory(at: pendingURL, withIntermediateDirectories: false)

            let finalTotals = sampleEvent(id: original.id, distance: 5_250, seconds: 1_625)
            try assertThrows("a failed pending upsert must report its error") { try inbox.upsert(finalTotals) }
            try assertEqual(inbox.events, [original], "failed pending upsert must preserve the last durable payload")
            try assertThrows("a failed pending acknowledgement must report its error") {
                try inbox.remove(runID: original.id)
            }
            try assertEqual(inbox.events, [original], "failed removal must retain the completion for retry")

            try FileManager.default.removeItem(at: pendingURL)
            try FileManager.default.moveItem(at: backupURL, to: pendingURL)
            let reloaded = try PendingRunCompletionStore(directory: directory)
            try assertEqual(reloaded.events, [original], "failed writes must leave recoverable pending data intact")
        }
    }

    private static func testCorruptPendingCompletionsArePreserved() throws {
        try withFixture { directory, _ in
            let pendingURL = directory.appendingPathComponent(pendingFileName)
            let corrupt = Data("{ interrupted or unsupported pending completion }".utf8)
            try corrupt.write(to: pendingURL)
            try assertThrows("corrupt pending data must report an error instead of silently becoming empty") {
                _ = try PendingRunCompletionStore(directory: directory)
            }
            try assertEqual(try Data(contentsOf: pendingURL), corrupt,
                            "corrupt pending completion bytes must remain available for recovery")
        }
    }

    private static func sampleEvent(
        id: UUID = UUID(),
        date: Date = Date(timeIntervalSince1970: 1_750_000_000),
        distance: Int = 5_000,
        seconds: Int = 1_600
    ) -> RunEvent {
        RunEvent(id: id, date: date, totalDistanceMeters: distance, totalTimeSeconds: seconds,
                 segments: [RunSegment(id: UUID(uuidString: "8AA2C10F-5195-44FC-B385-29405312C581")!,
                                       intensity: .zone3, target: .distance(meters: 5_000))],
                 dataPoints: [WorkoutDataPoint(timestamp: 30, heartRate: 145, cadence: 168,
                                               distanceMeters: 96, paceSecondsPerKm: 312.5,
                                               currentSongTitle: "Running Song", currentSongArtist: "Runner")],
                 songHistory: [SongPeriod(songTitle: "Running Song", artist: "Runner",
                                          startTimestamp: 0, endTimestamp: 180)])
    }

    private static func withFixture(_ body: (URL, MigrationFaultDefaults) throws -> Void) throws {
        let fixtureID = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PancakeRunHistoryRegression-\(fixtureID)", isDirectory: true)
        let suiteName = "Pancake.RunHistoryRegression.\(fixtureID)"
        guard let defaults = MigrationFaultDefaults(suiteName: suiteName) else {
            throw RegressionError("Could not create isolated defaults")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try body(directory, defaults)
    }

    private static func assertTrue(_ condition: Bool, _ message: String) throws {
        if !condition { throw RegressionError(message) }
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
        if actual != expected { throw RegressionError(message) }
    }

    private static func assertThrows(_ message: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            return
        }
        throw RegressionError(message)
    }

    private struct RegressionError: LocalizedError {
        let errorDescription: String?
        init(_ description: String) { errorDescription = description }
    }
}

/// A fault hook used only to obstruct migration between its source read and
/// destination write. All stored data still uses an isolated UserDefaults suite.
private final class MigrationFaultDefaults: UserDefaults {
    var onLegacyRead: (() -> Void)?

    override func data(forKey defaultName: String) -> Data? {
        let data = super.data(forKey: defaultName)
        if defaultName == "RunHistoryStore.events" { onLegacyRead?() }
        return data
    }
}
