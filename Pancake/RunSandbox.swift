#if DEBUG
import Combine
import Foundation

// MARK: - Adaptive Mix Eval Recorder

/// DEBUG-only capture of each Adaptive Mix curation for live evaluation:
/// the prompt sent to the on-device model, what it generated, what survived
/// catalog verification, and how the queue splits between taste-profile
/// favorites and exploratory picks. Everything is also printed with
/// PANCAKE_EVAL markers so a device console capture can be analyzed offline.
@MainActor
final class AdaptiveMixEvalRecorder: ObservableObject {
    static let shared = AdaptiveMixEvalRecorder()

    struct CurationRecord: Identifiable {
        let id = UUID()
        let timestamp: Date
        let trigger: String
        let targetZone: String
        let guidance: String
        let effectiveHeartRate: Int?
        let targetHeartRate: Int?
        let prompt: String
        let generatedSongs: [String]
        let verifiedSongs: [String]
        let favoriteCount: Int
        let exploratoryCount: Int
        let applied: Bool
    }

    @Published private(set) var records: [CurationRecord] = []
    @Published private(set) var sessionFavoriteCount = 0
    @Published private(set) var sessionExploratoryCount = 0

    private var pendingPrompt: String?
    private var pendingGeneratedSongs: [String] = []

    var sessionFavoritesRatioText: String {
        let total = sessionFavoriteCount + sessionExploratoryCount
        guard total > 0 else { return "no songs yet" }
        let percent = Int((Double(sessionFavoriteCount) / Double(total) * 100).rounded())
        return "\(percent)% favorites (\(sessionFavoriteCount)/\(total)) — target 35-45%"
    }

    func beginSession(preferences: MusicPreferences) {
        records = []
        sessionFavoriteCount = 0
        sessionExploratoryCount = 0
        pendingPrompt = nil
        pendingGeneratedSongs = []

        let profile = MusicTasteProfileBuilder.build(from: preferences)
        print("PANCAKE_EVAL:SESSION_START taste=\(profile.conciseSummary)")
    }

    func endSession() {
        print("PANCAKE_EVAL:SESSION_END curations=\(records.count) ratio=\(sessionFavoritesRatioText)")
    }

    func willGenerate(prompt: String) {
        pendingPrompt = prompt
        pendingGeneratedSongs = []
        print("PANCAKE_EVAL:PROMPT_BEGIN")
        print(prompt)
        print("PANCAKE_EVAL:PROMPT_END")
    }

    func didGenerate(_ suggestions: [MusicSuggestion]) {
        pendingGeneratedSongs = suggestions.map { "\($0.songTitle) — \($0.artist)" }
        for suggestion in suggestions {
            print("PANCAKE_EVAL:GENERATED title=\(suggestion.songTitle) artist=\(suggestion.artist) mood=\(suggestion.mood.rawValue)")
        }
    }

    func recordCuration(
        trigger: String,
        goalScore: AdaptiveMixGoalScore,
        resolvedSongs: [MusicSong],
        applied: Bool,
        preferences: MusicPreferences
    ) {
        var favoriteCount = 0
        var exploratoryCount = 0
        var verifiedDescriptions: [String] = []

        for song in resolvedSongs {
            let isFavorite = Self.isTasteAnchor(song, preferences: preferences)
            if isFavorite { favoriteCount += 1 } else { exploratoryCount += 1 }
            verifiedDescriptions.append("\(song.title) — \(song.artist)")
            print("PANCAKE_EVAL:VERIFIED verdict=\(isFavorite ? "favorite" : "exploratory") title=\(song.title) artist=\(song.artist)")
        }

        if applied {
            sessionFavoriteCount += favoriteCount
            sessionExploratoryCount += exploratoryCount
        }

        let record = CurationRecord(
            timestamp: Date(),
            trigger: trigger,
            targetZone: goalScore.targetIntensity.label,
            guidance: goalScore.guidance.rawValue,
            effectiveHeartRate: goalScore.effectiveHeartRate,
            targetHeartRate: goalScore.targetHeartRate,
            prompt: pendingPrompt ?? "(fallback only — no AI prompt this round)",
            generatedSongs: pendingGeneratedSongs,
            verifiedSongs: verifiedDescriptions,
            favoriteCount: favoriteCount,
            exploratoryCount: exploratoryCount,
            applied: applied
        )
        records.insert(record, at: 0)
        pendingPrompt = nil
        pendingGeneratedSongs = []

        let heartRateText = goalScore.effectiveHeartRate.map(String.init) ?? "-"
        let targetText = goalScore.targetHeartRate.map(String.init) ?? "-"
        print("PANCAKE_EVAL:CURATION trigger=\(trigger) zone=\(goalScore.targetIntensity.label) guidance=\(goalScore.guidance.rawValue) hr=\(heartRateText) targetHR=\(targetText) generated=\(record.generatedSongs.count) verified=\(resolvedSongs.count) favorites=\(favoriteCount) exploratory=\(exploratoryCount) applied=\(applied) sessionRatio=\(sessionFavoritesRatioText)")
    }

