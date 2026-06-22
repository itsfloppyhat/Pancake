import Foundation
import Combine

@MainActor
final class PromptLabViewModel: ObservableObject {
    private struct DuplicateSongCheckSuggestionError: LocalizedError {
        var errorDescription: String? {
            "Song Check generated only songs it has already shown. Try changing the scenario or recent songs."
        }
    }

    private struct UnverifiedSongCheckSuggestionError: LocalizedError {
        var errorDescription: String? {
            "Song Check could not verify a generated song in Apple Music. It rejected the unverified pick and retried."
        }
    }

    private struct ActiveWorkoutSongCheckError: LocalizedError {
        var errorDescription: String? {
            "Finish the active workout before starting Song Check."
        }
    }

    private static let maxGenerationAttempts = 10
    private static let songArtistDelimiters = [" by ", " - ", " — "]

    @Published var selectedWorkoutPhase: WorkoutPhase = .midway
    @Published var selectedIntensity: Intensity = .zone3
    @Published var sourceMode: PromptLabSourceMode = .allowCatalog
    @Published var currentHeartRate: Double = 143
    @Published var heartRateTrend: HeartRateTrend = .steady
    @Published var hasStableHeartRateSignal: Bool = true
    @Published var currentDistance: Double = 5.0
    @Published var currentTimeMinutes: Double = 30
    @Published var timeRemainingInSegmentMinutes: Double = 4
    @Published var currentSongEndingInSeconds: Double = 25
    @Published var isRunnerActive: Bool = true
    @Published var recentSongsInput: String = ""
    @Published var favoriteArtistsInput: String = ""
    @Published var favoriteSongsInput: String = ""
    @Published var favoriteGenresInput: String = ""
    @Published var generatedSuggestion: MusicSuggestion?
    @Published var isGenerating: Bool = false
    @Published var error: Error?
    @Published private(set) var isAdaptiveMixPreviewActive = false
    @Published private(set) var adaptiveMixPreviewQueue: [MusicSong] = []
    @Published private(set) var adaptiveMixPreviewStatus = "Ready to generate a verified Apple Music mix"
    @Published private(set) var adaptiveMixPreviewRevision = 0
    @Published private(set) var adaptiveMixPreviewSecondsUntilRefresh = Int(AdaptiveMixPolicy.refreshInterval)
    @Published private(set) var adaptiveMixPreviewGoalScore: AdaptiveMixGoalScore?
    @Published private(set) var adaptiveMixPreviewRejectedSongCount = 0

    private let profileManager = UserProfileManager.shared
    private let musicManager = MusicPlaybackManager.shared
    private let aiService = MusicAIService.shared
    private let musicKitService = MusicKitService.shared
    private let workoutCoordinator = WorkoutMusicCoordinator.shared

    private var cancellables = Set<AnyCancellable>()
    private var songCheckGeneratedSongs: [MusicSong] = []
    private var songCheckGeneratedSongKeys: Set<String> = []
    private var adaptiveMixPreviewPlayedSongs: [MusicSong] = []
    private var adaptiveMixPreviewPlayedSongKeys = Set<String>()
    private var adaptiveMixPreviewRefreshTimer: Timer?
    private var hasPendingAdaptiveMixPreviewRefresh = false

    init() {
        setupBindings()
        setupAdaptiveMixMetricBindings()
        syncTasteInputsFromProfile()
    }

