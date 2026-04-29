import Foundation
import Combine

@MainActor
final class PromptLabViewModel: ObservableObject {
    private struct DuplicateSongCheckSuggestionError: LocalizedError {
        var errorDescription: String? {
            "Song Check generated only songs it has already shown. Try changing the scenario or recent songs."
        }
    }

    private static let maxGenerationAttempts = 3

    @Published var selectedWorkoutPhase: WorkoutPhase = .midway
    @Published var selectedIntensity: Intensity = .medium
    @Published var sourceMode: PromptLabSourceMode = .allowCatalog
    @Published var currentHeartRate: Double = 150
    @Published var heartRateTrend: HeartRateTrend = .steady
    @Published var hasStableHeartRateSignal: Bool = true
    @Published var currentDistance: Double = 5.0
    @Published var currentTimeMinutes: Double = 30
    @Published var timeRemainingInSegmentMinutes: Double = 4
    @Published var currentSongEndingInSeconds: Double = 25
    @Published var isRunnerActive: Bool = true
    @Published var recentSongsInput: String = ""
    @Published var generatedSuggestion: MusicSuggestion?
    @Published var isGenerating: Bool = false
    @Published var error: Error?

    private let profileManager = UserProfileManager.shared
    private let musicManager = MusicPlaybackManager.shared
    private let aiService = MusicAIService.shared
    private let musicKitService = MusicKitService.shared

    private var cancellables = Set<AnyCancellable>()
    private var songCheckGeneratedSongs: [MusicSong] = []
    private var songCheckGeneratedSongKeys: Set<String> = []

    init() {
        setupBindings()
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
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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
            return "Apple Music catalog playback is not enabled, so this test is forcing a library-playable suggestion."
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

            for _ in 0..<Self.maxGenerationAttempts {
                let rawSuggestion = try await requestSuggestion(avoiding: songCheckGeneratedSongs)
                let suggestion = rawSuggestion.cleanedTitle()

                if rememberSongCheckSuggestion(suggestion) {
                    generatedSuggestion = suggestion
                    return
                }

                duplicateSuggestion = suggestion
            }

            if duplicateSuggestion != nil {
                self.error = DuplicateSongCheckSuggestionError()
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
    }

    func resumePlayback() {
        musicManager.play()
    }

    func setEasy5KScenario() {
        selectedWorkoutPhase = .midway
        selectedIntensity = .easy
        sourceMode = .preferLibrary
        currentHeartRate = 132
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
        selectedIntensity = .medium
        sourceMode = .allowCatalog
        currentHeartRate = 154
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
        selectedIntensity = .hard
        sourceMode = .allowCatalog
        currentHeartRate = 171
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
        selectedIntensity = .easy
        sourceMode = .libraryOnly
        currentHeartRate = 121
        heartRateTrend = .falling
        hasStableHeartRateSignal = true
        currentDistance = 4.2
        currentTimeMinutes = 28
        timeRemainingInSegmentMinutes = 3
        currentSongEndingInSeconds = 22
        isRunnerActive = true
    }

    private var elapsedTimeSeconds: TimeInterval {
        currentTimeMinutes * 60
    }

    private var effectiveMustUseLibrary: Bool {
        sourceMode.requiresLibraryOnly || (isLibraryAuthorized && !isCatalogAuthorized)
    }

    private var effectivePreferLibrarySelection: Bool {
        effectiveMustUseLibrary || sourceMode.prefersLibrary
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
                RunSegment(intensity: .easy, target: .time(seconds: 180)),
                RunSegment(intensity: selectedIntensity, target: .time(seconds: primaryDuration))
            ]
        case .recovery:
            return [
                RunSegment(intensity: .hard, target: .time(seconds: 120)),
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
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: avoidedSongs
            )
        case .midway, .finishing:
            return try await aiService.generateMusicSuggestion(
                context: promptContext,
                userPreferences: currentPreferences,
                mustUseLibrary: effectiveMustUseLibrary,
                avoidedSongs: avoidedSongs
            )
        }
    }

    private func rememberSongCheckSuggestion(_ suggestion: MusicSuggestion) -> Bool {
        guard songCheckGeneratedSongKeys.insert(suggestion.sessionSongKey).inserted else {
            return false
        }

        songCheckGeneratedSongs.append(
            MusicSong(
                id: "song-check-\(songCheckGeneratedSongs.count)",
                title: suggestion.songTitle,
                artist: suggestion.artist,
                duration: 0
            )
        )

        return true
    }

    private func parsedRecentSongs() -> [MusicSong] {
        let separators = CharacterSet(charactersIn: ",\n")
        let entries = recentSongsInput
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return entries.enumerated().map { index, entry in
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
        let delimiters = [" by ", " - ", " — "]

        for delimiter in delimiters {
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

    private func targetHeartRate(for intensity: Intensity) -> Int {
        switch intensity {
        case .easy:
            return 140
        case .medium:
            return 155
        case .hard:
            return 172
        }
    }
}