    /// A pick counts toward the 35-45% favorites budget when its artist is in
    /// the saved taste profile or the exact song is a saved favorite.
    static func isTasteAnchor(_ song: MusicSong, preferences: MusicPreferences) -> Bool {
        let favoriteArtists = Set(
            (preferences.favoriteArtists + preferences.importedPlaylistArtists)
                .map { $0.name.normalizedMusicIdentity }
        )
        let favoriteSongKeys = Set(preferences.allFavoriteSongs.map(\.sessionSongKey))

        return favoriteArtists.contains(song.artist.normalizedMusicIdentity) ||
            favoriteSongKeys.contains(song.sessionSongKey)
    }
}

// MARK: - Run Sandbox Driver

/// DEBUG-only "virtual watch": drives WorkoutMusicCoordinator through the
/// same NotificationCenter messages the real watch companion sends, so the
/// full production pipeline (segment changes, 10-second pre-interval
/// curation, 30-second refreshes, queue refills) runs against live, tunable
/// speed and heart-rate values with real Apple Music playback.
@MainActor
final class RunSandboxDriver: ObservableObject {
    static let shared = RunSandboxDriver()

    /// Suppresses Cheer Squad broadcasts so sandbox runs never notify friends.
    private(set) static var isSandboxRunActive = false

    @Published var speedMetersPerSecond: Double = 3.0
    @Published var heartRate: Double = 132
    @Published private(set) var isRunning = false
    @Published private(set) var totalTime: TimeInterval = 0
    @Published private(set) var totalDistanceMeters: Double = 0
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var plannedSegments: [RunSegment] = []
    @Published private(set) var secondsRemainingInSegment: Int?

    private var tickTimer: Timer?
    private var segmentElapsed: TimeInterval = 0
    private var segmentStartDistance: Double = 0
    private var secondsSinceUpdateSent = 0
    private var lastPrecuratedSegmentIndex: Int?

    private static let updateInterval = 5
    private static let precurationLeadTime: TimeInterval = 10

    static let defaultPlan: [RunSegment] = [
        RunSegment(intensity: .zone2, target: .time(seconds: 180)),
        RunSegment(intensity: .zone4, target: .time(seconds: 150)),
        RunSegment(intensity: .zone2, target: .time(seconds: 150)),
        RunSegment(intensity: .zone4, target: .time(seconds: 150)),
        RunSegment(intensity: .zone1, target: .time(seconds: 150))
    ]

    var currentSegment: RunSegment? {
        guard currentSegmentIndex < plannedSegments.count else { return nil }
        return plannedSegments[currentSegmentIndex]
    }

    var currentTargetHeartRate: Int? {
        currentSegment?.intensity.defaultTargetHeartRate
    }

    func start(plan: [RunSegment] = RunSandboxDriver.defaultPlan) {
        guard !isRunning else { return }

        plannedSegments = plan
        currentSegmentIndex = 0
        totalTime = 0
        totalDistanceMeters = 0
        segmentElapsed = 0
        segmentStartDistance = 0
        secondsSinceUpdateSent = 0
        lastPrecuratedSegmentIndex = nil
        isRunning = true
        Self.isSandboxRunActive = true

        AdaptiveMixEvalRecorder.shared.beginSession(
            preferences: UserProfileManager.shared.userProfile.musicPreferences
        )
        print("PANCAKE_EVAL:RUN_START segments=\(plan.count)")

        let startMessage: [String: Any] = [
            "type": WatchMessageType.workoutStart.rawValue,
            "segments": plan.map { segment in
                [
                    "intensity": segment.intensity.rawValue,
                    "target": [
                        "type": segment.target.isTime ? "time" : "distance",
                        "value": segment.target.isTime ? segment.target.timeSeconds : segment.target.distanceMeters
                    ]
                ]
            }
        ]
        NotificationCenter.default.post(name: .workoutControl, object: startMessage)
        sendWorkoutUpdate()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        guard isRunning else { return }

        tickTimer?.invalidate()
        tickTimer = nil
        isRunning = false
        Self.isSandboxRunActive = false
        secondsRemainingInSegment = nil

        // "end" stops workout music without saving a run event, so sandbox
        // sessions never pollute real run history.
        NotificationCenter.default.post(name: .workoutControl, object: ["action": "end"])
        AdaptiveMixEvalRecorder.shared.endSession()
        print("PANCAKE_EVAL:RUN_END totalSeconds=\(Int(totalTime)) distanceMeters=\(Int(totalDistanceMeters))")
    }

