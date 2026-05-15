import Foundation
import Combine

// MARK: - Workout Music Coordinator
@MainActor
final class WorkoutMusicCoordinator: ObservableObject {
    static let shared = WorkoutMusicCoordinator()
    
    @Published var isWorkoutActive = false
    @Published var currentWorkoutContext: WorkoutContext?
    @Published var lastMusicSuggestion: MusicSuggestion?
    @Published var liveMetricsWarning: String?

    /// Segments waiting for Watch to confirm workout started before music begins
    private var pendingRunPlanSegments: [RunSegment]?

    private let musicManager = MusicPlaybackManager.shared
    private let aiService = MusicAIService.shared
    private let profileManager = UserProfileManager.shared
    private let watchConnectivity = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()


    // Time-series recording
    private var workoutStartTime: Date?
    private var workoutDataPoints: [WorkoutDataPoint] = []
    private var songHistory: [SongPeriod] = []
    private var recordingTimer: Timer?
    private var lastRecordedSongID: String?
    private var liveMetricsMonitorTimer: Timer?
    private var lastHeartRateSampleAt: Date?
    private var isLiveMetricsWarningDismissed = false

    // Song pre-fetching
    private var prefetchedSuggestions: [MusicSuggestion] = []
    private var prefetchTimer: Timer?
    private var isPrefetching = false
    private var songEndCheckTimer: Timer?
    private var isAdvancingSong = false
    private var lastSongAdvanceAt: Date = .distantPast
    private var lastAutomaticSongAdvanceAttemptAt: Date = .distantPast

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
    private static let minimumAutomaticAdvanceInterval: TimeInterval = 10
    private static let minimumAutomaticAdvanceAttemptInterval: TimeInterval = 15
    private static let liveHeartRateGracePeriod: TimeInterval = 90

    // Fartlek detection
    private var isFartlekWorkout = false
    /// Minimum segment duration (in seconds) required to trigger a song change on segment transition.
    /// Segments shorter than this inherit the current song.
    private static let minimumSegmentDurationForSongChange: TimeInterval = 90
    
    private init() {
        setupWatchConnectivity()
        setupMusicManager()
    }
    
    // MARK: - Setup
    