    private func setupBindings() {
        profileManager.$lastError
            .compactMap { $0 }
            .sink { [weak self] in self?.error = $0 }
            .store(in: &cancellables)

        musicManager.$playbackError
            .compactMap { $0 }
            .sink { [weak self] in self?.error = $0 }
            .store(in: &cancellables)

        aiService.$lastError
            .compactMap { $0 }
            .sink { [weak self] in self?.error = $0 }
            .store(in: &cancellables)

        profileManager.$userProfile
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicKitService.$isAuthorized
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicManager.$isPlaying
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicManager.$currentSong
            .sink { [weak self] song in
                self?.recordAdaptiveMixPreviewPlayedSong(song)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicManager.$adaptiveUpcomingSongs
            .sink { [weak self] songs in
                guard let self, self.isAdaptiveMixPreviewActive else {
                    return
                }

                self.adaptiveMixPreviewQueue = Array(songs.prefix(AdaptiveMixPolicy.queueDepth))
                if songs.count < AdaptiveMixPolicy.queueDepth, !self.isGenerating {
                    Task { @MainActor [weak self] in
                        await self?.refreshAdaptiveMixPreview(reason: "queue advanced")
                    }
                }
            }
            .store(in: &cancellables)

        musicManager.$isAdaptivePlaybackActive
            .dropFirst()
            .sink { [weak self] isActive in
                guard let self, self.isAdaptiveMixPreviewActive, !isActive else {
                    return
                }

                self.resetAdaptiveMixPreviewState()
            }
            .store(in: &cancellables)
    }

    private func setupAdaptiveMixMetricBindings() {
        let metricChanges: [AnyPublisher<Void, Never>] = [
            $selectedWorkoutPhase.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $selectedIntensity.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $currentHeartRate.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $heartRateTrend.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $hasStableHeartRateSignal.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $currentDistance.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $currentTimeMinutes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $timeRemainingInSegmentMinutes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $currentSongEndingInSeconds.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $isRunnerActive.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(metricChanges)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isAdaptiveMixPreviewActive else {
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.refreshAdaptiveMixPreview(reason: "metrics changed")
                }
            }
            .store(in: &cancellables)
    }

    var isLibraryAuthorized: Bool {
        profileManager.isMusicAuthorized
    }

    var isCatalogAuthorized: Bool {
        musicKitService.isAuthorized
    }

    var isAIConfigured: Bool {
        aiService.isConfigured
    }

    var playbackStateDescription: String {
        musicManager.playbackStateDescription
    }

    var isPlaying: Bool {
        musicManager.isPlaying
    }

    var currentSong: MusicSong? {
        musicManager.currentSong
    }

    var adaptiveMixPreviewProgress: Double {
        Double(adaptiveMixPreviewSecondsUntilRefresh) / AdaptiveMixPolicy.refreshInterval
    }

    var adaptiveMixPreviewDetail: String {
        guard let score = adaptiveMixPreviewGoalScore else {
            return adaptiveMixPreviewStatus
        }

        return "\(score.targetIntensity.label) | \(score.alignmentScore)% match | \(adaptiveMixPreviewRejectedSongCount) replaced"
    }

    var currentPreferences: MusicPreferences {
        profileManager.userProfile.musicPreferences
    }

    var currentTasteSummary: String {
        MusicTasteProfileBuilder.build(from: currentPreferences).conciseSummary
    }

    var currentTargetHeartRate: Int {
        targetHeartRate(for: selectedIntensity)
    }

    var effectiveSourceModeDescription: String {
        if sourceMode.requiresLibraryOnly && !isLibraryAuthorized {
            return "Library-only mode needs library access before Pancake can honor it."
        }

        if effectiveMustUseLibrary, !sourceMode.requiresLibraryOnly {
            return "Apple Music catalog playback is not enabled, so Pancake will choose a song saved in your library."
        }

        return sourceMode.detail
    }

    var promptPreview: MusicPromptPreview {
        switch selectedWorkoutPhase {
        case .starting:
            return aiService.previewStartingSongPrompt(
                workoutPlan: promptWorkoutPlan,
                userPreferences: currentPreferences,
                currentIntensity: selectedIntensity,
                preferLibrarySelection: effectivePreferLibrarySelection,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: songCheckGeneratedSongs
            )
        case .interval, .recovery:
            return aiService.previewIntervalChangePrompt(
                context: promptContext,
                userPreferences: currentPreferences,
                currentDistance: currentDistance,
                currentTime: elapsedTimeSeconds,
                upcomingIntensity: selectedIntensity,
                preferLibrarySelection: effectivePreferLibrarySelection,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: songCheckGeneratedSongs
            )
        case .midway, .finishing:
            return aiService.previewMusicSuggestionPrompt(
                context: promptContext,
                userPreferences: currentPreferences,
                preferLibrarySelection: effectivePreferLibrarySelection,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: songCheckGeneratedSongs
            )
        }
    }

    func requestLibraryAuthorization() {
        profileManager.requestMusicAuthorization()
    }

    func requestCatalogAuthorization() async {
        await profileManager.requestCatalogAuthorization()
    }

    func refreshAuthorizationState() {
        profileManager.refreshMusicAuthorizationStates()
    }

    func clearError() {
        error = nil
    }

    func saveTasteInputs() {
        var preferences = currentPreferences
        preferences.favoriteArtists = parsedFavoriteArtists()
        preferences.favoriteSongs = parsedFavoriteSongs()
        preferences.favoriteGenres = parsedFavoriteGenres()
        profileManager.updateMusicPreferences(preferences)
        syncTasteInputsFromProfile()
    }

    func resetTasteInputsFromProfile() {
        syncTasteInputsFromProfile()
    }

    func generateSuggestion() async {
        guard isAIConfigured else {
            error = MusicAIError.aiUnavailable(.unknown)
            return
        }

        guard !sourceMode.requiresLibraryOnly || isLibraryAuthorized else {
            error = MusicError.libraryAccessDenied
            return
        }

        isGenerating = true
        error = nil
        generatedSuggestion = nil

        defer { isGenerating = false }

        do {
            var duplicateSuggestion: MusicSuggestion?
            var rejectedUnverifiedSuggestion: MusicSuggestion?
            var avoidedDuringAttempt = songCheckGeneratedSongs

            for _ in 0..<Self.maxGenerationAttempts {
                let rawSuggestion = try await requestSuggestion(avoiding: avoidedDuringAttempt)
                let suggestedSong = rawSuggestion.cleanedTitle()
                let suggestion: MusicSuggestion

                if shouldValidateCatalogSuggestion {
                    do {
                        suggestion = try await musicManager.validateAppleMusicSuggestion(suggestedSong)
                    } catch {
                        rejectedUnverifiedSuggestion = suggestedSong
                        avoidedDuringAttempt.append(songFromSuggestion(suggestedSong, idPrefix: "song-check-rejected"))
                        continue
                    }
                } else {
                    suggestion = suggestedSong
                }

                if rememberSongCheckSuggestion(suggestion) {
                    generatedSuggestion = suggestion
                    return
                }

                duplicateSuggestion = suggestion
                avoidedDuringAttempt.append(songFromSuggestion(suggestion, idPrefix: "song-check-duplicate"))
            }

            if duplicateSuggestion != nil {
                self.error = DuplicateSongCheckSuggestionError()
            } else if rejectedUnverifiedSuggestion != nil {
                self.error = UnverifiedSongCheckSuggestionError()
            }
        } catch {
            self.error = error
        }
    }

    func generateAndPlaySuggestion() async {
        await generateSuggestion()
        guard generatedSuggestion != nil else {
            return
        }

        await playGeneratedSuggestion()
    }

    func playGeneratedSuggestion() async {
        guard let generatedSuggestion else {
            return
        }

        guard !sourceMode.requiresLibraryOnly || isLibraryAuthorized else {
            error = MusicError.libraryAccessDenied
            return
        }

        let played = await musicManager.playSuggestedSong(generatedSuggestion)
        if !played, error == nil {
            error = MusicError.playbackFailed
        }
    }

    func playGeneratedSuggestionViaAppleMusic() async {
        guard let generatedSuggestion else {
            return
        }

        guard isCatalogAuthorized else {
            error = MusicError.catalogAccessRequired
            return
        }

        let played = await musicManager.playAppleMusicSuggestion(generatedSuggestion)
        if !played, error == nil {
            error = MusicError.playbackFailed
        }
    }

    func stopPlayback() {
        musicManager.stop()
        resetAdaptiveMixPreviewState()
    }

    func resumePlayback() {
        musicManager.play()
    }

    func pausePlayback() {
        musicManager.pause()
    }

    func endSongCheck() {
        if isAdaptiveMixPreviewActive {
            musicManager.stop()
        }

        resetAdaptiveMixPreviewState()
    }

    func startAdaptiveMixPreview() async {
        guard !workoutCoordinator.isWorkoutActive else {
            error = ActiveWorkoutSongCheckError()
            return
        }

        guard isCatalogAuthorized else {
            error = MusicError.catalogAccessRequired
            return
        }

        if isAdaptiveMixPreviewActive {
            await refreshAdaptiveMixPreview(reason: "manual refresh")
            return
        }

        adaptiveMixPreviewPlayedSongs.removeAll()
        adaptiveMixPreviewPlayedSongKeys.removeAll()
        adaptiveMixPreviewRevision = 0
        await curateAdaptiveMixPreview(shouldStartPlayback: true, reason: "preview started")
    }

    func skipAdaptiveMixPreviewToNext() async {
        guard isAdaptiveMixPreviewActive else {
            return
        }

        await musicManager.skipAdaptiveMixToNext()
    }

    func setEasy5KScenario() {
        selectedWorkoutPhase = .midway
        selectedIntensity = .zone2
        sourceMode = .preferLibrary
        currentHeartRate = Double(targetHeartRate(for: .zone2))
        heartRateTrend = .steady
        hasStableHeartRateSignal = true
        currentDistance = 3.0
        currentTimeMinutes = 25
        timeRemainingInSegmentMinutes = 8
        currentSongEndingInSeconds = 24
        isRunnerActive = true
    }

    func setTempoScenario() {
        selectedWorkoutPhase = .midway
        selectedIntensity = .zone3
        sourceMode = .allowCatalog
        currentHeartRate = Double(targetHeartRate(for: .zone3) + 4)
        heartRateTrend = .rising
        hasStableHeartRateSignal = true
        currentDistance = 6.5
        currentTimeMinutes = 34
        timeRemainingInSegmentMinutes = 6
        currentSongEndingInSeconds = 18
        isRunnerActive = true
    }

    func setIntervalScenario() {
        selectedWorkoutPhase = .interval
        selectedIntensity = .zone4
        sourceMode = .allowCatalog
        currentHeartRate = Double(targetHeartRate(for: .zone4))
        heartRateTrend = .rising
        hasStableHeartRateSignal = true
        currentDistance = 1.4
        currentTimeMinutes = 7
        timeRemainingInSegmentMinutes = 2
        currentSongEndingInSeconds = 12
        isRunnerActive = true
    }

    func setRecoveryScenario() {
        selectedWorkoutPhase = .recovery
        selectedIntensity = .zone1
        sourceMode = .preferLibrary
        currentHeartRate = Double(targetHeartRate(for: .zone1))
        heartRateTrend = .falling
        hasStableHeartRateSignal = true
        currentDistance = 4.2
        currentTimeMinutes = 28
        timeRemainingInSegmentMinutes = 3
        currentSongEndingInSeconds = 22
        isRunnerActive = true
    }

    func setZone5Scenario() {
        selectedWorkoutPhase = .interval
        selectedIntensity = .zone5
        sourceMode = .allowCatalog
        currentHeartRate = Double(targetHeartRate(for: .zone5) - 2)
        heartRateTrend = .rising
        hasStableHeartRateSignal = true
        currentDistance = 0.8
        currentTimeMinutes = 4
        timeRemainingInSegmentMinutes = 1
        currentSongEndingInSeconds = 10
        isRunnerActive = true
    }

    private var elapsedTimeSeconds: TimeInterval {
        currentTimeMinutes * 60
    }

    private func refreshAdaptiveMixPreview(reason: String) async {
        guard isAdaptiveMixPreviewActive else {
            return
        }

        await curateAdaptiveMixPreview(shouldStartPlayback: false, reason: reason)
    }

    private func curateAdaptiveMixPreview(shouldStartPlayback: Bool, reason: String) async {
        guard !isGenerating else {
            hasPendingAdaptiveMixPreviewRefresh = true
            return
        }

        isGenerating = true
        error = nil
        adaptiveMixPreviewStatus = "Curating from simulated run metrics"

        defer {
            isGenerating = false

            if hasPendingAdaptiveMixPreviewRefresh, isAdaptiveMixPreviewActive {
                hasPendingAdaptiveMixPreviewRefresh = false
                Task { @MainActor [weak self] in
                    await self?.refreshAdaptiveMixPreview(reason: "pending metrics refresh")
                }
            }
        }

        let goalScore = AdaptiveMixPolicy.goalScore(
            targetIntensity: selectedIntensity,
            targetHeartRate: currentTargetHeartRate,
            effectiveHeartRate: Int(currentHeartRate.rounded())
        )
        adaptiveMixPreviewGoalScore = goalScore

        let hardAvoidedSongs = parsedRecentSongs() + adaptiveMixPreviewPlayedSongs
        let promptAvoidedSongs = shouldStartPlayback
            ? hardAvoidedSongs
            : hardAvoidedSongs + adaptiveMixPreviewQueue

        var candidates: [MusicSuggestion] = []
        if isAIConfigured {
            do {
                candidates = try await aiService.generateAdaptiveMixSuggestions(
                    context: promptContext,
                    userPreferences: currentPreferences,
                    goalScore: goalScore,
                    avoidedSongs: promptAvoidedSongs
                )
            } catch {
                print("Song Check Adaptive Mix generation fell back: \(error)")
            }
        }

        candidates.append(contentsOf: adaptiveMixPreviewFallbackSuggestions(for: goalScore))
        let avoidedSongKeys = Set(hardAvoidedSongs.map(\.sessionSongKey))
        candidates = uniqueAdaptiveMixPreviewSuggestions(candidates, excluding: avoidedSongKeys)

        let requiredSongCount = shouldStartPlayback
            ? AdaptiveMixPolicy.queueDepth + 1
            : AdaptiveMixPolicy.queueDepth
        let resolutionReport = await musicManager.resolveAdaptiveMixSuggestions(
            candidates,
            excluding: avoidedSongKeys,
            limit: requiredSongCount
        )

        guard resolutionReport.hasVerifiedSongCount(requiredSongCount) else {
            adaptiveMixPreviewStatus = "Keeping current mix: \(resolutionReport.items.count)/\(requiredSongCount) Apple Music songs verified"
            adaptiveMixPreviewRejectedSongCount = resolutionReport.rejectedSuggestionCount
            if isAdaptiveMixPreviewActive {
                restartAdaptiveMixPreviewRefreshTimer()
            }
            return
        }

        let didApplyQueue: Bool
        if shouldStartPlayback {
            didApplyQueue = await musicManager.startAdaptiveMix(with: resolutionReport.items)
        } else {
            didApplyQueue = musicManager.replaceAdaptiveMixUpcoming(
                with: Array(resolutionReport.items.prefix(AdaptiveMixPolicy.queueDepth))
            )
        }

        guard didApplyQueue else {
            adaptiveMixPreviewStatus = shouldStartPlayback
                ? "Unable to start Apple Music playback"
                : "Unable to replace the upcoming mix"
            return
        }

        isAdaptiveMixPreviewActive = true
        adaptiveMixPreviewRevision += 1
        adaptiveMixPreviewRejectedSongCount = resolutionReport.rejectedSuggestionCount
        adaptiveMixPreviewQueue = Array(musicManager.adaptiveUpcomingSongs.prefix(AdaptiveMixPolicy.queueDepth))
        adaptiveMixPreviewStatus = "Mix \(adaptiveMixPreviewRevision) | \(reason)"
        recordAdaptiveMixPreviewPlayedSong(musicManager.currentSong)
        restartAdaptiveMixPreviewRefreshTimer()
    }

    private func adaptiveMixPreviewFallbackSuggestions(for goalScore: AdaptiveMixGoalScore) -> [MusicSuggestion] {
        let preferredIntensities: [Intensity]

        switch goalScore.guidance {
        case .easeDown:
            preferredIntensities = Intensity.allCases
        case .lift:
            preferredIntensities = Array(Intensity.allCases.reversed())
        case .maintain, .followPlan:
            preferredIntensities = [goalScore.targetIntensity] + Intensity.allCases
        }

        return preferredIntensities
            .flatMap(MusicAIService.fallbackSuggestions(for:))
    }

    private func uniqueAdaptiveMixPreviewSuggestions(
        _ suggestions: [MusicSuggestion],
        excluding excludedSongKeys: Set<String>
    ) -> [MusicSuggestion] {
        var seenSongKeys = Set<String>()

        return suggestions
            .map { $0.cleanedTitle() }
            .filter { suggestion in
                AdaptiveMixPolicy.canQueue(
                    songKey: suggestion.sessionSongKey,
                    playedSongKeys: excludedSongKeys,
                    temporarilyReservedSongKeys: seenSongKeys
                ) &&
                    seenSongKeys.insert(suggestion.sessionSongKey).inserted
            }
    }

    private func recordAdaptiveMixPreviewPlayedSong(_ song: MusicSong?) {
        guard isAdaptiveMixPreviewActive, let song else {
            return
        }

        guard adaptiveMixPreviewPlayedSongKeys.insert(song.sessionSongKey).inserted else {
            return
        }

        adaptiveMixPreviewPlayedSongs.append(song)
    }

    private func restartAdaptiveMixPreviewRefreshTimer() {
        adaptiveMixPreviewSecondsUntilRefresh = Int(AdaptiveMixPolicy.refreshInterval)

        guard adaptiveMixPreviewRefreshTimer == nil else {
            return
        }

        adaptiveMixPreviewRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickAdaptiveMixPreviewRefreshTimer()
            }
        }
    }

    private func tickAdaptiveMixPreviewRefreshTimer() {
        guard isAdaptiveMixPreviewActive else {
            stopAdaptiveMixPreviewRefreshTimer()
            return
        }

        guard adaptiveMixPreviewSecondsUntilRefresh > 0 else {
            return
        }

        guard adaptiveMixPreviewSecondsUntilRefresh > 1 else {
            adaptiveMixPreviewSecondsUntilRefresh = 0
            Task { @MainActor [weak self] in
                await self?.refreshAdaptiveMixPreview(reason: "30-second metrics refresh")
            }
            return
        }

        adaptiveMixPreviewSecondsUntilRefresh -= 1
    }

    private func stopAdaptiveMixPreviewRefreshTimer() {
        adaptiveMixPreviewRefreshTimer?.invalidate()
        adaptiveMixPreviewRefreshTimer = nil
    }

    private func resetAdaptiveMixPreviewState() {
        isAdaptiveMixPreviewActive = false
        adaptiveMixPreviewQueue = []
        adaptiveMixPreviewStatus = "Ready to generate a verified Apple Music mix"
        adaptiveMixPreviewGoalScore = nil
        adaptiveMixPreviewRejectedSongCount = 0
        adaptiveMixPreviewSecondsUntilRefresh = Int(AdaptiveMixPolicy.refreshInterval)
        hasPendingAdaptiveMixPreviewRefresh = false
        stopAdaptiveMixPreviewRefreshTimer()
    }

    private var effectiveMustUseLibrary: Bool {
        sourceMode.requiresLibraryOnly || (isLibraryAuthorized && !isCatalogAuthorized)
    }

    private var effectivePreferLibrarySelection: Bool {
        effectiveMustUseLibrary || sourceMode.prefersLibrary
    }

    private var shouldValidateCatalogSuggestion: Bool {
        !effectiveMustUseLibrary
    }

    private var promptWorkoutPlan: [RunSegment] {
        let primaryDuration = max(Int(timeRemainingInSegmentMinutes * 60), 60)

        switch selectedWorkoutPhase {
        case .starting:
            return [
                RunSegment(intensity: selectedIntensity, target: .time(seconds: max(primaryDuration * 3, 600)))
            ]
        case .interval:
            return [
                RunSegment(intensity: .zone2, target: .time(seconds: 180)),
                RunSegment(intensity: selectedIntensity, target: .time(seconds: primaryDuration))
            ]
        case .recovery:
            return [
                RunSegment(intensity: .zone4, target: .time(seconds: 120)),
                RunSegment(intensity: selectedIntensity, target: .time(seconds: primaryDuration))
            ]
        case .midway, .finishing:
            return [
                RunSegment(intensity: selectedIntensity, target: .time(seconds: max(primaryDuration, 300)))
            ]
        }
    }

    private var promptContext: MusicContext {
        let pace = currentTimeMinutes > 0.1 ? (currentDistance * 60) / currentTimeMinutes : nil
        let recentSongs = parsedRecentSongs() + songCheckGeneratedSongs

        return MusicContext(
            currentHeartRate: Int(currentHeartRate.rounded()),
            guidanceHeartRate: Int(currentHeartRate.rounded()),
            targetHeartRate: targetHeartRate(for: selectedIntensity),
            heartRateTrend: heartRateTrend,
            hasStableHeartRateSignal: hasStableHeartRateSignal,
            currentIntensity: selectedIntensity,
            timeRemainingInSegment: timeRemainingInSegmentMinutes * 60,
            currentSongEndingIn: currentSongEndingInSeconds,
            userPreferences: currentPreferences,
            recentSongs: recentSongs,
            currentDistance: currentDistance,
            currentPace: pace,
            isActive: isRunnerActive
        )
    }

    private func requestSuggestion(avoiding avoidedSongs: [MusicSong]) async throws -> MusicSuggestion {
        switch selectedWorkoutPhase {
        case .starting:
            return try await aiService.generateStartingSongSuggestion(
                workoutPlan: promptWorkoutPlan,
                userPreferences: currentPreferences,
                currentIntensity: selectedIntensity,
                preferLibrarySelection: effectivePreferLibrarySelection,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: avoidedSongs
            )
        case .interval, .recovery:
            return try await aiService.generateIntervalChangeSuggestion(
                context: promptContext,
                userPreferences: currentPreferences,
                currentDistance: currentDistance,
                currentTime: elapsedTimeSeconds,
                upcomingIntensity: selectedIntensity,
                preferLibrarySelection: effectivePreferLibrarySelection,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: avoidedSongs
            )
        case .midway, .finishing:
            return try await aiService.generateMusicSuggestion(
                context: promptContext,
                userPreferences: currentPreferences,
                preferLibrarySelection: effectivePreferLibrarySelection,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: avoidedSongs
            )
        }
    }

    private func rememberSongCheckSuggestion(_ suggestion: MusicSuggestion) -> Bool {
        guard songCheckGeneratedSongKeys.insert(suggestion.sessionSongKey).inserted else {
            return false
        }

        songCheckGeneratedSongs.append(songFromSuggestion(suggestion, idPrefix: "song-check"))

        return true
    }

    private func songFromSuggestion(_ suggestion: MusicSuggestion, idPrefix: String) -> MusicSong {
        MusicSong(
            id: "\(idPrefix)-\(songCheckGeneratedSongs.count)-\(suggestion.sessionSongKey)",
            title: suggestion.songTitle,
            artist: suggestion.artist,
            duration: 0
        )
    }

    private func parsedRecentSongs() -> [MusicSong] {
        splitSongListEntries(recentSongsInput).enumerated().map { index, entry in
            let components = splitSongAndArtist(from: entry)
            return MusicSong(
                id: "prompt-lab-\(index)",
                title: components.title,
                artist: components.artist,
                duration: 0
            )
        }
    }

    private func splitSongAndArtist(from value: String) -> (title: String, artist: String) {
        for delimiter in Self.songArtistDelimiters {
            if let range = value.range(of: delimiter, options: [.caseInsensitive]) {
                let title = value[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = value[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty, !artist.isEmpty {
                    return (title, artist)
                }
            }
        }

        return (value, "Unknown Artist")
    }

    private func syncTasteInputsFromProfile() {
        favoriteArtistsInput = currentPreferences.favoriteArtists
            .map(\.name)
            .joined(separator: ", ")

        favoriteSongsInput = currentPreferences.favoriteSongs
            .map { "\($0.title) - \($0.artist)" }
            .joined(separator: "\n")

        favoriteGenresInput = currentPreferences.favoriteGenres
            .filter(\.isSelected)
            .map(\.name)
            .joined(separator: ", ")
    }

    private func parsedFavoriteArtists() -> [MusicArtist] {
        splitListEntries(favoriteArtistsInput)
            .map { artist in
                MusicArtist(
                    id: artist.normalizedMusicIdentity,
                    name: artist,
                    artwork: nil,
                    genres: []
                )
            }
    }

    private func parsedFavoriteSongs() -> [MusicSong] {
        splitSongListEntries(favoriteSongsInput)
            .enumerated()
            .map { index, entry in
                let components = splitSongAndArtist(from: entry)
                return MusicSong(
                    id: "manual-\(index)-\(components.artist.normalizedMusicIdentity)-\(components.title.normalizedMusicIdentity)",
                    title: components.title,
                    artist: components.artist,
                    duration: 0
                )
            }
    }

    private func parsedFavoriteGenres() -> [MusicGenre] {
        splitListEntries(favoriteGenresInput)
            .map { genre in
                MusicGenre(
                    id: genre.normalizedMusicIdentity,
                    name: genre,
                    isSelected: true
                )
            }
    }

    private func splitListEntries(_ value: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n")
        return value
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitSongListEntries(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .flatMap { splitSongLineEntries($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitSongLineEntries(_ value: String) -> [String] {
        var entries: [String] = []
        var currentEntry = ""

        for rawComponent in value.components(separatedBy: ",") {
            let component = rawComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !component.isEmpty else { continue }

            if !currentEntry.isEmpty,
               containsSongArtistDelimiter(currentEntry),
               containsSongArtistDelimiter(component) {
                entries.append(currentEntry)
                currentEntry = component
            } else if currentEntry.isEmpty {
                currentEntry = component
            } else {
                currentEntry += ", \(component)"
            }
        }

        if !currentEntry.isEmpty {
            entries.append(currentEntry)
        }

        return entries
    }

    private func containsSongArtistDelimiter(_ value: String) -> Bool {
        Self.songArtistDelimiters.contains { delimiter in
            value.range(of: delimiter, options: [.caseInsensitive]) != nil
        }
    }

    private func targetHeartRate(for intensity: Intensity) -> Int {
        let personalInfo = profileManager.userProfile.personalInfo
        let maxHeartRate = personalInfo.maxHeartRate
            ?? Intensity.estimatedMaxHeartRate(age: personalInfo.age)
            ?? Intensity.defaultMaxHeartRate

        return intensity.targetHeartRate(maxHeartRate: maxHeartRate)
    }
}