    func startAdaptiveMix() {
        Task {
            await WorkoutMusicCoordinator.shared.startAdaptiveMixUserRequested()
        }
    }

    /// Convenience for coarse control through iPhone Mirroring: sets the
    /// heart rate relative to the current segment target.
    func setHeartRateRelativeToTarget(offset: Int) {
        let target = currentTargetHeartRate ?? 140
        heartRate = Double(max(80, min(195, target + offset)))
        sendWorkoutUpdate()
    }

    private func tick() {
        guard isRunning else { return }

        totalTime += 1
        segmentElapsed += 1
        totalDistanceMeters += speedMetersPerSecond

        advanceSegmentIfNeeded()
        checkForPrecuration()
        updateSecondsRemaining()

        secondsSinceUpdateSent += 1
        if secondsSinceUpdateSent >= Self.updateInterval {
            secondsSinceUpdateSent = 0
            sendWorkoutUpdate()
        }
    }

    private func segmentSecondsRemaining() -> TimeInterval? {
        guard let segment = currentSegment else { return nil }

        switch segment.target {
        case .time(let seconds):
            return max(0, TimeInterval(seconds) - segmentElapsed)
        case .distance(let meters):
            let covered = totalDistanceMeters - segmentStartDistance
            let remaining = max(0, Double(meters) - covered)
            guard speedMetersPerSecond > 0 else { return nil }
            return remaining / speedMetersPerSecond
        }
    }

    private func advanceSegmentIfNeeded() {
        guard let remaining = segmentSecondsRemaining(), remaining <= 0 else { return }

        guard currentSegmentIndex + 1 < plannedSegments.count else {
            print("PANCAKE_EVAL:PLAN_COMPLETE")
            return
        }

        currentSegmentIndex += 1
        segmentElapsed = 0
        segmentStartDistance = totalDistanceMeters
        print("PANCAKE_EVAL:SEGMENT_CHANGE index=\(currentSegmentIndex) zone=\(currentSegment?.intensity.label ?? "?")")
        sendWorkoutUpdate()
    }

    private func checkForPrecuration() {
        let upcomingIndex = currentSegmentIndex + 1
        guard upcomingIndex < plannedSegments.count,
              lastPrecuratedSegmentIndex != upcomingIndex,
              let remaining = segmentSecondsRemaining(),
              remaining > 0,
              remaining <= Self.precurationLeadTime else {
            return
        }

        lastPrecuratedSegmentIndex = upcomingIndex
        print("PANCAKE_EVAL:PRECURATION upcomingIndex=\(upcomingIndex) zone=\(plannedSegments[upcomingIndex].intensity.label)")
        sendWorkoutUpdate(adaptiveMixCurationTargetSegmentIndex: upcomingIndex)
    }

    private func updateSecondsRemaining() {
        secondsRemainingInSegment = segmentSecondsRemaining().map { Int($0) }
    }

    private func sendWorkoutUpdate(adaptiveMixCurationTargetSegmentIndex: Int? = nil) {
        var message: [String: Any] = [
            "type": WatchMessageType.workoutUpdate.rawValue,
            "currentSegmentIndex": currentSegmentIndex,
            "totalDistance": totalDistanceMeters / 1000.0,
            "totalTime": totalTime,
            "heartRate": Int(heartRate)
        ]

        if let targetHeartRate = currentTargetHeartRate {
            message["targetHeartRate"] = targetHeartRate
        }

        if let adaptiveMixCurationTargetSegmentIndex {
            message["adaptiveMixCurationTargetSegmentIndex"] = adaptiveMixCurationTargetSegmentIndex
        }

        NotificationCenter.default.post(name: .workoutUpdate, object: message)
    }
}
#endif