    private func setupWatchConnectivity() {
        // Listen for music-related messages from WatchConnectivityManager
        NotificationCenter.default.addObserver(
            forName: .requestMusicSuggestion,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.generateNextSong()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .playbackControl,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let action = message["action"] as? String {
                Task { @MainActor in
                    self?.handlePlaybackControl(action)
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
            forName: .workoutHeartRate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let heartRate = message["heartRate"] as? Int {
                Task { @MainActor in
                    self?.handleHeartRateUpdate(heartRate)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .segmentChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let segmentIndex = message["currentSegmentIndex"] as? Int {
                Task { @MainActor in
                    self?.handleSegmentChange(segmentIndex: segmentIndex)
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
    }
    
    // MARK: - Pending Run Plan (deferred music start)

    /// Store segments from the iPhone run setup. Music will NOT start until
    /// the Watch sends a `workoutStarted` confirmation message.
    func setPendingRunPlan(_ segments: [RunSegment]) {
        pendingRunPlanSegments = segments
    }

    // MARK: - Workout Management

    func startWorkoutMusic(segments: [RunSegment]) {

        guard !isWorkoutActive else {
            return
        }

        isWorkoutActive = true
        musicManager.coordinatorDriven = true

        // Start time-series recording
        workoutStartTime = Date()
        workoutDataPoints = []
        songHistory = []
        lastRecordedSongID = nil
        lastHeartRateSampleAt = nil
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false
        startRecordingTimer()
        startLiveMetricsMonitorTimer()

        // Reset pre-fetch and session tracking
        prefetchedSuggestions.removeAll()
        isPrefetching = false
        isAdvancingSong = false
        lastSongAdvanceAt = .distantPast
        lastAutomaticSongAdvanceAttemptAt = .distantPast
        playedSongsThisSession.removeAll()
        unavailableSongsThisSession.removeAll()
        recentHeartRateSamples.removeAll()
        recentPlayedSongs.removeAll()
        lastMusicSuggestion = nil
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false
        aiService.beginVarietySession()

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

        // Start music playback immediately
        musicManager.startWorkoutMusic(workoutContext: context)

        // Generate the first song, then start pre-fetching
        Task {
            await generateStartingSong()
            startPrefetchTimer()
            startSongEndCheckTimer()
        }
    }
    
    func stopWorkoutMusic() {
        guard isWorkoutActive else { return }

        // Stop recording timer
        stopRecordingTimer()
        stopLiveMetricsMonitorTimer()

        // Stop pre-fetch timers
        stopPrefetchTimer()
        stopSongEndCheckTimer()

        // Close the final song period
        closeFinalSongPeriod()

        isWorkoutActive = false
        musicManager.coordinatorDriven = false
        currentWorkoutContext = nil
        prefetchedSuggestions.removeAll()
        isPrefetching = false
        isAdvancingSong = false
        lastSongAdvanceAt = .distantPast
        lastAutomaticSongAdvanceAttemptAt = .distantPast
        recentHeartRateSamples.removeAll()
        recentPlayedSongs.removeAll()
        playedSongsThisSession.removeAll()
        unavailableSongsThisSession.removeAll()
        lastMusicSuggestion = nil
        lastHeartRateSampleAt = nil
        liveMetricsWarning = nil
        isLiveMetricsWarningDismissed = false
        aiService.endVarietySession()

        // Stop music playback
        musicManager.stopWorkoutMusic()

        // Send workout stop to watch
        sendWorkoutStopToWatch()
    }
    
    func updateWorkoutContext(
        currentSegmentIndex: Int,
        totalDistance: Double,
        totalTime: TimeInterval,
        heartRate: Int?,
        targetHeartRate: Int?
    ) {
        guard let context = currentWorkoutContext else { return }
        
        let updatedContext = makeWorkoutContext(
            segments: context.segments,
            currentSegmentIndex: currentSegmentIndex,
            totalDistance: totalDistance,
            totalTime: totalTime,
            heartRate: heartRate,
            targetHeartRate: targetHeartRate
        )
        
        currentWorkoutContext = updatedContext
        musicManager.updateWorkoutContext(updatedContext)
        
        // Check for distance milestones (only for single segment workouts)
        checkForDistanceMilestone(previousDistance: context.totalDistance, newDistance: totalDistance)
        
        // Send updated context to watch
        sendWorkoutContextToWatch(updatedContext)
    }
    
    private func checkForDistanceMilestone(previousDistance: Double, newDistance: Double) {
        // Km milestones are now handled on the Watch side with haptic feedback
    }
    
    // MARK: - Music Suggestion Generation
    
    func generateStartingSong() async {
        guard beginSongAdvance(isAutomatic: false) else { return }
        defer { finishSongAdvance() }

        guard let context = currentWorkoutContext else { return }

        let intensity = effectiveIntensity(
            at: context.currentSegmentIndex,
            segments: context.segments
        )

        let played = await resolveAndPlaySuggestion(fallbackIntensity: intensity) {
            try await self.aiService.generateStartingSongSuggestion(
                workoutPlan: context.segments,
                userPreferences: self.profileManager.userProfile.musicPreferences,
                currentIntensity: intensity,
                isFartlek: self.isFartlekWorkout,
                mustUseLibrary: self.mustUseLibrarySuggestions
            )
        }

        if played {
            triggerPrefetch()
        }
    }
    
    func generateNextSong() async {
        guard beginSongAdvance(isAutomatic: true) else { return }
        defer { finishSongAdvance() }

        // If we have a pre-fetched suggestion, use it immediately
        if let prefetched = takePrefetchedSuggestion(),
           await playSuggestedSong(prefetched) {
            triggerPrefetch()
            return
        }

        // No pre-fetched song — generate one now
        guard let context = currentWorkoutContext else { return }

        // For fartlek workouts, compute the effective intensity using the lookahead window
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

    /// User-initiated "new song" request from the Watch button.
    /// Uses pre-fetched song if available for instant response.
    func generateNextSongUserRequested() async {
        guard beginSongAdvance(isAutomatic: false) else { return }
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

    private func startPrefetchTimer() {
        stopPrefetchTimer()
        prefetchTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.triggerPrefetch()
            }
        }
    }

    private func stopPrefetchTimer() {
        prefetchTimer?.invalidate()
        prefetchTimer = nil
    }

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

    // MARK: - Song End Detection

    private func startSongEndCheckTimer() {
        stopSongEndCheckTimer()
        // Check every 3 seconds if the song is about to end or has ended
        songEndCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSongEnd()
            }
        }
    }

    private func stopSongEndCheckTimer() {
        songEndCheckTimer?.invalidate()
        songEndCheckTimer = nil
    }

    private func checkForSongEnd() {
        guard isWorkoutActive else { return }
        guard !isAdvancingSong else { return }

        let timeRemaining = musicManager.currentSongDuration - musicManager.currentPlaybackTime
        let hasNoSong = musicManager.currentSong == nil
        let songEnding = timeRemaining > 0 && timeRemaining <= 5.0 // Within 5 seconds of ending
        let songEnded = musicManager.currentSongDuration > 0 && musicManager.currentPlaybackTime >= musicManager.currentSongDuration - 0.5
        let playbackStopped = !musicManager.isPlaying && musicManager.currentSong != nil && musicManager.currentSongDuration > 0

        if musicManager.currentSong != nil,
           musicManager.currentPlaybackTime > 0,
           musicManager.currentPlaybackTime < Self.minimumAutomaticAdvanceInterval {
            return
        }

        if hasNoSong || songEnding || songEnded || playbackStopped {
            Task {
                await generateNextSong()
            }
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

        let fallback = aiService.fallbackSuggestion(
            preferences: profileManager.userProfile.musicPreferences,
            intensity: fallbackIntensity,
            avoiding: reservedSongKeys
        ).cleanedTitle()
        aiService.registerSessionSuggestion(fallback)

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

        if let emergencySuggestion = await musicManager.playEmergencyFallback(
            preferences: profileManager.userProfile.musicPreferences,
            intensity: fallbackIntensity,
            avoiding: reservedSongKeys
        ) {
            let songKey = emergencySuggestion.sessionSongKey
            playedSongsThisSession.insert(songKey)
            if let actualSongKey = musicManager.currentSong?.sessionSongKey {
                playedSongsThisSession.insert(actualSongKey)
            }
            unavailableSongsThisSession.remove(songKey)
            aiService.registerSessionSuggestion(emergencySuggestion)
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

    private func beginSongAdvance(isAutomatic: Bool) -> Bool {
        guard isWorkoutActive || !isAutomatic else { return false }
        guard !isAdvancingSong else { return false }

        if isAutomatic {
            let now = Date()
            let secondsSinceLastAdvance = now.timeIntervalSince(lastSongAdvanceAt)
            if secondsSinceLastAdvance < Self.minimumAutomaticAdvanceInterval {
                return false
            }

            let secondsSinceLastAttempt = now.timeIntervalSince(lastAutomaticSongAdvanceAttemptAt)
            if secondsSinceLastAttempt < Self.minimumAutomaticAdvanceAttemptInterval {
                return false
            }

            lastAutomaticSongAdvanceAttemptAt = now
        }

        isAdvancingSong = true
        return true
    }

    private func finishSongAdvance() {
        isAdvancingSong = false
    }

    private var excludedSongKeys: Set<String> {
        playedSongsThisSession.union(unavailableSongsThisSession)
    }

    private var reservedSongKeys: Set<String> {
        excludedSongKeys.union(prefetchedSuggestions.map(\.sessionSongKey))
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
    
    private func sendWorkoutStartToWatch(segments: [RunSegment]) {
        // Use fallback method for workout start - critical message
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { 
            return 
        }
        
        let message: [String: Any] = [
            "type": WatchMessageType.workoutStart.rawValue,
            "segments": segments.map { segment in
                [
                    "intensity": segment.intensity.rawValue,
                    "target": [
                        "type": segment.target.isTime ? "time" : "distance",
                        "value": segment.target.isTime ? segment.target.timeSeconds : segment.target.distanceMeters
                    ]
                ]
            }
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send workout start to watch: \(error)")
        }
    }
    
    private func sendWorkoutStopToWatch() {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.workoutStop.rawValue
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send workout stop to watch: \(error)")
        }
    }
    
    private func sendWorkoutContextToWatch(_ context: WorkoutContext) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }

        var message: [String: Any] = [
            "type": WatchMessageType.workoutUpdate.rawValue,
            "currentSegmentIndex": context.currentSegmentIndex,
            "totalDistance": context.totalDistance,
            "totalTime": context.totalTime
        ]

        if let heartRate = context.musicContext.currentHeartRate {
            message["heartRate"] = heartRate
        }

        if let targetHeartRate = context.musicContext.targetHeartRate {
            message["targetHeartRate"] = targetHeartRate
        }
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send workout context to watch: \(error)")
        }
    }
    
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
    
    private func sendMusicSuggestionToWatch(_ suggestion: MusicSuggestion) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.musicSuggestion.rawValue,
            "suggestion": [
                "songTitle": suggestion.songTitle,
                "artist": suggestion.artist,
                "reason": suggestion.reason,
                "mood": suggestion.mood.rawValue,
                "confidence": suggestion.confidence
            ]
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send music suggestion to watch: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func handlePlaybackControl(_ action: String) {
        switch action {
        case "play":
            musicManager.play()
        case "stop":
            musicManager.stop()
        case "suggest":
            Task {
                await generateNextSongUserRequested()
            }
        default:
            break
        }
    }
    
    private func handleWorkoutControl(_ action: String) {
        switch action {
        case "end":
            stopWorkoutMusic()
        case "pause":
            break
        default:
            break
        }
    }

    /// Handles workout control messages keyed by "type" (sent by the Watch).
    /// The Watch sends messages like {"type": "workoutStarted"} and {"type": "workoutCompleted"}.
    private func handleWorkoutControlByType(_ type: String, message: [String: Any]) {
        switch type {
        case WatchMessageType.workoutStarted.rawValue, WatchMessageType.workoutStart.rawValue:
            if let segments = pendingRunPlanSegments {
                pendingRunPlanSegments = nil
                startWorkoutMusic(segments: segments)
            } else if let segments = decodeSegmentsFromWatchMessage(message) {
                startWorkoutMusic(segments: segments)
            } else {
                // Watch started a workout without iPhone sending a plan first.
                // Start music with a default single Zone 2 segment so the user still gets music.
                let defaultSegments = [RunSegment(intensity: .zone2, target: .time(seconds: 1800))]
                startWorkoutMusic(segments: defaultSegments)
            }

        case WatchMessageType.workoutCompleted.rawValue:
            pendingRunPlanSegments = nil

            // Update context with final data from the Watch (distance, time)
            // before saving, since periodic updates may have been slightly behind.
            if let context = currentWorkoutContext {
                let finalDistanceKm = message["totalDistanceKm"] as? Double ?? context.totalDistance
                let finalTimeSeconds = message["totalTimeSeconds"] as? Int ?? Int(context.totalTime)

                let finalContext = makeWorkoutContext(
                    segments: context.segments,
                    currentSegmentIndex: context.currentSegmentIndex,
                    totalDistance: finalDistanceKm,
                    totalTime: TimeInterval(finalTimeSeconds),
                    heartRate: context.musicContext.currentHeartRate,
                    targetHeartRate: context.musicContext.targetHeartRate
                )
                currentWorkoutContext = finalContext
            }

            saveRunEvent()
            stopWorkoutMusic()

        default:
            break
        }
    }

    private func decodeSegmentsFromWatchMessage(_ message: [String: Any]) -> [RunSegment]? {
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
    
    private func handleHeartRateUpdate(_ heartRate: Int) {
        guard let context = currentWorkoutContext else { return }
        rememberHeartRate(heartRate)
        
        updateWorkoutContext(
            currentSegmentIndex: context.currentSegmentIndex,
            totalDistance: context.totalDistance,
            totalTime: context.totalTime,
            heartRate: heartRate,
            targetHeartRate: context.musicContext.targetHeartRate
        )
    }
    
    private func handleWorkoutUpdate(_ message: [String: Any]) {
        guard isWorkoutActive, let context = currentWorkoutContext else { return }

        let segmentIndex = message["currentSegmentIndex"] as? Int ?? context.currentSegmentIndex
        let totalDistance = message["totalDistance"] as? Double ?? context.totalDistance
        let totalTime = message["totalTime"] as? Double ?? context.totalTime
        let heartRateUnavailable = message["heartRateUnavailable"] as? Bool ?? false
        let receivedHeartRate = message["heartRate"] as? Int
        let heartRate = heartRateUnavailable ? nil : (receivedHeartRate ?? context.musicContext.currentHeartRate)
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
        musicManager.updateWorkoutContext(updatedContext)

        if segmentChanged {
            handleSegmentChange(segmentIndex: segmentIndex)
        }
    }

    private func handleSegmentChange(segmentIndex: Int) {

        guard let context = currentWorkoutContext else {
            return
        }

        // Update the workout context with the new segment index
        let updatedContext = makeWorkoutContext(
            segments: context.segments,
            currentSegmentIndex: segmentIndex,
            totalDistance: context.totalDistance,
            totalTime: context.totalTime,
            heartRate: context.musicContext.currentHeartRate,
            targetHeartRate: context.musicContext.targetHeartRate
        )

        currentWorkoutContext = updatedContext
        musicManager.updateWorkoutContext(updatedContext)

        // For fartlek workouts, skip song changes on short segments.
        // The current song continues and we rely on the lookahead intensity
        // to keep the overall energy appropriate.
        if isFartlekWorkout {
            let newSegment = context.segments[min(segmentIndex, context.segments.count - 1)]
            let newSegmentDuration = segmentDurationSeconds(newSegment)

            if newSegmentDuration < Self.minimumSegmentDurationForSongChange {
                // Short segment — don't change the song. The existing song's energy
                // was chosen using the lookahead window and already accounts for this segment.
                return
            }
        }

        // Generate a new song suggestion for the new segment
        Task {
            await generateNextSong()
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
        guard !isLiveMetricsWarningDismissed else { return }
        guard Date().timeIntervalSince(workoutStartTime) >= Self.liveHeartRateGracePeriod else { return }
        guard lastHeartRateSampleAt == nil else { return }

        liveMetricsWarning = "Heart rate has not arrived from Apple Watch yet. Music is using the run plan, segment intensity, distance, pace, and song history until heart-rate data starts."
    }

    func dismissLiveMetricsWarning() {
        isLiveMetricsWarningDismissed = true
        liveMetricsWarning = nil
    }

    private func recordDataPoint() {
        guard let startTime = workoutStartTime,
              let context = currentWorkoutContext else { return }

        let elapsed = Date().timeIntervalSince(startTime)
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
            currentSongArtist: currentSong?.artist
        )

        workoutDataPoints.append(dataPoint)
    }

    private func trackSongChange(_ song: MusicSong?) {
        guard isWorkoutActive, let startTime = workoutStartTime else { return }

        let songID = song?.id
        guard songID != lastRecordedSongID else { return }

        let elapsed = Date().timeIntervalSince(startTime)

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
            playedSongsThisSession.insert(song.sessionSongKey)
            rememberPlayedSong(song)
            lastSongAdvanceAt = Date()
            songHistory.append(SongPeriod(
                songTitle: song.title,
                artist: song.artist,
                startTimestamp: elapsed,
                endTimestamp: nil
            ))
        }

        lastRecordedSongID = songID
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

        let elapsed = Date().timeIntervalSince(startTime)
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

    private func saveRunEvent() {
        guard let context = currentWorkoutContext else {
            print("⚠️ saveRunEvent: No workout context available")
            return
        }

        let totalDistanceMeters = Int(context.totalDistance * 1000.0)
        let totalTimeSeconds = Int(context.totalTime)

        // Log for debugging
        print("📊 saveRunEvent: distance=\(totalDistanceMeters)m, time=\(totalTimeSeconds)s, dataPoints=\(workoutDataPoints.count)")

        // Save even if distance/time seem small — the Watch data is authoritative.
        // Only skip if there's truly no data at all (e.g. immediate cancel).
        guard totalTimeSeconds > 0 || totalDistanceMeters > 0 else {
            print("⚠️ saveRunEvent: Skipping — no distance or time data")
            return
        }

        let event = RunEvent(
            totalDistanceMeters: totalDistanceMeters,
            totalTimeSeconds: totalTimeSeconds,
            segments: context.segments,
            dataPoints: workoutDataPoints,
            songHistory: songHistory
        )

        RunHistoryStore.shared.add(event: event)
        print("✅ saveRunEvent: Run event saved successfully")
    }
}
