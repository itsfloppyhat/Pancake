import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum AdaptiveMixCurationTrigger: String {
    case userStarted = "user started"
    case periodicMetrics = "30-second metrics refresh"
    case queueAdvanced = "queue advanced"
    case queueExhausted = "queue exhausted"
    case upcomingInterval = "upcoming interval"
    case segmentChanged = "segment changed"
}

private extension AdaptiveMixCurationTrigger {
    var priority: Int {
        switch self {
        case .periodicMetrics:
            return 0
        case .userStarted, .queueAdvanced:
            return 1
        case .upcomingInterval:
            return 2
        case .segmentChanged, .queueExhausted:
            return 3
        }
    }
}

struct AdaptiveMixQueueSnapshot {
    let revision: Int
    let createdAt: Date
    let trigger: AdaptiveMixCurationTrigger
    let targetSegmentIndex: Int
    let goalScore: AdaptiveMixGoalScore
    let songs: [MusicSong]
    let rejectedCatalogCandidateCount: Int
}

private struct PreparedAdaptiveMix {
    let targetSegmentIndex: Int
    let goalScore: AdaptiveMixGoalScore
    let items: [ResolvedAdaptiveMixItem]
    let rejectedCatalogCandidateCount: Int
    let trigger: AdaptiveMixCurationTrigger
}

// MARK: - Workout Music Coordinator
@MainActor
final class WorkoutMusicCoordinator: ObservableObject {
    static let shared = WorkoutMusicCoordinator()
    
    @Published var isWorkoutActive = false
    @Published var currentWorkoutContext: WorkoutContext?
    @Published var lastMusicSuggestion: MusicSuggestion?
    @Published var liveMetricsWarning: String?
    @Published private(set) var isAdaptiveMixActive = false
    @Published private(set) var isAdaptiveMixCurating = false
    @Published private(set) var adaptiveMixSnapshot: AdaptiveMixQueueSnapshot?
    @Published private(set) var adaptiveMixStatus = "Adaptive Mix is off"
    @Published private(set) var nextAdaptiveMixRefreshAt: Date?

    /// Segments waiting for the watch companion to confirm workout start.
    private var pendingRunPlanSegments: [RunSegment]?

    private let musicManager = MusicPlaybackManager.shared
    private let aiService = MusicAIService.shared
    private let profileManager = UserProfileManager.shared
    private let playedSongHistory = PlayedSongHistoryStore.shared
    private let activeRunState = ActiveRunStateStore.shared
    private var completionInbox: PendingRunCompletionStore?
    private let watchConnectivity = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()


    // Time-series recording
    private var workoutStartTime: Date?
    private var workoutDataPoints: [WorkoutDataPoint] = []
    private var songHistory: [SongPeriod] = []
    private var recordingTimer: Timer?
    private var lastRecordedSongID: String?
    private var liveMetricsMonitorTimer: Timer?
    private var adaptiveMixRefreshTimer: Timer?
    private var lastHeartRateSampleAt: Date?
    private var isLiveMetricsWarningDismissed = false
    private var adaptiveMixRevision = 0
    private var mixTransition = AdaptiveMixTransitionState()
    private var preparedAdaptiveMix: PreparedAdaptiveMix?
    private var musicEnergyAssessments: [String: MusicEnergyAssessment] = [:]
    private var isApplyingAdaptiveMix = false
    private var isMusicPausedByUser = false
    private var pendingAdaptiveMixCuration: (trigger: AdaptiveMixCurationTrigger, targetSegmentIndex: Int)?
    private var lastAdaptiveMixQueueRefillRequestedAt = Date.distantPast
    private var handledWatchAdaptiveMixStartRunID: UUID?
    private static let watchAdaptiveMixStartExpiry: TimeInterval = 30

    // Song pre-fetching
    private var prefetchedSuggestions: [MusicSuggestion] = []
    private var isPrefetching = false
    private var isAdvancingSong = false

    // Session-wide played songs tracking (prevents repeats)
    private var playedSongsThisSession: Set<String> = []
    private var unavailableSongsThisSession: Set<String> = []
    private var recentHeartRateSamples: [Int] = []
    private var recentPlayedSongs: [MusicSong] = []
    private static let maximumSuggestionAttempts = 4
    private static let maximumPlayableSuggestionAttempts = 3
    private static let maximumHeartRateSamples = 5
    private static let maximumRecentSongs = 5
    private static let preferredPrefetchDepth = 2
    private static let liveHeartRateGracePeriod: TimeInterval = 90
    /// After this long without a fresh sample, stop steering music with the last known heart rate.
    private static let heartRateStalenessInterval: TimeInterval = 30
    private static let minimumQueueRefillRequestInterval: TimeInterval = 10
    private static let simulatorLoggingArgument = "--pancake-simulated-run"
    private static let simulatorLoggingEnvironmentKey = "PANCAKE_SIMULATED_RUN"

    var adaptiveMixQueuedSongCount: Int {
        min(musicManager.adaptiveUpcomingSongs.count, AdaptiveMixPolicy.queueDepth)
    }

    var playedSongCount: Int {
        playedSongsThisSession.count
    }

    var adaptiveMixDetail: String {
        guard let snapshot = adaptiveMixSnapshot else {
            return adaptiveMixStatus
        }

        return "Mix \(snapshot.revision) | \(adaptiveMixQueuedSongCount) verified | \(playedSongCount) played | \(snapshot.goalScore.targetIntensity.label) | \(snapshot.goalScore.alignmentScore)% match | \(snapshot.rejectedCatalogCandidateCount) replaced | \(snapshot.trigger.rawValue)"
    }

    private static var isSimulatorLoggingEnabled: Bool {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains(simulatorLoggingArgument) ||
            processInfo.environment[simulatorLoggingEnvironmentKey] == "1"
        #else
        return false
        #endif
    }

    // Fartlek detection
    private var isFartlekWorkout = false
    
    private init() {
        setupWatchConnectivity()
        setupMusicManager()
        retryPendingRunCompletions()
        restoreInterruptedRunIfNeeded()
        for url in RunRouteInbox.pending() { importRouteArchive(at: url) }
    }
    
    // MARK: - Setup
    
    private func setupWatchConnectivity() {
        // Listen for music-related messages from WatchConnectivityManager
        NotificationCenter.default.addObserver(
            forName: .playbackControl,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let action = message["action"] as? String {
                Task { @MainActor in
                    guard let self else { return }
                    if message["runID"] != nil {
                        _ = self.handleIntervalMusicControl(message)
                        return
                    }
                    self.handlePlaybackControl(action)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .workoutControl,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let message = notification.object as? [String: Any] else { return }

            // Handle messages that use the "action" key (e.g. end, pause)
            if let action = message["action"] as? String {
                Task { @MainActor in
                    self?.handleWorkoutControl(action)
                }
            }

            // Handle messages that use the "type" key (workoutStarted, workoutCompleted)
            if let type = message["type"] as? String {
                Task { @MainActor in
                    self?.handleWorkoutControlByType(type, message: message)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .workoutUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any] {
                Task { @MainActor in
                    self?.handleWorkoutUpdate(message)
                }
            }
        }
    }
    
    private func setupMusicManager() {
        // Listen for music playback changes
        musicManager.$currentSong
            .sink { [weak self] song in
                self?.sendCurrentSongToWatch(song)
                self?.trackSongChange(song)
            }
            .store(in: &cancellables)

        musicManager.$isPlaying
            .sink { [weak self] isPlaying in
                self?.sendPlaybackStateToWatch(isPlaying, state: self?.musicManager.playbackStateDescription ?? "stopped")
            }
            .store(in: &cancellables)

        musicManager.$playbackStateDescription
            .sink { [weak self] state in
                guard let self else { return }
                self.sendPlaybackStateToWatch(self.musicManager.isPlaying, state: state)
            }
            .store(in: &cancellables)

        musicManager.$adaptiveUpcomingSongs
            .sink { [weak self] songs in
                self?.sendAdaptiveMixStateToWatch()
                self?.handleAdaptiveMixQueueUpdate(upcomingSongs: songs)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Pending Run Plan (deferred music start)

    /// Store segments from the iPhone run setup so optional suggestions can use
    /// workout context after the watch companion confirms the run has started.
    func setPendingRunPlan(_ segments: [RunSegment]) {
        pendingRunPlanSegments = segments
    }

    // MARK: - Workout Management

    func startWorkoutMusic(segments: [RunSegment], runID: UUID = UUID(), startedAt: Date = Date()) {

        guard !isWorkoutActive else {
            return
        }

        // A run recovered from a previous launch is still waiting for a
        // completion message that is clearly never coming. Save it before the
        // new run overwrites its snapshot.
        if activeRunState.snapshot != nil {
            guard saveRunEvent() else {
                liveMetricsWarning = "The previous run could not be saved. Its recovery data has been kept. Free up storage and reopen Pancake."
                return
            }
            currentWorkoutContext = nil
        }

        isWorkoutActive = true
        handledWatchAdaptiveMixStartRunID = nil
        setIdleTimerDisabled(true)

        // Start time-series recording
        workoutStartTime = startedAt
        workoutDataPoints = []
        songHistory = []
        lastRecordedSongID = nil
        lastHeartRateSampleAt = nil
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false
        startRecordingTimer()
        startLiveMetricsMonitorTimer()
        stopAdaptiveMixRefreshTimer()

        // Reset pre-fetch and session tracking
        prefetchedSuggestions.removeAll()
        isPrefetching = false
        isAdvancingSong = false
        playedSongsThisSession.removeAll()
        unavailableSongsThisSession.removeAll()
        recentHeartRateSamples.removeAll()
        recentPlayedSongs.removeAll()
        lastMusicSuggestion = nil
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false

        // Mirror the run to disk from the first moment, so it survives the app
        // being suspended or terminated before the watch reports completion.
        activeRunState.beginRun(id: runID, segments: segments, startedAt: startedAt)

        // Open a history slot for this run, then carry the last few runs'
        // songs into the prompt so repeats are discouraged from the first pick.
        playedSongHistory.beginRun()
        aiService.beginVarietySession(carryingOver: playedSongHistory.promptAvoidedSongs)
        resetAdaptiveMixState()

        // Detect if this is a fartlek-style workout
        isFartlekWorkout = detectFartlekWorkout(segments: segments)

        // Create initial workout context
        let context = makeWorkoutContext(
            segments: segments,
            currentSegmentIndex: 0,
            totalDistance: 0,
            totalTime: 0,
            heartRate: nil,
            targetHeartRate: nil
        )

        currentWorkoutContext = context

        // Prepare optional music context. Playback starts only after a user action.
        musicManager.startWorkoutMusic()

        // Let the Cheer Squad know (no-op unless sharing is set up).
        CheerSquadManager.shared.workoutDidStart(startedAt: startedAt)
    }
    
    func stopWorkoutMusic() {
        // Also clear restored runs, which have context but aren't active yet.

        // Stop recording timer
        stopRecordingTimer()
        stopLiveMetricsMonitorTimer()
        stopAdaptiveMixRefreshTimer()

        // Close the final song period
        closeFinalSongPeriod()

        isWorkoutActive = false
        setIdleTimerDisabled(false)
        currentWorkoutContext = nil
        prefetchedSuggestions.removeAll()
        isPrefetching = false
        isAdvancingSong = false
        recentHeartRateSamples.removeAll()
        recentPlayedSongs.removeAll()
        playedSongsThisSession.removeAll()
        unavailableSongsThisSession.removeAll()
        lastMusicSuggestion = nil
        lastHeartRateSampleAt = nil
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false
        aiService.endVarietySession()
        // A failed history commit must retain its on-disk recovery checkpoint.
        resetAdaptiveMixState()

        // Stop music playback
        musicManager.stopWorkoutMusic()

        // End the private run broadcast, including after process recovery.
        CheerSquadManager.shared.workoutDidEnd()
    }
    
    // MARK: - Adaptive Mix

    func startAdaptiveMixUserRequested() async {
        guard isWorkoutActive, let context = currentWorkoutContext else {
            adaptiveMixStatus = "Start a workout before starting Adaptive Mix"
            sendAdaptiveMixStateToWatch()
            return
        }

        guard musicManager.hasCatalogAccess else {
            adaptiveMixStatus = "Connect Apple Music playback on iPhone to use Adaptive Mix"
            sendAdaptiveMixStateToWatch()
            return
        }

        guard !isAdaptiveMixActive else {
            return
        }

        isAdaptiveMixActive = true
        mixTransition.advance(to: context.currentSegmentIndex)
        updateAdaptiveMixTransition(secondsRemaining: context.timeRemainingInSegment)
        adaptiveMixStatus = "Curating Adaptive Mix"
        sendAdaptiveMixStateToWatch()

        await requestAdaptiveMixCuration(
            trigger: .userStarted,
            targetSegmentIndex: mixTransition.targetSegmentIndex,
            shouldStartPlayback: true
        )
    }

    private func requestAdaptiveMixCuration(
        trigger: AdaptiveMixCurationTrigger,
        targetSegmentIndex: Int,
        shouldStartPlayback: Bool = false
    ) async {
        guard isAdaptiveMixActive, let workoutContext = currentWorkoutContext,
              !workoutContext.segments.isEmpty else { return }

        // Refills and refreshes follow the music target, which can already be
        // ahead of the watch's current interval. Never regress to the old zone.
        let target = min(max(targetSegmentIndex, mixTransition.targetSegmentIndex), workoutContext.segments.count - 1)
        guard !isAdaptiveMixCurating, !isApplyingAdaptiveMix else {
            rememberPendingAdaptiveMixCuration(trigger: trigger, targetSegmentIndex: target)
            return
        }
        if target < mixTransition.curationSegmentIndex, preparedAdaptiveMix == nil,
           !shouldStartPlayback, trigger != .queueExhausted {
            return // Preparation for the next zone already has priority.
        }

        let sessionID = mixTransition.sessionID
        let musicContext = makeAdaptiveMixContext(from: workoutContext, targetSegmentIndex: target)
        let goalScore = AdaptiveMixPolicy.goalScore(
            targetIntensity: musicContext.currentIntensity,
            targetHeartRate: musicContext.targetHeartRate,
            effectiveHeartRate: musicContext.effectiveHeartRate
        )
        isAdaptiveMixCurating = true
        adaptiveMixStatus = "Preparing \(musicContext.currentIntensity.label) music"
        sendAdaptiveMixStateToWatch()

        var candidates: [MusicSuggestion] = []
        do {
            candidates = try await aiService.generateAdaptiveMixSuggestions(
                context: musicContext,
                userPreferences: profileManager.userProfile.musicPreferences,
                goalScore: goalScore,
                avoidedSongs: adaptiveMixPromptAvoidedSongs(shouldStartPlayback: shouldStartPlayback)
            )
        } catch {
            print("Adaptive Mix generation unavailable: \(error)")
        }
        guard mixTransition.sessionID == sessionID else { return }
        guard mixTransition.acceptsResult(sessionID: sessionID, segmentIndex: target) else {
            isAdaptiveMixCurating = false
            await drainPendingAdaptiveMixCuration()
            return
        }

        candidates.append(contentsOf: adaptiveMixFallbackSuggestions(for: goalScore))
        candidates = uniqueAdaptiveMixSuggestions(candidates, excluding: adaptiveMixExcludedSongKeys(shouldStartPlayback: false))
        // Bound the independent review. Reuse recording assessments across
        // zones, but always recheck their fit against this request's goal.
        let unassessed = Array(candidates.filter { musicEnergyAssessments[$0.sessionSongKey] == nil }.prefix(8))
        do {
            let assessments = try await aiService.assessSongEnergy(unassessed)
            guard mixTransition.sessionID == sessionID else { return }
            musicEnergyAssessments.merge(assessments) { _, new in new }
        } catch {
            print("Adaptive Mix energy review unavailable; using previously assessed songs only: \(error)")
        }
        guard mixTransition.sessionID == sessionID else { return }
        guard mixTransition.acceptsResult(sessionID: sessionID, segmentIndex: target) else {
            isAdaptiveMixCurating = false
            await drainPendingAdaptiveMixCuration()
            return
        }
        let suitableCandidates = candidates.filter { musicEnergyAssessments[$0.sessionSongKey]?.fits(goalScore) == true }
        print("Adaptive Mix energy check: \(suitableCandidates.count)/\(candidates.count) fit \(goalScore.targetIntensity.label)")
        let report = await musicManager.resolveAdaptiveMixSuggestions(
            suitableCandidates,
            excluding: adaptiveMixExcludedSongKeys(shouldStartPlayback: false),
            limit: AdaptiveMixPolicy.queueDepth + 1
        )
        guard mixTransition.sessionID == sessionID else { return }

        if isWorkoutActive, isAdaptiveMixActive,
           mixTransition.acceptsResult(sessionID: sessionID, segmentIndex: target),
           !report.items.isEmpty {
            let prepared = PreparedAdaptiveMix(
                targetSegmentIndex: target, goalScore: goalScore, items: report.items,
                rejectedCatalogCandidateCount: report.rejectedSuggestionCount, trigger: trigger
            )
            if target > mixTransition.targetSegmentIndex {
                preparedAdaptiveMix = prepared
                adaptiveMixStatus = "\(goalScore.targetIntensity.label) music ready for the next interval"
            } else {
                await applyAdaptiveMix(prepared, sessionID: sessionID)
            }
        } else if mixTransition.acceptsResult(sessionID: sessionID, segmentIndex: target) {
            // Never pad a hard interval with unassessed favorites just to fill
            // three slots. Keep the current song and retry a suitable queue.
            adaptiveMixStatus = "Finding songs that fit \(goalScore.targetIntensity.label)"
        }
        guard mixTransition.sessionID == sessionID else { return }
        isAdaptiveMixCurating = false
        restartAdaptiveMixRefreshTimer()
        sendAdaptiveMixStateToWatch()
        await drainPendingAdaptiveMixCuration()
    }

    private func applyAdaptiveMix(_ prepared: PreparedAdaptiveMix, sessionID: UUID) async {
        guard !isApplyingAdaptiveMix, isAdaptiveMixActive,
              mixTransition.sessionID == sessionID,
              prepared.targetSegmentIndex == mixTransition.targetSegmentIndex,
              let context = currentWorkoutContext else { return }
        let liveContext = makeAdaptiveMixContext(from: context, targetSegmentIndex: prepared.targetSegmentIndex)
        let goalScore = AdaptiveMixPolicy.goalScore(
            targetIntensity: liveContext.currentIntensity, targetHeartRate: liveContext.targetHeartRate,
            effectiveHeartRate: liveContext.effectiveHeartRate
        )
        let excluded = adaptiveMixExcludedSongKeys(shouldStartPlayback: false)
        let items = prepared.items.filter {
            !excluded.contains($0.song.sessionSongKey) && musicEnergyAssessments[$0.sourceSongKey]?.fits(goalScore) == true
        }
        guard items.count >= AdaptiveMixPolicy.minimumStartSongCount else { return }
        if isMusicPausedByUser {
            preparedAdaptiveMix = prepared
            adaptiveMixStatus = "\(goalScore.targetIntensity.label) music ready; playback paused"
            return
        }
        isApplyingAdaptiveMix = true

        let mustChangeSong = adaptiveMixSnapshot?.goalScore.targetIntensity != prepared.goalScore.targetIntensity
        let didApply: Bool
        if mustChangeSong || !musicManager.hasActiveAdaptiveQueueEntry {
            didApply = await musicManager.startAdaptiveMix(with: items)
        } else {
            didApply = musicManager.replaceAdaptiveMixUpcoming(with: Array(items.prefix(AdaptiveMixPolicy.queueDepth)))
        }
        guard mixTransition.sessionID == sessionID else { return }
        isApplyingAdaptiveMix = false
        guard prepared.targetSegmentIndex == mixTransition.targetSegmentIndex else { return }
        if didApply {
            adaptiveMixRevision += 1
            adaptiveMixSnapshot = AdaptiveMixQueueSnapshot(
                revision: adaptiveMixRevision, createdAt: Date(), trigger: prepared.trigger,
                targetSegmentIndex: prepared.targetSegmentIndex, goalScore: goalScore,
                songs: Array(musicManager.adaptiveUpcomingSongs.prefix(AdaptiveMixPolicy.queueDepth)),
                rejectedCatalogCandidateCount: prepared.rejectedCatalogCandidateCount
            )
            adaptiveMixStatus = adaptiveMixStatusText(
                queueCount: musicManager.adaptiveUpcomingSongs.count,
                targetIntensity: prepared.goalScore.targetIntensity,
                rejectedCatalogCandidateCount: prepared.rejectedCatalogCandidateCount
            )
            logSimulatorQueueSnapshotIfNeeded(trigger: prepared.trigger)
            if mustChangeSong {
                PancakeSimulatorLog("PANCAKE_SIM:TRANSITION target=\(prepared.targetSegmentIndex) time=\(currentWorkoutContext?.totalTime ?? 0)")
            }
        }
        #if DEBUG
        AdaptiveMixEvalRecorder.shared.recordCuration(
            trigger: prepared.trigger.rawValue, goalScore: goalScore,
            resolvedSongs: items.map(\.song), applied: didApply,
            preferences: profileManager.userProfile.musicPreferences
        )
        #endif
        sendAdaptiveMixStateToWatch()
    }

    private func drainPendingAdaptiveMixCuration() async {
        guard !isAdaptiveMixCurating, !isApplyingAdaptiveMix else { return }
        if let pending = pendingAdaptiveMixCuration {
            pendingAdaptiveMixCuration = nil
            await requestAdaptiveMixCuration(
                trigger: pending.trigger,
                targetSegmentIndex: max(pending.targetSegmentIndex, mixTransition.targetSegmentIndex)
            )
        }
    }

    private func rememberPendingAdaptiveMixCuration(
        trigger: AdaptiveMixCurationTrigger,
        targetSegmentIndex: Int
    ) {
        if let pendingAdaptiveMixCuration {
            if pendingAdaptiveMixCuration.targetSegmentIndex > targetSegmentIndex { return }
            if pendingAdaptiveMixCuration.targetSegmentIndex == targetSegmentIndex,
               pendingAdaptiveMixCuration.trigger.priority > trigger.priority { return }
        }

        pendingAdaptiveMixCuration = (trigger, targetSegmentIndex)
    }

    private func restartAdaptiveMixRefreshTimer() {
        guard isAdaptiveMixActive else { return }

        stopAdaptiveMixRefreshTimer()
        nextAdaptiveMixRefreshAt = Date().addingTimeInterval(AdaptiveMixPolicy.refreshInterval)
        adaptiveMixRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: AdaptiveMixPolicy.refreshInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.currentWorkoutContext != nil else { return }

                self.restartAdaptiveMixRefreshTimer()
                await self.requestAdaptiveMixCuration(
                    trigger: .periodicMetrics,
                    targetSegmentIndex: self.preparedAdaptiveMix == nil
                        ? self.mixTransition.curationSegmentIndex : self.mixTransition.targetSegmentIndex
                )
            }
        }
    }

    private func stopAdaptiveMixRefreshTimer() {
        adaptiveMixRefreshTimer?.invalidate()
        adaptiveMixRefreshTimer = nil
        nextAdaptiveMixRefreshAt = nil
    }

    private func resetAdaptiveMixState() {
        stopAdaptiveMixRefreshTimer()
        isAdaptiveMixActive = false
        isAdaptiveMixCurating = false
        adaptiveMixSnapshot = nil
        adaptiveMixStatus = "Adaptive Mix is off"
        adaptiveMixRevision = 0
        mixTransition = AdaptiveMixTransitionState()
        preparedAdaptiveMix = nil
        musicEnergyAssessments.removeAll()
        isApplyingAdaptiveMix = false
        isMusicPausedByUser = false
        musicManager.invalidatePendingAdaptiveStart()
        pendingAdaptiveMixCuration = nil
        lastAdaptiveMixQueueRefillRequestedAt = .distantPast
        sendAdaptiveMixStateToWatch()
    }

    private func handleAdaptiveMixQueueUpdate(upcomingSongs: [MusicSong]) {
        guard isWorkoutActive,
              isAdaptiveMixActive,
              musicManager.isAdaptivePlaybackActive,
              // While a curation is replacing the queue, the entry count dips
              // transiently; reacting to those dips chain-fires refills every
              // few seconds on device. Real advances are re-checked when the
              // in-flight curation publishes its final queue.
              !isAdaptiveMixCurating,
              !isApplyingAdaptiveMix,
              adaptiveMixSnapshot?.targetSegmentIndex == mixTransition.targetSegmentIndex,
              upcomingSongs.count < AdaptiveMixPolicy.queueDepth,
              currentWorkoutContext != nil else {
            return
        }

        let shouldRestartPlayback = !musicManager.hasActiveAdaptiveQueueEntry
        let now = Date()

        if !shouldRestartPlayback,
           now.timeIntervalSince(lastAdaptiveMixQueueRefillRequestedAt) < Self.minimumQueueRefillRequestInterval {
            return
        }

        lastAdaptiveMixQueueRefillRequestedAt = now

        Task { @MainActor in
            await requestAdaptiveMixCuration(
                trigger: shouldRestartPlayback ? .queueExhausted : .queueAdvanced,
                targetSegmentIndex: mixTransition.targetSegmentIndex,
                shouldStartPlayback: shouldRestartPlayback
            )
        }
    }

    private var hasFreshHeartRateSample: Bool {
        guard let lastHeartRateSampleAt else { return false }
        return Date().timeIntervalSince(lastHeartRateSampleAt) <= Self.heartRateStalenessInterval
    }

    private func makeAdaptiveMixContext(
        from workoutContext: WorkoutContext,
        targetSegmentIndex: Int
    ) -> MusicContext {
        let boundedTargetIndex = min(max(0, targetSegmentIndex), workoutContext.segments.count - 1)
        let targetSegment = workoutContext.segments[boundedTargetIndex]
        // Adaptive Mix follows each explicit interval, including one-minute
        // efforts. The legacy single-song path still has its own lookahead.
        let targetIntensity = targetSegment.intensity
        let currentContext = workoutContext.musicContext
        let timeRemaining = if boundedTargetIndex == workoutContext.currentSegmentIndex {
            workoutContext.timeRemainingInSegment
        } else {
            segmentDurationSeconds(targetSegment)
        }

        return MusicContext(
            currentHeartRate: currentContext.currentHeartRate,
            guidanceHeartRate: currentContext.guidanceHeartRate,
            targetHeartRate: targetIntensity.defaultTargetHeartRate,
            heartRateTrend: currentContext.heartRateTrend,
            hasStableHeartRateSignal: currentContext.hasStableHeartRateSignal,
            currentIntensity: targetIntensity,
            timeRemainingInSegment: timeRemaining,
            currentSongEndingIn: currentContext.currentSongEndingIn,
            userPreferences: currentContext.userPreferences,
            recentSongs: currentContext.recentSongs,
            currentDistance: currentContext.currentDistance,
            currentPace: currentContext.currentPace,
            isActive: currentContext.isActive
        )
    }

    /// Saved taste supplies candidates, never automatic eligibility. These
    /// recordings receive the same independent energy review as AI picks.
    private func adaptiveMixFallbackSuggestions(for goalScore: AdaptiveMixGoalScore) -> [MusicSuggestion] {
        MusicRecommendationPolicy.fallbackSuggestions(
            preferences: profileManager.userProfile.musicPreferences,
            intensity: goalScore.targetIntensity
        )
    }

    private func adaptiveMixExcludedSongKeys(shouldStartPlayback: Bool) -> Set<String> {
        var songKeys = excludedSongKeys
            .union(prefetchedSuggestions.map(\.sessionSongKey))

        if let currentSong = musicManager.currentSong {
            songKeys.insert(currentSong.sessionSongKey)
        }

        if shouldStartPlayback {
            songKeys.formUnion(musicManager.adaptiveUpcomingSongs.map(\.sessionSongKey))
        }

        return songKeys
    }

    private func adaptiveMixPromptAvoidedSongs(shouldStartPlayback: Bool) -> [MusicSong] {
        var songs: [MusicSong] = []
        var seenSongKeys = Set<String>()

        func appendIfNew(_ song: MusicSong) {
            guard seenSongKeys.insert(song.sessionSongKey).inserted else {
                return
            }
            songs.append(song)
        }

        recentPlayedSongs.forEach(appendIfNew)

        if let currentSong = musicManager.currentSong {
            appendIfNew(currentSong)
        }

        // Songs still resting from recent runs. Capped by the store so a long
        // avoid list cannot crowd out the rest of the prompt; the full set is
        // still enforced by key filtering in adaptiveMixExcludedSongKeys.
        playedSongHistory.promptAvoidedSongs.forEach(appendIfNew)

        if !shouldStartPlayback {
            for song in musicManager.adaptiveUpcomingSongs {
                appendIfNew(song)
            }
        }

        return songs
    }

    private func uniqueAdaptiveMixSuggestions(
        _ suggestions: [MusicSuggestion],
        excluding excludedSongKeys: Set<String>
    ) -> [MusicSuggestion] {
        var seenKeys = Set<String>()

        return suggestions
            .map { $0.cleanedTitle() }
            .filter { suggestion in
                AdaptiveMixPolicy.canQueue(
                    songKey: suggestion.sessionSongKey,
                    playedSongKeys: excludedSongKeys,
                    temporarilyReservedSongKeys: seenKeys
                ) &&
                    seenKeys.insert(suggestion.sessionSongKey).inserted
            }
    }

    private func adaptiveMixStatusText(
        queueCount: Int,
        targetIntensity: Intensity,
        rejectedCatalogCandidateCount: Int
    ) -> String {
        "\(min(queueCount, AdaptiveMixPolicy.queueDepth)) Apple Music songs verified for \(targetIntensity.label); \(rejectedCatalogCandidateCount) replaced"
    }

    // MARK: - Music Suggestion Generation

    /// User-initiated "new song" request from the Watch button.
    /// Uses pre-fetched song if available for instant response.
    func generateNextSongUserRequested() async {
        guard beginSongAdvance() else { return }
        defer { finishSongAdvance() }

        // If we have a pre-fetched suggestion, play it immediately
        if let prefetched = takePrefetchedSuggestion(),
           await playSuggestedSong(prefetched) {
            triggerPrefetch()
            return
        }

        guard let context = currentWorkoutContext else { return }

        let upcomingIntensity: Intensity? = if isFartlekWorkout {
            effectiveIntensity(at: context.currentSegmentIndex, segments: context.segments)
        } else {
            context.upcomingSegment?.intensity
        }

        let fallbackIntensity = upcomingIntensity ?? context.currentSegment.intensity

        let played = await resolveAndPlaySuggestion(fallbackIntensity: fallbackIntensity) {
            try await self.aiService.generateIntervalChangeSuggestion(
                context: context.musicContext,
                userPreferences: self.profileManager.userProfile.musicPreferences,
                currentDistance: context.totalDistance,
                currentTime: context.totalTime,
                upcomingIntensity: upcomingIntensity,
                isFartlek: self.isFartlekWorkout,
                mustUseLibrary: self.mustUseLibrarySuggestions
            )
        }

        if played {
            triggerPrefetch()
        }
    }

    // MARK: - Song Pre-fetching

    /// Start a pre-fetch in the background (non-blocking)
    private func triggerPrefetch() {
        guard isWorkoutActive,
              !isPrefetching,
              prefetchedSuggestions.count < Self.preferredPrefetchDepth else { return }

        Task {
            await prefetchNextSong()
        }
    }

    private func prefetchNextSong() async {
        guard let context = currentWorkoutContext else { return }
        guard !isPrefetching else { return }

        isPrefetching = true

        let upcomingIntensity: Intensity? = if isFartlekWorkout {
            effectiveIntensity(at: context.currentSegmentIndex, segments: context.segments)
        } else {
            context.upcomingSegment?.intensity
        }

        if let suggestion = await requestPrefetchSuggestion(
            context: context,
            upcomingIntensity: upcomingIntensity
        ) {
            let songKey = suggestion.sessionSongKey
            let reservedKeys = Set(prefetchedSuggestions.map(\.sessionSongKey))

            if !reservedKeys.contains(songKey) {
                prefetchedSuggestions.append(suggestion)
            }
        }

        isPrefetching = false

        if isWorkoutActive, prefetchedSuggestions.count < Self.preferredPrefetchDepth {
            triggerPrefetch()
        }
    }

    private func requestPrefetchSuggestion(
        context: WorkoutContext,
        upcomingIntensity: Intensity?
    ) async -> MusicSuggestion? {
        let fallbackIntensity = upcomingIntensity ?? context.currentSegment.intensity

        return await resolveUniqueSuggestion(fallbackIntensity: fallbackIntensity) {
            try await self.aiService.generateIntervalChangeSuggestion(
                context: context.musicContext,
                userPreferences: self.profileManager.userProfile.musicPreferences,
                currentDistance: context.totalDistance,
                currentTime: context.totalTime,
                upcomingIntensity: upcomingIntensity,
                isFartlek: self.isFartlekWorkout,
                mustUseLibrary: self.mustUseLibrarySuggestions
            )
        }
    }

    @discardableResult
    private func playSuggestedSong(_ suggestion: MusicSuggestion) async -> Bool {
        let cleaned = suggestion.cleanedTitle()
        let songKey = cleaned.sessionSongKey

        guard !excludedSongKeys.contains(songKey) else {
            return false
        }

        let didStartPlaying = await musicManager.playSuggestedSong(cleaned)
        guard didStartPlaying else {
            unavailableSongsThisSession.insert(songKey)
            return false
        }

        playedSongsThisSession.insert(songKey)
        if let actualSongKey = musicManager.currentSong?.sessionSongKey {
            playedSongsThisSession.insert(actualSongKey)
        }
        unavailableSongsThisSession.remove(songKey)
        lastMusicSuggestion = cleaned
        return true
    }

    private func resolveUniqueSuggestion(
        fallbackIntensity: Intensity,
        generator: @escaping () async throws -> MusicSuggestion
    ) async -> MusicSuggestion? {
        do {
            if let suggestion = try await requestUniqueSuggestion(generator: generator) {
                return suggestion
            }
        } catch {
            print("Suggestion generation fell back: \(error)")
        }

        guard let fallback = aiService.fallbackSuggestion(
            preferences: profileManager.userProfile.musicPreferences,
            intensity: fallbackIntensity,
            avoiding: reservedSongKeys
        )?.cleanedTitle() else {
            return nil
        }

        guard !reservedSongKeys.contains(fallback.sessionSongKey) else {
            return nil
        }

        return fallback
    }

    private func resolveAndPlaySuggestion(
        fallbackIntensity: Intensity,
        generator: @escaping () async throws -> MusicSuggestion
    ) async -> Bool {
        for _ in 0..<Self.maximumPlayableSuggestionAttempts {
            guard let suggestion = await resolveUniqueSuggestion(
                fallbackIntensity: fallbackIntensity,
                generator: generator
            ) else {
                break
            }

            if await playSuggestedSong(suggestion) {
                return true
            }
        }

        // Last resort. The first attempt still rests songs from recent runs;
        // the retry drops only that window so a small library ends up hearing
        // a repeat rather than silence.
        for includingRecentRuns in [true, false] {
            guard let emergencySuggestion = await musicManager.playEmergencyFallback(
                preferences: profileManager.userProfile.musicPreferences,
                intensity: fallbackIntensity,
                avoiding: reservedSongKeys(includingRecentRuns: includingRecentRuns)
            ) else {
                continue
            }

            if !includingRecentRuns {
                print("Emergency fallback replayed a song still resting from a recent run")
            }

            let songKey = emergencySuggestion.sessionSongKey
            playedSongsThisSession.insert(songKey)
            if let actualSongKey = musicManager.currentSong?.sessionSongKey {
                playedSongsThisSession.insert(actualSongKey)
            }
            unavailableSongsThisSession.remove(songKey)
            lastMusicSuggestion = emergencySuggestion
            return true
        }

        return false
    }

    private func requestUniqueSuggestion(
        maxAttempts: Int? = nil,
        generator: () async throws -> MusicSuggestion
    ) async throws -> MusicSuggestion? {
        let maxAttempts = maxAttempts ?? Self.maximumSuggestionAttempts
        var attemptedKeys = Set<String>()

        for _ in 0..<maxAttempts {
            let suggestion = (try await generator()).cleanedTitle()
            let songKey = suggestion.sessionSongKey

            guard !reservedSongKeys.contains(songKey),
                  attemptedKeys.insert(songKey).inserted else {
                continue
            }

            return suggestion
        }

        return nil
    }

    private func takePrefetchedSuggestion() -> MusicSuggestion? {
        while !prefetchedSuggestions.isEmpty {
            let prefetchedSuggestion = prefetchedSuggestions.removeFirst().cleanedTitle()

            guard !excludedSongKeys.contains(prefetchedSuggestion.sessionSongKey) else {
                continue
            }

            return prefetchedSuggestion
        }

        return nil
    }

    private func beginSongAdvance() -> Bool {
        guard isWorkoutActive else { return false }
        guard !isAdvancingSong else { return false }

        isAdvancingSong = true
        return true
    }

    private func finishSongAdvance() {
        isAdvancingSong = false
    }

    /// Songs already played or known unavailable during this workout.
    private var sessionExcludedSongKeys: Set<String> {
        playedSongsThisSession.union(unavailableSongsThisSession)
    }

    /// Songs that must not play again: this session's exclusions plus
    /// everything still resting inside the recent-runs window.
    private var excludedSongKeys: Set<String> {
        sessionExcludedSongKeys.union(playedSongHistory.avoidedSongKeys)
    }

    private var reservedSongKeys: Set<String> {
        reservedSongKeys(includingRecentRuns: true)
    }

    private func reservedSongKeys(includingRecentRuns: Bool) -> Set<String> {
        let base = includingRecentRuns ? excludedSongKeys : sessionExcludedSongKeys

        return base
            .union(prefetchedSuggestions.map(\.sessionSongKey))
            .union(musicManager.adaptiveUpcomingSongs.map(\.sessionSongKey))
    }

    private var mustUseLibrarySuggestions: Bool {
        musicManager.hasLibraryAccess && !musicManager.hasCatalogAccess
    }

    // MARK: - Fartlek Detection & Lookahead

    /// Analyzes the workout segments to determine if this is a fartlek-style run.
    /// A fartlek workout has frequent intensity changes with many short segments.
    private func detectFartlekWorkout(segments: [RunSegment]) -> Bool {
        guard segments.count >= 4 else { return false }

        // Count segments shorter than 2 minutes
        let shortSegmentCount = segments.filter { segment in
            segmentDurationSeconds(segment) < 120
        }.count

        // Count intensity changes between consecutive segments
        var intensityChanges = 0
        for i in 1..<segments.count {
            if segments[i].intensity != segments[i - 1].intensity {
                intensityChanges += 1
            }
        }

        // It's fartlek-style if at least half the segments are short
        // AND there are frequent intensity changes (at least once every 2 segments on average)
        let halfAreShort = shortSegmentCount >= segments.count / 2
        let frequentChanges = intensityChanges >= (segments.count - 1) / 2

        return halfAreShort && frequentChanges
    }

    /// Returns the estimated duration of a segment in seconds.
    /// For distance-based segments, estimates using a rough pace.
    private func segmentDurationSeconds(_ segment: RunSegment) -> TimeInterval {
        switch segment.target {
        case .time(let seconds):
            return TimeInterval(seconds)
        case .distance(let meters):
            // Estimate duration by planned heart-rate zone.
            let paceSecondsPerMeter: Double = switch segment.intensity {
            case .zone1: 0.42 // 7:00/km
            case .zone2: 0.36 // 6:00/km
            case .zone3: 0.30 // 5:00/km
            case .zone4: 0.24 // 4:00/km
            case .zone5: 0.21 // 3:30/km
            }
            return Double(meters) * paceSecondsPerMeter
        }
    }

    /// Looks ahead from the current segment and computes the dominant highest zone
    /// over the next ~3-4 minutes of segments. This prevents choosing a chill song right
    /// before a high-zone effort, or during a brief recovery between high-zone efforts.
    private func lookaheadIntensity(from segmentIndex: Int, segments: [RunSegment]) -> Intensity {
        let lookaheadWindowSeconds: TimeInterval = 210 // 3.5 minutes

        var accumulatedTime: TimeInterval = 0
        var intensityCounts = Dictionary(
            uniqueKeysWithValues: Intensity.allCases.map { ($0, TimeInterval.zero) }
        )

        for i in segmentIndex..<segments.count {
            let seg = segments[i]
            let segDuration = segmentDurationSeconds(seg)
            let remaining = lookaheadWindowSeconds - accumulatedTime
            let contribution = min(segDuration, remaining)

            intensityCounts[seg.intensity, default: 0] += contribution
            accumulatedTime += contribution

            if accumulatedTime >= lookaheadWindowSeconds { break }
        }

        // Return the highest zone that occupies a meaningful portion of the window.
        // "Meaningful" = at least 20% of the window, so a single 30s Zone 5 burst in
        // 3.5 min of Zone 2 running won't force a peak-effort song.
        let threshold = lookaheadWindowSeconds * 0.20

        for intensity in Intensity.allCases.reversed() {
            if (intensityCounts[intensity] ?? 0) >= threshold {
                return intensity
            }
        }

        return segments[min(segmentIndex, segments.count - 1)].intensity
    }

    /// Returns the effective intensity to use for music selection at the given segment index.
    /// For fartlek workouts, this uses the lookahead window. For normal workouts, it uses
    /// the current segment's intensity directly.
    private func effectiveIntensity(at segmentIndex: Int, segments: [RunSegment]) -> Intensity {
        if isFartlekWorkout {
            return lookaheadIntensity(from: segmentIndex, segments: segments)
        }
        let idx = min(segmentIndex, segments.count - 1)
        return segments[idx].intensity
    }

    // MARK: - Watch Communication

    private func sendCurrentSongToWatch(_ song: MusicSong?) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }

        guard let song = song else {
            let message: [String: Any] = [
                "type": WatchMessageType.currentSong.rawValue,
                "hasSong": false
            ]
            watchConnectivity.sendMessageWithFallback(message) { _ in }
            return
        }

        do {
            let songData = try JSONEncoder().encode(song)
            let message: [String: Any] = [
                "type": WatchMessageType.currentSong.rawValue,
                "hasSong": true,
                "song": songData
            ]

            watchConnectivity.sendMessageWithFallback(message) { error in
                print("Failed to send current song to watch: \(error)")
            }
        } catch {
            print("Failed to encode current song: \(error)")
        }
    }
    
    private func sendPlaybackStateToWatch(_ isPlaying: Bool, state: String) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.playbackControl.rawValue,
            "isPlaying": isPlaying,
            "state": state
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send playback state to watch: \(error)")
        }
    }

    private func sendAdaptiveMixStateToWatch() {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }

        var message: [String: Any] = [
            "type": WatchMessageType.adaptiveMixState.rawValue,
            "isActive": isAdaptiveMixActive,
            "isCurating": isAdaptiveMixCurating,
            "queuedSongCount": min(musicManager.adaptiveUpcomingSongs.count, AdaptiveMixPolicy.queueDepth),
            "playedSongCount": playedSongCount,
            "status": adaptiveMixStatus
        ]

        if let snapshot = adaptiveMixSnapshot {
            message["revision"] = snapshot.revision
            message["trigger"] = snapshot.trigger.rawValue
            message["targetZone"] = snapshot.goalScore.targetIntensity.label
            message["alignmentScore"] = snapshot.goalScore.alignmentScore
            message["replacedSongCount"] = snapshot.rejectedCatalogCandidateCount
            message["guidanceText"] = friendlyGuidanceText(for: snapshot.goalScore)
        }

        if let nextSong = musicManager.adaptiveUpcomingSongs.first {
            message["nextSongTitle"] = nextSong.title
            message["nextSongArtist"] = nextSong.artist
        }

        if let nextAdaptiveMixRefreshAt {
            message["nextRefreshAt"] = nextAdaptiveMixRefreshAt.timeIntervalSince1970
        }

        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send Adaptive Mix state to watch: \(error)")
        }
    }
    
    private func friendlyGuidanceText(for goalScore: AdaptiveMixGoalScore) -> String {
        switch goalScore.guidance {
        case .easeDown:
            return "Easing you down to \(goalScore.targetIntensity.label)"
        case .lift:
            return "Lifting you toward \(goalScore.targetIntensity.label)"
        case .maintain:
            return "Holding \(goalScore.targetIntensity.label)"
        case .followPlan:
            return "Following your plan: \(goalScore.targetIntensity.label)"
        }
    }

    // MARK: - Helper Methods

    private func advanceAdaptiveMixUserRequested() async {
        guard isAdaptiveMixActive else {
            await musicManager.skipAdaptiveMixToNext()
            return
        }
        guard !isApplyingAdaptiveMix else { return }
        if adaptiveMixSnapshot?.targetSegmentIndex != mixTransition.targetSegmentIndex || musicManager.adaptiveUpcomingSongs.isEmpty {
            let sessionID = mixTransition.sessionID
            let originalSongID = musicManager.currentSong?.id
            await requestAdaptiveMixCuration(trigger: .queueExhausted, targetSegmentIndex: mixTransition.targetSegmentIndex)
            if sessionID == mixTransition.sessionID,
               originalSongID == musicManager.currentSong?.id,
               adaptiveMixSnapshot?.targetSegmentIndex == mixTransition.targetSegmentIndex,
               !musicManager.adaptiveUpcomingSongs.isEmpty {
                await musicManager.skipAdaptiveMixToNext()
            }
            return
        }
        await musicManager.skipAdaptiveMixToNext()
    }

    private func handlePlaybackControl(_ action: String) {
        switch action {
        case "play":
            isMusicPausedByUser = false
            if isAdaptiveMixActive {
                let sessionID = mixTransition.sessionID
                Task {
                    guard sessionID == mixTransition.sessionID else { return }
                    if let prepared = preparedAdaptiveMix, prepared.targetSegmentIndex == mixTransition.targetSegmentIndex {
                        preparedAdaptiveMix = nil
                        await applyAdaptiveMix(prepared, sessionID: sessionID)
                    }
                    guard sessionID == mixTransition.sessionID else { return }
                    if adaptiveMixSnapshot?.targetSegmentIndex == mixTransition.targetSegmentIndex {
                        musicManager.play()
                    } else {
                        await requestAdaptiveMixCuration(trigger: .segmentChanged, targetSegmentIndex: mixTransition.targetSegmentIndex)
                    }
                    await drainPendingAdaptiveMixCuration()
                }
            } else {
                musicManager.play()
            }
        case "pause":
            isMusicPausedByUser = true
            musicManager.invalidatePendingAdaptiveStart()
            musicManager.pause()
        case "stop":
            resetAdaptiveMixState()
            musicManager.stop()
        case "adaptiveMix":
            Task {
                await startAdaptiveMixUserRequested()
            }
        case "next":
            Task {
                await advanceAdaptiveMixUserRequested()
            }
        case "suggest":
            Task {
                if isAdaptiveMixActive {
                    await advanceAdaptiveMixUserRequested()
                } else {
                    await generateNextSongUserRequested()
                }
            }
        default:
            break
        }
    }
    
    private func handleWorkoutControl(_ action: String) {
        switch action {
        case "end":
            // Commit before tearing down the live context; a failed commit
            // retains its recovery checkpoint.
            saveRunEvent()
            stopWorkoutMusic()
        case "pause":
            break
        default:
            break
        }
    }

    private func setIdleTimerDisabled(_ isDisabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = isDisabled
        #endif
    }

    /// Keep the optional playback request tied to the run that carried it.
    /// Workout starts remain durable, but a queued music request expires quickly.
    private func startAdaptiveMixFromWorkoutMessageIfRequested(_ message: [String: Any], runID: UUID) {
        guard message["startAdaptiveMix"] as? Bool == true,
              isWorkoutActive,
              activeRunState.snapshot?.id == runID,
              handledWatchAdaptiveMixStartRunID != runID,
              let timestamp = message["startedAt"] as? Double,
              timestamp.isFinite else { return }

        let startedAt = Date(timeIntervalSince1970: timestamp)
        let age = Date().timeIntervalSince(startedAt)
        guard age >= -5, age <= Self.watchAdaptiveMixStartExpiry else { return }

        // Both workoutStart and workoutStarted can arrive for the same run.
        handledWatchAdaptiveMixStartRunID = runID
        Task { [weak self] in
            guard let self,
                  self.isWorkoutActive,
                  self.activeRunState.snapshot?.id == runID,
                  Date().timeIntervalSince(startedAt) <= Self.watchAdaptiveMixStartExpiry else { return }
            await self.startAdaptiveMixUserRequested()
        }
    }

    /// Handles workout control messages keyed by "type" (sent by the Watch).
    /// The Watch sends messages like {"type": "workoutStarted"} and {"type": "workoutCompleted"}.
    private func handleWorkoutControlByType(_ type: String, message: [String: Any]) {
        switch type {
        case WatchMessageType.workoutStarted.rawValue, WatchMessageType.workoutStart.rawValue:
            if message["runID"] == nil, isWorkoutActive { return }
            let runID = (message["runID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            guard !RunHistoryStore.shared.contains(runID: runID), !activeRunState.hasSaved(runID: runID) else { return }
            if isWorkoutActive {
                if activeRunState.snapshot?.id == runID {
                    startAdaptiveMixFromWorkoutMessageIfRequested(message, runID: runID)
                    return
                }
                // A new Watch run supersedes an interrupted session on this phone.
                saveRunEvent()
                stopWorkoutMusic()
            }
            let startedAt = (message["startedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            let segments = decodeSegmentsFromWatchMessage(message) ?? pendingRunPlanSegments
                ?? [RunSegment(intensity: .zone2, target: .time(seconds: 1800))]
            pendingRunPlanSegments = nil
            startWorkoutMusic(segments: segments, runID: runID, startedAt: startedAt)
            startAdaptiveMixFromWorkoutMessageIfRequested(message, runID: runID)

        case WatchMessageType.workoutCompleted.rawValue:
            let completedRunID = (message["runID"] as? String).flatMap(UUID.init(uuidString:))
            if let completedRunID,
               let saved = RunHistoryStore.shared.events.first(where: { $0.id == completedRunID }) {
                // A snapshot may have reached history before the Watch's final
                // totals arrived. Preserve its detail while upserting those totals.
                let event = RunEvent(id: saved.id, date: saved.date,
                    totalDistanceMeters: (message["totalDistanceKm"] as? Double).map { Int($0 * 1000) } ?? saved.totalDistanceMeters,
                    totalTimeSeconds: message["totalTimeSeconds"] as? Int ?? saved.totalTimeSeconds,
                    segments: saved.segments.isEmpty ? (decodeSegmentsFromWatchMessage(message) ?? []) : saved.segments,
                    dataPoints: saved.dataPoints, songHistory: saved.songHistory, routePoints: saved.routePoints)
                let committed = commitCompletedRun(event)
                if activeRunState.snapshot?.id == completedRunID {
                    if committed { activeRunState.clear() }
                    stopWorkoutMusic()
                } else if !isWorkoutActive, activeRunState.snapshot == nil {
                    CheerSquadManager.shared.workoutDidEnd()
                }
                return
            }
            if let completedRunID, activeRunState.hasSaved(runID: completedRunID) {
                // Don't recreate history that the user already deleted.
                return
            }

            // A delayed completion must not finish a different, newer workout.
            if let completedRunID, completedRunID != activeRunState.snapshot?.id {
                let seconds = message["totalTimeSeconds"] as? Int ?? 0
                let distance = message["totalDistanceKm"] as? Double ?? 0
                guard seconds > 0 || distance > 0 else { return }
                let endedAt = (message["endedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
                let startedAt = (message["startedAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                    ?? endedAt.addingTimeInterval(-Double(seconds))
                let event = RunEvent(id: completedRunID, date: startedAt,
                                     totalDistanceMeters: Int(distance * 1000), totalTimeSeconds: seconds,
                                     segments: decodeSegmentsFromWatchMessage(message) ?? [])
                _ = commitCompletedRun(event)
                if !isWorkoutActive, activeRunState.snapshot == nil { CheerSquadManager.shared.workoutDidEnd() }
                return
            }

            pendingRunPlanSegments = nil
            if let context = currentWorkoutContext {
                let finalDistanceKm = message["totalDistanceKm"] as? Double ?? context.totalDistance
                let finalTimeSeconds = message["totalTimeSeconds"] as? Int ?? Int(context.totalTime)
                currentWorkoutContext = makeWorkoutContext(
                    segments: context.segments,
                    currentSegmentIndex: context.currentSegmentIndex,
                    totalDistance: finalDistanceKm,
                    totalTime: TimeInterval(finalTimeSeconds),
                    heartRate: context.musicContext.currentHeartRate,
                    targetHeartRate: context.musicContext.targetHeartRate
                )
            }
            saveRunEvent()
            stopWorkoutMusic()

        default:
            break
        }
    }

    private func decodeSegmentsFromWatchMessage(_ message: [String: Any]) -> [RunSegment]? {
        if let data = message["segments"] as? Data,
           let segments = try? JSONDecoder().decode([RunSegment].self, from: data), !segments.isEmpty {
            return segments
        }
        guard let rawSegments = message["segments"] as? [[String: Any]], !rawSegments.isEmpty else {
            return nil
        }

        let segments = rawSegments.compactMap { rawSegment -> RunSegment? in
            guard let intensityRaw = rawSegment["intensity"] as? String,
                  let intensity = Intensity.fromStoredRawValue(intensityRaw),
                  let targetDictionary = rawSegment["target"] as? [String: Any],
                  let targetType = targetDictionary["type"] as? String,
                  let targetValue = targetDictionary["value"] as? Int else {
                return nil
            }

            let target: Target
            switch targetType {
            case "time":
                target = .time(seconds: targetValue)
            case "distance":
                target = .distance(meters: targetValue)
            default:
                return nil
            }

            return RunSegment(intensity: intensity, target: target)
        }

        return segments.isEmpty ? nil : segments
    }
    
    private func handleWorkoutUpdate(_ message: [String: Any]) {
        if let runID = message["runID"] as? String {
            guard activeRunState.snapshot?.id.uuidString == runID else { return }
        }
        guard isWorkoutActive, let context = currentWorkoutContext else { return }

        let segmentIndex = message["currentSegmentIndex"] as? Int ?? context.currentSegmentIndex
        let totalDistance = message["totalDistance"] as? Double ?? context.totalDistance
        let totalTime = message["totalTime"] as? Double ?? context.totalTime
        guard segmentIndex >= context.currentSegmentIndex,
              context.segments.indices.contains(segmentIndex),
              totalTime >= context.totalTime else { return }
        let heartRateUnavailable = message["heartRateUnavailable"] as? Bool ?? false
        let receivedHeartRate = message["heartRate"] as? Int
        let fallbackHeartRate = hasFreshHeartRateSample ? context.musicContext.currentHeartRate : nil
        let heartRate = heartRateUnavailable ? nil : (receivedHeartRate ?? fallbackHeartRate)
        let targetHeartRate = message["targetHeartRate"] as? Int ?? context.musicContext.targetHeartRate

        if heartRateUnavailable,
           !isLiveMetricsWarningDismissed,
           let warning = message["metricsWarning"] as? String {
            liveMetricsWarning = warning
        }

        if let heartRate {
            rememberHeartRate(heartRate)
        }

        let segmentChanged = segmentIndex != context.currentSegmentIndex

        let updatedContext = makeWorkoutContext(
            segments: context.segments,
            currentSegmentIndex: segmentIndex,
            totalDistance: totalDistance,
            totalTime: totalTime,
            heartRate: heartRate,
            targetHeartRate: targetHeartRate
        )

        currentWorkoutContext = updatedContext

        guard isAdaptiveMixActive else { return }
        if segmentChanged {
            transitionAdaptiveMix(to: updatedContext.currentSegmentIndex)
        }
        let remaining: TimeInterval?
        if let estimate = message["estimatedSecondsRemaining"] as? Double {
            remaining = estimate
        } else if case .time = updatedContext.currentSegment.target {
            remaining = updatedContext.timeRemainingInSegment
        } else {
            remaining = nil
        }
        updateAdaptiveMixTransition(secondsRemaining: remaining)
    }

    private func updateAdaptiveMixTransition(secondsRemaining: TimeInterval?) {
        guard isAdaptiveMixActive, let context = currentWorkoutContext else { return }
        let upcomingIndex = context.currentSegmentIndex + 1
        guard upcomingIndex < context.segments.count else { return }
        if AdaptiveMixTransitionPolicy.isWithin(AdaptiveMixTransitionPolicy.preparationLeadTime, secondsRemaining: secondsRemaining),
           mixTransition.prepare(for: upcomingIndex) {
            Task {
                await requestAdaptiveMixCuration(trigger: .upcomingInterval, targetSegmentIndex: upcomingIndex)
            }
        }
        if AdaptiveMixTransitionPolicy.isWithin(AdaptiveMixTransitionPolicy.playbackLeadTime, secondsRemaining: secondsRemaining) {
            transitionAdaptiveMix(to: upcomingIndex)
        }
    }

    private func transitionAdaptiveMix(to segmentIndex: Int) {
        guard let context = currentWorkoutContext,
              context.segments.indices.contains(segmentIndex),
              mixTransition.advance(to: segmentIndex) else { return }
        musicManager.invalidatePendingAdaptiveStart()
        // Do not let a manual skip or a natural song ending consume the old
        // zone's queue while the new selection is still being prepared.
        musicManager.clearAdaptiveMixUpcoming()
        let prepared = preparedAdaptiveMix
        let sessionID = mixTransition.sessionID
        preparedAdaptiveMix = nil
        Task {
            guard sessionID == mixTransition.sessionID, isAdaptiveMixActive else { return }
            if let prepared, prepared.targetSegmentIndex == mixTransition.targetSegmentIndex {
                await applyAdaptiveMix(prepared, sessionID: sessionID)
            }
            guard sessionID == mixTransition.sessionID else { return }
            if adaptiveMixSnapshot?.targetSegmentIndex != mixTransition.targetSegmentIndex {
                await requestAdaptiveMixCuration(trigger: .segmentChanged, targetSegmentIndex: mixTransition.targetSegmentIndex)
            }
            await drainPendingAdaptiveMixCuration()
        }
    }

    // MARK: - Time-Series Recording

    private func startRecordingTimer() {
        stopRecordingTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordDataPoint()
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startLiveMetricsMonitorTimer() {
        stopLiveMetricsMonitorTimer()
        liveMetricsMonitorTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkLiveMetricsSignal()
            }
        }
    }

    private func stopLiveMetricsMonitorTimer() {
        liveMetricsMonitorTimer?.invalidate()
        liveMetricsMonitorTimer = nil
    }

    private func checkLiveMetricsSignal() {
        guard isWorkoutActive, let workoutStartTime else { return }

        // Signal dropped mid-run: stop steering music with stale samples.
        if lastHeartRateSampleAt != nil, !hasFreshHeartRateSample, !recentHeartRateSamples.isEmpty {
            recentHeartRateSamples.removeAll()
        }

        guard !isLiveMetricsWarningDismissed else { return }
        guard Date().timeIntervalSince(workoutStartTime) >= Self.liveHeartRateGracePeriod else { return }
        guard lastHeartRateSampleAt == nil else { return }

        liveMetricsWarning = "Heart rate has not arrived from your watch yet. Music is using the run plan, segment intensity, distance, pace, and song history until heart-rate data starts."
    }

    func dismissLiveMetricsWarning() {
        isLiveMetricsWarningDismissed = true
        liveMetricsWarning = nil
    }

    private func recordDataPoint() {
        guard isWorkoutActive, let context = currentWorkoutContext else { return }

        let elapsed = context.totalTime
        guard elapsed > (workoutDataPoints.last?.timestamp ?? -1) else { return }
        let distanceMeters = context.totalDistance * 1000.0 // totalDistance is in km
        let heartRate = context.musicContext.currentHeartRate

        // Calculate pace (seconds per km)
        let paceSecondsPerKm: Double? = if distanceMeters > 50, elapsed > 0 {
            elapsed / (distanceMeters / 1000.0)
        } else {
            nil
        }

        let currentSong = musicManager.currentSong

        let dataPoint = WorkoutDataPoint(
            timestamp: elapsed,
            heartRate: heartRate,
            cadence: nil, // Cadence is tracked on Watch side
            distanceMeters: distanceMeters,
            paceSecondsPerKm: paceSecondsPerKm,
            currentSongTitle: currentSong?.title,
            currentSongArtist: currentSong?.artist,
            targetHeartRate: context.musicContext.targetHeartRate
        )

        workoutDataPoints.append(dataPoint)
        persistActiveRunSnapshot()
    }

    private func trackSongChange(_ song: MusicSong?) {
        guard isWorkoutActive, let context = currentWorkoutContext else { return }

        let songID = song?.id
        guard songID != lastRecordedSongID else { return }

        let elapsed = context.totalTime

        // Close previous song period
        if !songHistory.isEmpty {
            let last = songHistory.removeLast()
            songHistory.append(SongPeriod(
                songTitle: last.songTitle,
                artist: last.artist,
                startTimestamp: last.startTimestamp,
                endTimestamp: elapsed
            ))
        }

        // Start new song period
        if let song = song {
            let songKey = song.sessionSongKey
            let isNewlyPlayedSong = !playedSongsThisSession.contains(songKey)
            playedSongsThisSession = AdaptiveMixPolicy.recordingPlayedSong(
                songKey,
                in: playedSongsThisSession
            )
            rememberPlayedSong(song)
            playedSongHistory.recordPlayedSong(song)
            aiService.registerPlayedSong(song)

            if isNewlyPlayedSong {
                print("Workout recorded played song: \(song.title) by \(song.artist)")
                logSimulatorPlayedSongIfNeeded(song)
                sendAdaptiveMixStateToWatch()
            }

            songHistory.append(SongPeriod(
                songTitle: song.title,
                artist: song.artist,
                startTimestamp: elapsed,
                endTimestamp: nil
            ))
        }

        lastRecordedSongID = songID
        persistActiveRunSnapshot()
    }

    private func rememberHeartRate(_ heartRate: Int) {
        lastHeartRateSampleAt = Date()
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false
        recentHeartRateSamples.append(heartRate)
        recentHeartRateSamples = Array(recentHeartRateSamples.suffix(Self.maximumHeartRateSamples))
    }

    private func rememberPlayedSong(_ song: MusicSong) {
        recentPlayedSongs.removeAll { $0.sessionSongKey == song.sessionSongKey }
        recentPlayedSongs.append(song)
        recentPlayedSongs = Array(recentPlayedSongs.suffix(Self.maximumRecentSongs))
    }

    private func makeWorkoutContext(
        segments: [RunSegment],
        currentSegmentIndex: Int,
        totalDistance: Double,
        totalTime: TimeInterval,
        heartRate: Int?,
        targetHeartRate: Int?
    ) -> WorkoutContext {
        let currentSegment = if segments.isEmpty {
            RunSegment()
        } else {
            segments[min(currentSegmentIndex, segments.count - 1)]
        }
        let effectiveTargetHeartRate = targetHeartRate ?? currentSegment.intensity.defaultTargetHeartRate
        let smoothedHeartRate = MusicRecommendationPolicy.smoothedHeartRate(from: recentHeartRateSamples)
        let heartRateTrend = MusicRecommendationPolicy.heartRateTrend(from: recentHeartRateSamples)
        let hasStableHeartRateSignal =
            recentHeartRateSamples.count >= 4 ||
            MusicRecommendationPolicy.hasStableHeartRateMismatch(
                targetHeartRate: effectiveTargetHeartRate,
                samples: recentHeartRateSamples
            )
        let currentSongEndingIn: TimeInterval? = if musicManager.currentSongDuration > 0 {
            max(0, musicManager.currentSongDuration - musicManager.currentPlaybackTime)
        } else {
            nil
        }

        return WorkoutContext(
            segments: segments,
            currentSegmentIndex: currentSegmentIndex,
            totalDistance: totalDistance,
            totalTime: totalTime,
            heartRate: heartRate,
            smoothedHeartRate: smoothedHeartRate,
            heartRateTrend: heartRateTrend,
            hasStableHeartRateSignal: hasStableHeartRateSignal,
            targetHeartRate: effectiveTargetHeartRate,
            currentSongEndingIn: currentSongEndingIn,
            recentSongs: recentPlayedSongs
        )
    }

    private func closeFinalSongPeriod() {
        guard let startTime = workoutStartTime, !songHistory.isEmpty else { return }

        let elapsed = currentWorkoutContext?.totalTime
            ?? activeRunState.snapshot.map { TimeInterval($0.totalTimeSeconds) }
            ?? Date().timeIntervalSince(startTime)
        let last = songHistory.removeLast()
        if last.endTimestamp == nil {
            songHistory.append(SongPeriod(
                songTitle: last.songTitle,
                artist: last.artist,
                startTimestamp: last.startTimestamp,
                endTimestamp: elapsed
            ))
        } else {
            songHistory.append(last)
        }
    }

    // MARK: - Run Event Saving

    /// Mirrors the live run to disk so a suspended or terminated app can still
    /// save a complete run event when the watch's completion message arrives.
    private func persistActiveRunSnapshot() {
        guard isWorkoutActive, let context = currentWorkoutContext else { return }

        activeRunState.update(
            currentSegmentIndex: context.currentSegmentIndex,
            totalDistanceKm: context.totalDistance,
            totalTimeSeconds: Int(context.totalTime),
            dataPoints: workoutDataPoints,
            songHistory: songHistory
        )
    }

    /// Recovers a run that was interrupted by the app being killed. The run is
    /// rehydrated into memory rather than saved immediately, so a late
    /// completion message can still supply the watch's authoritative totals.
    /// A snapshot old enough that no completion is coming is flushed to history.
    private func restoreInterruptedRunIfNeeded() {
        guard !isWorkoutActive, let snapshot = activeRunState.snapshot else { return }

        guard !activeRunState.hasSaved(runID: snapshot.id) else {
            activeRunState.clear()
            return
        }

        workoutStartTime = snapshot.startedAt
        workoutDataPoints = snapshot.dataPoints
        songHistory = snapshot.songHistory
        currentWorkoutContext = makeWorkoutContext(
            segments: snapshot.segments,
            currentSegmentIndex: snapshot.currentSegmentIndex,
            totalDistance: snapshot.totalDistanceKm,
            totalTime: TimeInterval(snapshot.totalTimeSeconds),
            heartRate: nil,
            targetHeartRate: nil
        )

        print("♻️ Recovered interrupted run from \(snapshot.startedAt): dataPoints=\(snapshot.dataPoints.count)")

        if RunEventRecoveryPolicy.isStale(snapshot) {
            print("♻️ No completion message arrived for the recovered run — saving it now")
            saveRunEvent()
            currentWorkoutContext = nil
            workoutStartTime = nil
            workoutDataPoints = []
            songHistory = []
        }
    }

    @discardableResult
    private func saveRunEvent() -> Bool {
        closeFinalSongPeriod()
        if let context = currentWorkoutContext {
            activeRunState.update(currentSegmentIndex: context.currentSegmentIndex,
                                  totalDistanceKm: context.totalDistance,
                                  totalTimeSeconds: Int(context.totalTime),
                                  dataPoints: workoutDataPoints, songHistory: songHistory)
        }
        // Prefer live context; fall back to the on-disk snapshot when the app
        // was killed mid-run and only the completion message brought us back.
        let snapshot = activeRunState.snapshot
        let runID = snapshot?.id ?? UUID()

        guard !activeRunState.hasSaved(runID: runID) else {
            print("⚠️ saveRunEvent: Run already saved, skipping duplicate")
            activeRunState.clear()
            return true
        }

        let resolution = RunEventRecoveryPolicy.resolve(
            liveSegments: currentWorkoutContext?.segments,
            liveTotalDistanceKm: currentWorkoutContext?.totalDistance,
            liveTotalTimeSeconds: currentWorkoutContext.map { Int($0.totalTime) },
            liveDataPoints: workoutDataPoints,
            liveSongHistory: songHistory,
            snapshot: snapshot
        )

        // Log for debugging
        print("📊 saveRunEvent: distance=\(resolution.totalDistanceMeters)m, time=\(resolution.totalTimeSeconds)s, dataPoints=\(resolution.dataPoints.count), recovered=\(currentWorkoutContext == nil)")

        // Save even if distance/time seem small — the Watch data is authoritative.
        // Only skip if there's truly no data at all (e.g. immediate cancel).
        guard resolution.isSavable else {
            print("⚠️ saveRunEvent: Skipping — no distance or time data")
            activeRunState.clear()
            return true
        }

        let event = RunEvent(
            id: runID,
            date: resolution.date,
            totalDistanceMeters: resolution.totalDistanceMeters,
            totalTimeSeconds: resolution.totalTimeSeconds,
            segments: resolution.segments,
            dataPoints: resolution.dataPoints,
            songHistory: resolution.songHistory
        )

        guard commitCompletedRun(event) else {
            print("Could not save run history; retaining the recovery snapshot")
            return false
        }
        activeRunState.clear()
        print("✅ saveRunEvent: Run event saved successfully")
        #if DEBUG
        if Self.isSimulatorLoggingEnabled {
            PancakeSimulatorLog("PANCAKE_SIM:SAVE_RUN_EVENT distanceMeters=\(resolution.totalDistanceMeters) totalSeconds=\(resolution.totalTimeSeconds)")
        }
        #endif
        return true
    }

    /// Return a rejection to the watch instead of acknowledging a stale action
    /// that did not change playback. The caller already runs on the main actor.
    func handleIntervalMusicControl(_ message: [String: Any]) -> String? {
        guard let runID = message["runID"] as? String,
              let segmentIndex = message["segmentIndex"] as? Int,
              isWorkoutActive,
              activeRunState.snapshot?.id.uuidString == runID,
              currentWorkoutContext?.currentSegmentIndex == segmentIndex else {
            return "This interval is no longer active on iPhone. Open Pancake on iPhone to check the run."
        }
        guard let action = message["action"] as? String,
              ["next", "suggest", "play", "pause"].contains(action) else {
            return "This music control isn't available."
        }
        handlePlaybackControl(action)
        return nil
    }

    private func loadCompletionInbox() throws -> PendingRunCompletionStore {
        if let completionInbox { return completionInbox }
        let inbox = try PendingRunCompletionStore()
        completionInbox = inbox
        return inbox
    }

    /// Routes can arrive before or after their completion message. Both deliveries
    /// use the Watch run ID and preserve the phone's detailed music history.
    func importRouteArchive(at url: URL) {
        do {
            let archive = try JSONDecoder().decode(RunRouteArchive.self, from: Data(contentsOf: url))
            if activeRunState.hasSaved(runID: archive.runID), !RunHistoryStore.shared.contains(runID: archive.runID) {
                if WatchConnectivityWrapper.shared.acknowledgeRunRoute(archive.runID) {
                    try FileManager.default.removeItem(at: url) // History was deliberately deleted.
                }
                return
            }
            handleWorkoutControlByType(WatchMessageType.workoutCompleted.rawValue, message: [
                "runID": archive.runID.uuidString,
                "startedAt": archive.startedAt.timeIntervalSince1970,
                "totalDistanceKm": Double(archive.totalDistanceMeters) / 1000,
                "totalTimeSeconds": archive.totalTimeSeconds,
                "segments": try JSONEncoder().encode(archive.segments)
            ])
            let saved = RunHistoryStore.shared.events.first { $0.id == archive.runID }
            let event = RunEvent(
                id: archive.runID, date: saved?.date ?? archive.startedAt,
                totalDistanceMeters: archive.totalDistanceMeters, totalTimeSeconds: archive.totalTimeSeconds,
                segments: saved?.segments ?? archive.segments,
                dataPoints: saved?.dataPoints ?? [], songHistory: saved?.songHistory ?? [],
                routePoints: archive.points
            )
            guard commitCompletedRun(event) else { return }
            guard WatchConnectivityWrapper.shared.acknowledgeRunRoute(archive.runID) else { return }
            try FileManager.default.removeItem(at: url)
            PancakeSimulatorLog("PANCAKE_SIM:ROUTE_SAVED points=\(archive.points.count)")
        } catch {
            print("GPS route import will retry at next launch: \(error.localizedDescription)")
        }
    }

    /// Journal completions independently of the current workout. This preserves
    /// an out-of-order completion without replacing a newer run's checkpoint.
    private func commitCompletedRun(_ event: RunEvent) -> Bool {
        do {
            try loadCompletionInbox().upsert(event)
        } catch {
            print("Could not checkpoint completed run: \(error.localizedDescription)")
        }
        guard RunHistoryStore.shared.add(event: event) else { return false }
        activeRunState.markSaved(runID: event.id)
        do {
            try completionInbox?.remove(runID: event.id)
        } catch {
            // Replaying this entry is safe because history uses the same run ID.
            print("Completed run will be reconciled at next launch: \(error.localizedDescription)")
        }
        return true
    }

    private func retryPendingRunCompletions() {
        do {
            for event in try loadCompletionInbox().events {
                _ = commitCompletedRun(event)
            }
        } catch {
            print("Could not load pending run completions; will retry on the next completion: \(error.localizedDescription)")
        }
    }

    private func logSimulatorQueueSnapshotIfNeeded(trigger: AdaptiveMixCurationTrigger) {
        guard Self.isSimulatorLoggingEnabled else { return }

        let queuedKeys = musicManager.adaptiveUpcomingSongs
            .prefix(AdaptiveMixPolicy.queueDepth)
            .map(\.sessionSongKey)
            .joined(separator: ",")

        PancakeSimulatorLog("PANCAKE_SIM:QUEUE revision=\(adaptiveMixRevision) trigger=\(trigger.rawValue) songs=\(queuedKeys) played=\(playedSongCount)")
    }

    private func logSimulatorPlayedSongIfNeeded(_ song: MusicSong) {
        guard Self.isSimulatorLoggingEnabled else { return }

        PancakeSimulatorLog("PANCAKE_SIM:PLAYED key=\(song.sessionSongKey) title=\(song.title) artist=\(song.artist)")
    }
}
