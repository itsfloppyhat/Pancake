import Foundation
import FoundationModels
import Combine

// MARK: - AI Availability

enum AIAvailabilityStatus: Equatable {
    case available
    case unavailable(reason: AIUnavailabilityReason)
}

enum AIUnavailabilityReason: Equatable {
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unknown

    var userMessage: String {
        switch self {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Go to Settings > Apple Intelligence & Siri to enable it."
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence. AI music features require a compatible iPhone or iPad."
        case .modelNotReady:
            return "The AI model is still downloading. Please try again in a few minutes."
        case .unknown:
            return "AI features are currently unavailable."
        }
    }
}

// MARK: - AI Service Errors

enum MusicAIError: LocalizedError {
    case aiUnavailable(AIUnavailabilityReason)
    case generationFailed(Error)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .aiUnavailable(let reason):
            return reason.userMessage
        case .generationFailed(let error):
            return "AI generation failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from AI model"
        case .timeout:
            return "AI request timed out. Please try again."
        }
    }
}

// MARK: - Generable Structs for Apple Foundation Models

@Generable
struct GenerableMusicSuggestion {
    @Guide(description: "The exact title of the song only, without the artist name. For example: 'Blinding Lights' not 'Blinding Lights by The Weeknd'")
    let songTitle: String

    @Guide(description: "The artist or band name only, separate from the song title")
    let artist: String

    @Guide(description: "Brief reason why this song fits the workout context (1-2 sentences)")
    let reason: String

    @Guide(.anyOf(["chill", "energetic", "intense", "motivational", "calming", "upbeat"]))
    let mood: String

    @Guide(description: "Confidence score for this suggestion", .range(0.0...1.0))
    let confidence: Double
}

@Generable
struct GenerableMotivation {
    @Guide(description: "A short motivational message under 15 words")
    let message: String
}

@Generable
struct GenerableSpeech {
    @Guide(description: "A motivational speech of 2-3 sentences, under 30 words total")
    let speech: String
}

/// Thrown when a generation request is skipped because another is already in flight.
struct ConcurrentRequestError: LocalizedError {
    var errorDescription: String? { "Another AI request is already in progress" }
}

// MARK: - Music AI Service

@MainActor
final class MusicAIService: ObservableObject {
    static let shared = MusicAIService()
    private static let generationTimeoutSeconds: TimeInterval = 12

    @Published var isGenerating = false
    @Published var lastError: Error?
    @Published var availabilityStatus: AIAvailabilityStatus = .available

    // Configuration for library selection probability
    @Published var librarySelectionProbability: Double = 0.45 // 45% chance to select from library

    // Variety tracking to prevent repetitive suggestions
    // Tracks songs only during an active workout recommendation session.
    private var recentSuggestions: [String] = []
    private var recentSuggestionKeys: Set<String> = []
    private var isVarietySessionActive = false

    /// Guards against concurrent FoundationModels requests which crash the session.
    private var isRequestInFlight = false

    private init() {
        loadLibrarySelectionProbability()
        checkAvailability()
    }

    // MARK: - Availability

    func checkAvailability() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            availabilityStatus = .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                availabilityStatus = .unavailable(reason: .appleIntelligenceNotEnabled)
            case .deviceNotEligible:
                availabilityStatus = .unavailable(reason: .deviceNotEligible)
            case .modelNotReady:
                availabilityStatus = .unavailable(reason: .modelNotReady)
            @unknown default:
                availabilityStatus = .unavailable(reason: .unknown)
            }
        }
    }

    var isAvailable: Bool {
        if case .available = availabilityStatus { return true }
        return false
    }

    /// Replaces isConfigured check from ChatGPTService
    var isConfigured: Bool {
        isAvailable
    }

    private func checkAvailabilityOrThrow() throws {
        checkAvailability()
        guard case .available = availabilityStatus else {
            if case .unavailable(let reason) = availabilityStatus {
                throw MusicAIError.aiUnavailable(reason)
            }
            throw MusicAIError.aiUnavailable(.unknown)
        }
    }

    /// Creates a fresh session for each request to avoid accumulating context
    /// that would exceed the 4096-token limit.
    private func createSession() -> LanguageModelSession {
        return LanguageModelSession()
    }

    /// Waits until any in-flight request completes before proceeding.
    /// Returns false if a request is already in flight (caller should bail out).
    private func acquireGenerationLock() -> Bool {
        guard !isRequestInFlight else {
            return false
        }
        isRequestInFlight = true
        return true
    }

    private func releaseGenerationLock() {
        isRequestInFlight = false
    }

    private func withRequestTimeout<T>(
        seconds: TimeInterval? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let timeoutSeconds = seconds ?? Self.generationTimeoutSeconds

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw MusicAIError.timeout
            }

            guard let result = try await group.next() else {
                throw MusicAIError.timeout
            }

            group.cancelAll()
            return result
        }
    }

    // MARK: - Library Selection Probability Management

    func setLibrarySelectionProbability(_ probability: Double) {
        librarySelectionProbability = max(0.0, min(1.0, probability)) // Clamp between 0 and 1
        saveLibrarySelectionProbability()
    }

    private func loadLibrarySelectionProbability() {
        librarySelectionProbability = UserDefaults.standard.double(forKey: "AI_LibrarySelectionProbability")
        if librarySelectionProbability == 0.0 {
            librarySelectionProbability = 0.45 // Default to 45%
        }
    }

    private func saveLibrarySelectionProbability() {
        UserDefaults.standard.set(librarySelectionProbability, forKey: "AI_LibrarySelectionProbability")
    }

    // MARK: - Music Suggestion Generation

    /// Get a random song from user's library based on their preferences
    func getRandomLibrarySong(
        preferences: MusicPreferences,
        intensity: Intensity
    ) async throws -> MusicSuggestion {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        let prompt = buildRandomLibrarySongPrompt(preferences: preferences, intensity: intensity)

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableMusicSuggestion.self)
            }

            let suggestion = mapToMusicSuggestion(response.content)

            return suggestion
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    func generateMusicSuggestion(
        context: MusicContext,
        userPreferences: MusicPreferences,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) async throws -> MusicSuggestion {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        // Configurable chance to select from user's library
        let shouldSelectFromLibrary = mustUseLibrary || Double.random(in: 0...1) < librarySelectionProbability

        let prompt = buildMusicSuggestionPrompt(
            context: context,
            preferences: userPreferences,
            preferLibrarySelection: shouldSelectFromLibrary,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        )

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableMusicSuggestion.self)
            }

            let suggestion = mapToMusicSuggestion(response.content)

            // Track this suggestion for variety
            trackSuggestion(suggestion)

            return suggestion
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    func generateStartingSongSuggestion(
        workoutPlan: [RunSegment],
        userPreferences: MusicPreferences,
        currentIntensity: Intensity,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) async throws -> MusicSuggestion {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        // Configurable chance to select from user's library
        let shouldSelectFromLibrary = mustUseLibrary || Double.random(in: 0...1) < librarySelectionProbability

        let prompt = buildStartingSongPrompt(
            workoutPlan: workoutPlan,
            preferences: userPreferences,
            currentIntensity: currentIntensity,
            preferLibrarySelection: shouldSelectFromLibrary,
            isFartlek: isFartlek,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        )

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableMusicSuggestion.self)
            }

            let suggestion = mapToMusicSuggestion(response.content)

            // Track this suggestion for variety
            trackSuggestion(suggestion)

            return suggestion
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    func generateIntervalChangeSuggestion(
        context: MusicContext,
        userPreferences: MusicPreferences,
        currentDistance: Double,
        currentTime: TimeInterval,
        upcomingIntensity: Intensity?,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) async throws -> MusicSuggestion {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        // Configurable chance to select from user's library
        let shouldSelectFromLibrary = mustUseLibrary || Double.random(in: 0...1) < librarySelectionProbability

        let prompt = buildIntervalChangePrompt(
            context: context,
            preferences: userPreferences,
            currentDistance: currentDistance,
            currentTime: currentTime,
            upcomingIntensity: upcomingIntensity,
            preferLibrarySelection: shouldSelectFromLibrary,
            isFartlek: isFartlek,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        )

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableMusicSuggestion.self)
            }

            let suggestion = mapToMusicSuggestion(response.content)

            // Track this suggestion for variety
            trackSuggestion(suggestion)

            return suggestion
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    func generateWorkoutMotivation(
        currentSegment: RunSegment,
        progress: Double,
        heartRate: Int?
    ) async throws -> String {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        let prompt = buildMotivationPrompt(
            segment: currentSegment,
            progress: progress,
            heartRate: heartRate
        )

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableMotivation.self)
            }

            return response.content.message.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    // MARK: - Motivational Speech Generation

    func generateMotivationalSpeech(workoutPlan: [RunSegment]) async throws -> String {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        let workoutSummary = buildWorkoutSummary(workoutPlan)
        let prompt = buildMotivationalSpeechPrompt(workoutSummary: workoutSummary)

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableSpeech.self)
            }

            return response.content.speech.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    // MARK: - Workout Motivation Generation

    func generateWorkoutMotivation(
        segmentChange: Bool,
        distanceMilestone: Bool,
        currentIntensity: Intensity,
        heartRate: Int?,
        totalDistance: Double
    ) async throws -> String {
        try checkAvailabilityOrThrow()
        guard acquireGenerationLock() else { throw MusicAIError.generationFailed(ConcurrentRequestError()) }

        isGenerating = true
        lastError = nil

        defer {
            isGenerating = false
            releaseGenerationLock()
        }

        let prompt = buildWorkoutMotivationPrompt(
            segmentChange: segmentChange,
            distanceMilestone: distanceMilestone,
            currentIntensity: currentIntensity,
            heartRate: heartRate,
            totalDistance: totalDistance
        )

        do {
            let response = try await withRequestTimeout {
                let session = self.createSession()
                return try await session.respond(to: prompt, generating: GenerableMotivation.self)
            }

            return response.content.message.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error
            throw MusicAIError.generationFailed(error)
        }
    }

    // MARK: - Variety Management

    private func trackSuggestion(_ suggestion: MusicSuggestion) {
        guard isVarietySessionActive else {
            return
        }

        // Clean the title before tracking so the avoid-list uses the real song name
        let cleaned = suggestion.cleanedTitle()
        let suggestionKey = "\(cleaned.artist) - \(cleaned.songTitle)"
        let normalizedKey = cleaned.sessionSongKey

        // Don't add duplicates — the AI already suggested this exact song
        guard recentSuggestionKeys.insert(normalizedKey).inserted else {
            return
        }

        // Track ALL songs for the session — no cap, songs should never repeat
        recentSuggestions.append(suggestionKey)
    }

    func beginVarietySession() {
        isVarietySessionActive = true
        clearVarietyTracking()
    }

    func endVarietySession() {
        isVarietySessionActive = false
        clearVarietyTracking()
    }

    /// Public method to clear workout-scoped variety tracking.
    func clearVarietyTracking() {
        recentSuggestions.removeAll()
        recentSuggestionKeys.removeAll()
    }

    func registerSessionSuggestion(_ suggestion: MusicSuggestion) {
        trackSuggestion(suggestion)
    }

    func fallbackSuggestion(
        preferences: MusicPreferences,
        intensity: Intensity,
        avoiding avoidedSongKeys: Set<String>
    ) -> MusicSuggestion {
        if let preferenceFallback = MusicRecommendationPolicy.fallbackSuggestion(
            preferences: preferences,
            intensity: intensity,
            avoiding: avoidedSongKeys
        ) {
            return preferenceFallback
        }

        return Self.fallbackSuggestion(for: intensity)
    }

    // MARK: - Mapping

    private func mapToMusicSuggestion(_ generable: GenerableMusicSuggestion) -> MusicSuggestion {
        let mood = MusicMood(rawValue: generable.mood) ?? .energetic
        return MusicSuggestion(
            songTitle: generable.songTitle,
            artist: generable.artist,
            reason: generable.reason,
            mood: mood,
            confidence: generable.confidence
        )
    }

    func previewStartingSongPrompt(
        workoutPlan: [RunSegment],
        userPreferences: MusicPreferences,
        currentIntensity: Intensity,
        preferLibrarySelection: Bool = false,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> MusicPromptPreview {
        makeStartingSongPromptPreview(
            workoutPlan: workoutPlan,
            preferences: userPreferences,
            currentIntensity: currentIntensity,
            preferLibrarySelection: preferLibrarySelection,
            isFartlek: isFartlek,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        )
    }

    func previewIntervalChangePrompt(
        context: MusicContext,
        userPreferences: MusicPreferences,
        currentDistance: Double,
        currentTime: TimeInterval,
        upcomingIntensity: Intensity?,
        preferLibrarySelection: Bool = false,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> MusicPromptPreview {
        makeIntervalChangePromptPreview(
            context: context,
            preferences: userPreferences,
            currentDistance: currentDistance,
            currentTime: currentTime,
            upcomingIntensity: upcomingIntensity,
            preferLibrarySelection: preferLibrarySelection,
            isFartlek: isFartlek,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        )
    }

    func previewMusicSuggestionPrompt(
        context: MusicContext,
        userPreferences: MusicPreferences,
        preferLibrarySelection: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> MusicPromptPreview {
        makeMusicSuggestionPromptPreview(
            context: context,
            preferences: userPreferences,
            preferLibrarySelection: preferLibrarySelection,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        )
    }

    // MARK: - Prompt Building

    private func buildStartingSongPrompt(
        workoutPlan: [RunSegment],
        preferences: MusicPreferences,
        currentIntensity: Intensity,
        preferLibrarySelection: Bool = false,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> String {
        makeStartingSongPromptPreview(
            workoutPlan: workoutPlan,
            preferences: preferences,
            currentIntensity: currentIntensity,
            preferLibrarySelection: preferLibrarySelection,
            isFartlek: isFartlek,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        ).fullPrompt
    }

    private func makeStartingSongPromptPreview(
        workoutPlan: [RunSegment],
        preferences: MusicPreferences,
        currentIntensity: Intensity,
        preferLibrarySelection: Bool = false,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> MusicPromptPreview {
        let workoutDescription = buildWorkoutPlanDescription(workoutPlan)
        let tasteProfile = MusicTasteProfileBuilder.build(from: preferences)
        let musicPreferences = tasteProfile.conciseSummary
        let effortMood = getEffortMoodMapping(currentIntensity)

        let libraryInstruction = if mustUseLibrary {
            """

            CRITICAL PLAYBACK CONSTRAINT: Suggest only a song the runner can realistically play from their local library right now. Use saved favorite songs first. If you are unsure, choose an explicit favorite song or a song by one of the runner's strongest library artists. Do not suggest catalog-only music.
            """
        } else if preferLibrarySelection {
            """

            IMPORTANT: Prefer a song that exists in my music library. Use my saved favorites first and use any imported playlist only as a taste sample, not as a playback queue.
            """
        } else {
            """

            You can suggest any song that matches my workout context, whether from my library or Apple Music catalog. Use my saved favorites and imported playlist taste sample to steer the choice, but do not treat any playlist as a required queue.
            """
        }

        // Build heart rate guidance for starting song
        let heartRateGuidance = buildStartingSongHeartRateGuidance(intensity: currentIntensity)

        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance(avoiding: avoidedSongs)

        // Build fartlek guidance
        let fartlekGuidance = buildFartlekGuidance(isFartlek: isFartlek, effectiveIntensity: currentIntensity)

        let selectionGoals = """
        - Get me pumped up and ready to run
        - Match the energy level for a \(currentIntensity.label) effort
        - Reflect my strongest taste signals: \(tasteProfile.libraryArtistPrompt) / \(tasteProfile.genrePrompt)
        - Set the perfect tone for my workout
        - Help me get into my target heart rate zone for \(currentIntensity.label) effort
        - Add variety to keep my playlist fresh and engaging
        """

        let fullPrompt = """
        You are a music curator for running workouts. I am starting an outdoor run. My plan is to \(workoutDescription). My taste profile is \(musicPreferences). Find a motivating song to get me started. With this being a \(currentIntensity.label) effort, make this a \(effortMood) song.\(heartRateGuidance)\(varietyGuidance)\(fartlekGuidance)\(libraryInstruction)

        Choose a song that will:
        \(selectionGoals)
        """

        let guidanceBody = joinedPromptSections([
            heartRateGuidance,
            varietyGuidance,
            fartlekGuidance
        ], fallback: "No special guidance beyond matching the planned starting effort.")

        return MusicPromptPreview(
            promptTitle: "Starting Song Prompt",
            sections: [
                MusicPromptSection(
                    title: "Workout Plan",
                    body: """
                    Phase: \(WorkoutPhase.starting.displayName)
                    Plan: \(workoutDescription)
                    Planned intensity: \(currentIntensity.label)
                    Desired feel: \(effortMood)
                    """
                ),
                MusicPromptSection(
                    title: "Taste Signals",
                    body: """
                    Taste profile: \(musicPreferences)
                    Strong artists: \(tasteProfile.libraryArtistPrompt)
                    Favorite genres: \(tasteProfile.genrePrompt)
                    """
                ),
                MusicPromptSection(title: "Guidance", body: guidanceBody),
                MusicPromptSection(
                    title: "Playback Constraint",
                    body: normalizedPromptSection(libraryInstruction)
                ),
                MusicPromptSection(
                    title: "Selection Goals",
                    body: selectionGoals
                )
            ],
            fullPrompt: fullPrompt
        )
    }

    private func buildIntervalChangePrompt(
        context: MusicContext,
        preferences: MusicPreferences,
        currentDistance: Double,
        currentTime: TimeInterval,
        upcomingIntensity: Intensity?,
        preferLibrarySelection: Bool = false,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> String {
        makeIntervalChangePromptPreview(
            context: context,
            preferences: preferences,
            currentDistance: currentDistance,
            currentTime: currentTime,
            upcomingIntensity: upcomingIntensity,
            preferLibrarySelection: preferLibrarySelection,
            isFartlek: isFartlek,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        ).fullPrompt
    }

    private func makeIntervalChangePromptPreview(
        context: MusicContext,
        preferences: MusicPreferences,
        currentDistance: Double,
        currentTime: TimeInterval,
        upcomingIntensity: Intensity?,
        preferLibrarySelection: Bool = false,
        isFartlek: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> MusicPromptPreview {
        let tasteProfile = MusicTasteProfileBuilder.build(from: preferences)
        let heartRateInfo = if let current = context.effectiveHeartRate, let target = context.targetHeartRate {
            "My effective heart rate is \(current) BPM (target: \(target) BPM). \(context.heartRateTrend.promptDescription)"
        } else {
            "My current heart rate is unknown. \(context.heartRateTrend.promptDescription)"
        }

        let targetIntensity = upcomingIntensity ?? context.currentIntensity

        let effortAnalysis = analyzeHeartRateVsEffort(
            currentHeartRate: context.effectiveHeartRate,
            targetHeartRate: context.targetHeartRate,
            currentIntensity: context.currentIntensity,
            upcomingIntensity: upcomingIntensity
        )

        let musicPreferences = tasteProfile.conciseSummary

        let libraryInstruction = if mustUseLibrary {
            """

            CRITICAL PLAYBACK CONSTRAINT: Suggest only a song the runner can realistically play from their local library right now. Choose from saved favorites, known preferred artists, or strong library taste signals. Do not suggest catalog-only songs.
            """
        } else if preferLibrarySelection {
            """

            IMPORTANT: Prefer a song from my local library. Use my saved favorites first and use imported playlist data only as taste guidance, not as a literal queue.
            """
        } else {
            """

            You can suggest any song that matches my workout context, whether from my library or Apple Music catalog. Use my taste profile as guidance, but do not assume the imported playlist should be played in order.
            """
        }

        // Build heart rate zone guidance for interval changes
        let heartRateGuidance = buildHeartRateGuidance(context: context)

        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance(avoiding: avoidedSongs)

        // Build fartlek guidance
        let fartlekGuidance = buildFartlekGuidance(isFartlek: isFartlek, effectiveIntensity: targetIntensity)

        let fullPrompt = """
        You are a music curator for running workouts. Suggest the next song based on these priorities:

        PRIORITY 1 — MY MUSIC TASTE PROFILE: \(musicPreferences)

        PRIORITY 2 — WORKOUT GOAL: The upcoming effort is \(targetIntensity.label). This is what I WANT to be doing. Choose music that fits this intended effort level.

        PRIORITY 3 — CURRENT METRICS: I have run \(String(format: "%.2f", currentDistance)) km in \(currentTime.formattedTime()). \(heartRateInfo). \(effortAnalysis)\(heartRateGuidance)\(varietyGuidance)\(fartlekGuidance)\(libraryInstruction)

        CRITICAL: Choose music that matches the PLANNED \(targetIntensity.label) intensity. If my heart rate doesn't match my goal, use the music to guide me back to the target zone. The song should fit both my taste AND my workout goal. Favor artists like \(tasteProfile.libraryArtistPrompt) when possible.
        """

        let metricsBody = joinedPromptSections([
            """
            Distance covered: \(String(format: "%.2f", currentDistance)) km
            Elapsed time: \(currentTime.formattedTime())
            \(heartRateInfo)
            \(effortAnalysis)
            """,
            heartRateGuidance,
            varietyGuidance,
            fartlekGuidance
        ], fallback: "No live workout metrics available.")

        return MusicPromptPreview(
            promptTitle: "Interval Change Prompt",
            sections: [
                MusicPromptSection(
                    title: "Taste Signals",
                    body: """
                    Taste profile: \(musicPreferences)
                    Strong artists: \(tasteProfile.libraryArtistPrompt)
                    Favorite genres: \(tasteProfile.genrePrompt)
                    """
                ),
                MusicPromptSection(
                    title: "Workout Goal",
                    body: """
                    Prompt style: Transition between workout states
                    Upcoming intensity: \(targetIntensity.label)
                    The music should guide the runner back toward the planned effort, not just mirror their current drift.
                    """
                ),
                MusicPromptSection(
                    title: "Current Metrics",
                    body: metricsBody
                ),
                MusicPromptSection(
                    title: "Playback Constraint",
                    body: normalizedPromptSection(libraryInstruction)
                ),
                MusicPromptSection(
                    title: "Final Steering Note",
                    body: "Choose music that fits both the runner's taste and the planned \(targetIntensity.label) effort. Favor artists like \(tasteProfile.libraryArtistPrompt) when possible."
                )
            ],
            fullPrompt: fullPrompt
        )
    }

    private func buildMusicSuggestionPrompt(
        context: MusicContext,
        preferences: MusicPreferences,
        preferLibrarySelection: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> String {
        makeMusicSuggestionPromptPreview(
            context: context,
            preferences: preferences,
            preferLibrarySelection: preferLibrarySelection,
            mustUseLibrary: mustUseLibrary,
            avoidedSongs: avoidedSongs
        ).fullPrompt
    }

    private func makeMusicSuggestionPromptPreview(
        context: MusicContext,
        preferences: MusicPreferences,
        preferLibrarySelection: Bool = false,
        mustUseLibrary: Bool = false,
        avoidedSongs: [MusicSong] = []
    ) -> MusicPromptPreview {
        let tasteProfile = MusicTasteProfileBuilder.build(from: preferences)
        let heartRateInfo = if let current = context.effectiveHeartRate, let target = context.targetHeartRate {
            "Current effective heart rate: \(current) BPM, target: \(target) BPM (\(context.heartRateZone.description)). \(context.heartRateTrend.promptDescription)"
        } else {
            "Heart rate: Unknown. \(context.heartRateTrend.promptDescription)"
        }

        let activityInfo = if let distance = context.currentDistance, let pace = context.currentPace {
            "Distance: \(String(format: "%.2f", distance)) km, Speed: \(String(format: "%.1f", pace)) km/h"
        } else {
            "Activity: Unknown"
        }

        // Build adaptive music guidance
        let adaptiveGuidance = if context.shouldAdjustMusic {
            """

            \(buildAdaptiveMusicGuidance(context: context))
            """
        } else {
            ""
        }

        let libraryInstruction = if mustUseLibrary {
            """

            CRITICAL PLAYBACK CONSTRAINT: Suggest only a song the runner can realistically play from their local library right now. Prefer exact saved favorites or songs by strong preferred library artists. Do not suggest catalog-only tracks.
            """
        } else if preferLibrarySelection {
            """

            IMPORTANT: Prefer a song that exists in the user's library. Their strongest taste signals are \(tasteProfile.libraryArtistPrompt) with genres \(tasteProfile.genrePrompt). Any imported playlist is only a taste sample.
            """
        } else {
            """

            You can suggest any song that matches the workout context, whether from their library or Apple Music catalog. Use their saved favorites and imported playlist taste sample as guidance, not as a playback queue.
            """
        }

        // Build heart rate zone guidance
        let heartRateGuidance = buildHeartRateGuidance(context: context)

        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance(avoiding: avoidedSongs)

        let recentSongsText = context.recentSongs.isEmpty
            ? "None yet"
            : context.recentSongs.map { "\($0.title) by \($0.artist)" }.joined(separator: ", ")

        let fullPrompt = """
        You are a music curator for running workouts. Suggest the perfect next song based on these priorities (in order):

        PRIORITY 1 — MUSIC PREFERENCES:
        - Taste profile: \(tasteProfile.conciseSummary)
        - Strong artists: \(tasteProfile.libraryArtistPrompt)
        - Favorite genres: \(tasteProfile.genrePrompt)
        - Preferred mood for \(context.currentIntensity.label): \(preferences.preferredMoodForIntensity[context.currentIntensity]?.displayName ?? "Not set")

        PRIORITY 2 — WORKOUT GOAL:
        - Planned intensity: \(context.currentIntensity.label) — this is what the runner WANTS to be doing
        - Time remaining in segment: \(Int(context.timeRemainingInSegment)) seconds

        PRIORITY 3 — CURRENT METRICS (adapt music to guide runner toward their goal):
        - \(heartRateInfo)
        - \(activityInfo)
        - Actual intensity: \(context.actualWorkoutIntensity.displayName)
        - User is actively exercising: \(context.isActive ? "Yes" : "No")
        - Current song ending in: \(context.currentSongEndingIn.map { "\(Int($0)) seconds" } ?? "Unknown")

        Recent songs: \(recentSongsText)\(adaptiveGuidance)\(heartRateGuidance)\(varietyGuidance)\(libraryInstruction)

        CRITICAL: Choose music that matches the PLANNED workout intensity (\(context.currentIntensity.label)). If the runner's heart rate doesn't match their goal, use music to guide them back to the target zone. The song should fit both the runner's taste AND their workout goal.
        """

        let metricsBody = joinedPromptSections([
            """
            \(heartRateInfo)
            \(activityInfo)
            Actual intensity: \(context.actualWorkoutIntensity.displayName)
            User is actively exercising: \(context.isActive ? "Yes" : "No")
            Current song ending in: \(context.currentSongEndingIn.map { "\(Int($0)) seconds" } ?? "Unknown")
            Recent songs: \(recentSongsText)
            """,
            adaptiveGuidance,
            heartRateGuidance,
            varietyGuidance
        ], fallback: "No live workout metrics available.")

        return MusicPromptPreview(
            promptTitle: "Next Song Prompt",
            sections: [
                MusicPromptSection(
                    title: "Music Preferences",
                    body: """
                    Taste profile: \(tasteProfile.conciseSummary)
                    Strong artists: \(tasteProfile.libraryArtistPrompt)
                    Favorite genres: \(tasteProfile.genrePrompt)
                    Preferred mood for \(context.currentIntensity.label): \(preferences.preferredMoodForIntensity[context.currentIntensity]?.displayName ?? "Not set")
                    """
                ),
                MusicPromptSection(
                    title: "Workout Goal",
                    body: """
                    Planned intensity: \(context.currentIntensity.label)
                    Time remaining in segment: \(Int(context.timeRemainingInSegment)) seconds
                    The music should support the intended effort, even if current metrics have drifted away from it.
                    """
                ),
                MusicPromptSection(
                    title: "Current Metrics",
                    body: metricsBody
                ),
                MusicPromptSection(
                    title: "Playback Constraint",
                    body: normalizedPromptSection(libraryInstruction)
                ),
                MusicPromptSection(
                    title: "Final Steering Note",
                    body: "Choose music that matches the planned \(context.currentIntensity.label) effort and use it to guide the runner back toward target if their heart rate has drifted."
                )
            ],
            fullPrompt: fullPrompt
        )
    }

    private func joinedPromptSections(_ sections: [String], fallback: String) -> String {
        let normalizedSections = sections
            .map(normalizedPromptSection)
            .filter { !$0.isEmpty }

        if normalizedSections.isEmpty {
            return fallback
        }

        return normalizedSections.joined(separator: "\n\n")
    }

    private func normalizedPromptSection(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = lines.firstIndex(where: { !$0.isEmpty }),
              let end = lines.lastIndex(where: { !$0.isEmpty }) else {
            return ""
        }

        return lines[start...end].joined(separator: "\n")
    }

    private func buildAdaptiveMusicGuidance(context: MusicContext) -> String {
        switch (context.currentIntensity, context.actualWorkoutIntensity) {
        case (.easy, .vigorous), (.easy, .maximum):
            return "CRITICAL MISMATCH: The goal is EASY but effective HR is too high (\(context.effectiveHeartRate ?? 0) BPM). They need to slow down NOW. Suggest a calming, slower-tempo song. Do not suggest anything intense or aggressive."
        case (.medium, .veryLight), (.medium, .light), (.hard, .veryLight), (.hard, .light):
            return "The runner planned a challenging workout but effective HR is low (\(context.effectiveHeartRate ?? 0) BPM). Suggest an energetic, motivational song to help them move harder."
        case (.easy, .veryLight), (.easy, .light):
            return "The runner planned an easy workout and heart rate is below target (\(context.effectiveHeartRate ?? 0) BPM). Suggest a moderately upbeat song to help them pick up the pace gently."
        case (.easy, .resting):
            return "The runner planned an easy workout but appears to be resting. Suggest an upbeat song to get them moving."
        default:
            return "Actual effort is close to planned effort. Suggest music that maintains this state."
        }
    }

    private func buildMotivationPrompt(segment: RunSegment, progress: Double, heartRate: Int?) -> String {
        let heartRateText = heartRate.map { " (HR: \($0) BPM)" } ?? ""
        let progressPercent = Int(progress * 100)

        return """
        You are a motivational running coach. The runner is in a \(segment.intensity.label) segment, \(progressPercent)% complete\(heartRateText).
        Target: \(segment.targetDescription)

        Provide a short, motivational message (under 15 words) to help them push through.
        """
    }

    private func buildRandomLibrarySongPrompt(preferences: MusicPreferences, intensity: Intensity) -> String {
        let tasteProfile = MusicTasteProfileBuilder.build(from: preferences)

        return """
        You are a music curator for running workouts. I need a random song from my music library for a \(intensity.label) intensity workout.

        The runner's library taste profile is:
        - \(tasteProfile.conciseSummary)
        - Strong artists: \(tasteProfile.libraryArtistPrompt)
        - Genres: \(tasteProfile.genrePrompt)

        Please select a random song from my library that would work well for a \(intensity.label) effort workout. Choose something that matches the energy level and would keep me motivated.

        If I have no favorites specified, suggest a popular song that would work well for this intensity level.
        """
    }

    private func buildMotivationalSpeechPrompt(workoutSummary: String) -> String {
        return """
        You are a motivational running coach. Give a short, inspiring speech to prepare someone for their upcoming run.

        Their workout plan: \(workoutSummary)

        Create a brief motivational speech (2-3 sentences, under 30 words) that:
        - Gets them excited and confident
        - Mentions the effort levels they'll experience
        - Ends with energy and determination

        Be encouraging, positive, and pump them up for the challenge ahead. Keep it concise and powerful.
        """
    }

    private func buildWorkoutMotivationPrompt(
        segmentChange: Bool,
        distanceMilestone: Bool,
        currentIntensity: Intensity,
        heartRate: Int?,
        totalDistance: Double
    ) -> String {
        var context = ""

        if segmentChange {
            context += "New segment starting - \(currentIntensity.label) effort. "
        }

        if distanceMilestone {
            let km = Int(totalDistance / 1000)
            context += "Another kilometer down! \(km)km completed. "
        }

        if let hr = heartRate {
            let hrStatus = getHeartRateStatus(heartRate: hr, intensity: currentIntensity)
            context += "Heart rate: \(hr) BPM. \(hrStatus) "
        }

        return """
        You are a motivational running coach. Give a short motivational message for this workout moment:
        \(context)

        Keep it under 15 words. Be encouraging and mention the effort level or milestone.
        """
    }

    // MARK: - Helper Methods for Prompt Building

    private func buildWorkoutPlanDescription(_ segments: [RunSegment]) -> String {
        if segments.count == 1 {
            let segment = segments[0]
            return "run \(segment.targetDescription) at \(segment.intensity.label) effort"
        } else {
            let segmentDescriptions = segments.enumerated().map { index, segment in
                "\(index + 1). \(segment.targetDescription) at \(segment.intensity.label) effort"
            }
            return "do an interval workout with \(segments.count) segments: \(segmentDescriptions.joined(separator: ", "))"
        }
    }

    private func buildMusicPreferencesDescription(_ preferences: MusicPreferences) -> String {
        MusicTasteProfileBuilder.build(from: preferences).conciseSummary
    }

    private func getEffortMoodMapping(_ intensity: Intensity) -> String {
        switch intensity {
        case .easy:
            return "relaxed"
        case .medium:
            return "energetic"
        case .hard:
            return "high-octane"
        }
    }

    private func analyzeHeartRateVsEffort(
        currentHeartRate: Int?,
        targetHeartRate: Int?,
        currentIntensity: Intensity,
        upcomingIntensity: Intensity?
    ) -> String {
        guard let current = currentHeartRate, let _ = targetHeartRate else {
            return "I need to maintain my current pace"
        }

        let intensity = upcomingIntensity ?? currentIntensity
        let (minHR, maxHR, _) = getHeartRateZone(for: intensity)

        if current < minHR {
            let deficit = minHR - current
            if deficit > 20 {
                return "My heart rate is WAY too low (\(current) BPM) for \(intensity.label) effort (target: \(minHR)-\(maxHR) BPM). I urgently need a high-energy, driving, fast-tempo song to get my heart rate up significantly."
            }
            return "My heart rate is below target (\(current) BPM) for \(intensity.label) effort (target: \(minHR)-\(maxHR) BPM). I need an energetic, up-tempo song to help increase my heart rate."
        } else if current > maxHR {
            let excess = current - maxHR
            switch intensity {
            case .easy:
                return "My heart rate is \(excess > 15 ? "SIGNIFICANTLY" : "") too high (\(current) BPM) for my EASY effort goal (target: \(minHR)-\(maxHR) BPM). I MUST slow down. Choose a calming, relaxed, slower-tempo song. DO NOT suggest intense, aggressive, heavy metal, or high-energy music — that would push my heart rate even higher when it needs to come DOWN."
            case .medium:
                return "My heart rate is above target (\(current) BPM) for medium effort (target: \(minHR)-\(maxHR) BPM). I need a steady, moderate-energy song to help bring my heart rate down slightly. Avoid very intense or aggressive music."
            case .hard:
                return "My heart rate is above target (\(current) BPM) for hard effort (target: \(minHR)-\(maxHR) BPM). I need a song that maintains intensity but doesn't push harder. Choose something driving but controlled."
            }
        } else {
            return "My heart rate is perfect (\(current) BPM) for \(intensity.label) effort (target: \(minHR)-\(maxHR) BPM). Choose a song that maintains this energy level — match the current vibe."
        }
    }

    private func getHeartRateZone(for intensity: Intensity) -> (min: Int, max: Int, name: String) {
        switch intensity {
        case .easy:
            return (130, 150, "Easy Zone")
        case .medium:
            return (140, 170, "Medium Zone")
        case .hard:
            return (160, 185, "Hard Zone")
        }
    }

    private func buildHeartRateGuidance(context: MusicContext) -> String {
        guard let currentHR = context.effectiveHeartRate else {
            return ""
        }

        let (minHR, maxHR, _) = getHeartRateZone(for: context.currentIntensity)

        if !context.hasStableHeartRateSignal {
            return """

            HEART RATE SIGNAL IS STILL SETTLING: Use the current intensity goal as the primary guide and avoid overreacting to a brief spike or dip. \(context.heartRateTrend.promptDescription)
            """
        }

        if currentHR < minHR {
            return """

            HEART RATE TOO LOW: Current HR is \(currentHR) BPM, but target for \(context.currentIntensity.label) effort is \(minHR)-\(maxHR) BPM.
            MUSIC STRATEGY: Choose an energetic, high-tempo, motivating song to help raise heart rate. Driving beats, fast tempo, and high energy are appropriate here.
            """
        } else if currentHR > maxHR {
            let excess = currentHR - maxHR
            let urgency = excess > 15 ? "URGENTLY " : ""
            var guidance = """

            HEART RATE TOO HIGH: Current HR is \(currentHR) BPM (\(excess) BPM above target), but the goal is \(context.currentIntensity.label) effort (\(minHR)-\(maxHR) BPM).
            MUSIC STRATEGY: \(urgency)Choose a calmer, relaxed, steady-tempo song to help bring heart rate DOWN.
            """
            if context.currentIntensity == .easy {
                guidance += """

                MANDATORY: Since this is an EASY effort goal, DO NOT suggest intense, aggressive, heavy metal, hard rock, or high-BPM songs. These would push heart rate UP when it needs to come DOWN. Choose chill, relaxed, or moderate-energy music only.
                """
            }
            return guidance
        } else {
            return """

            HEART RATE IN ZONE: Current HR is \(currentHR) BPM — perfect for \(context.currentIntensity.label) effort (target: \(minHR)-\(maxHR) BPM).
            MUSIC STRATEGY: Match the current energy level to maintain this zone. Don't push harder or calmer — stay steady.
            """
        }
    }

    private func buildStartingSongHeartRateGuidance(intensity: Intensity) -> String {
        let (minHR, maxHR, _) = getHeartRateZone(for: intensity)

        return """

        TARGET HEART RATE ZONE: For \(intensity.label) effort, I need to get into the \(minHR)-\(maxHR) BPM range.
        MUSIC STRATEGY: Choose a song that will help me gradually build up to my target heart rate zone. The song should match the energy level needed for \(intensity.label) effort.
        """
    }

    private func buildVarietyGuidance(avoiding avoidedSongs: [MusicSong] = []) -> String {
        let locallyAvoidedSuggestions = avoidedSongs.map { "\($0.artist) - \($0.title)" }
        let suggestionsToAvoid = recentSuggestions + locallyAvoidedSuggestions

        guard !suggestionsToAvoid.isEmpty, isVarietySessionActive || !locallyAvoidedSuggestions.isEmpty else {
            return ""
        }

        let avoidList = suggestionsToAvoid.joined(separator: ", ")

        let recentArtists = suggestionsToAvoid.map { suggestion in
            suggestion.components(separatedBy: " - ").first ?? suggestion
        }
        let uniqueArtists = Set(recentArtists)

        // For the last 3 songs, also avoid songs by those same artists to add variety
        let recentArtistList = suggestionsToAvoid.suffix(3).compactMap { suggestion in
            suggestion.components(separatedBy: " - ").first
        }
        let recentUniqueArtists = Set(recentArtistList)

        var guidance = """

        SONGS TO AVOID FOR THIS SELECTION: \(avoidList).
        Do not repeat any of these songs. Pick a different song.
        """

        if recentUniqueArtists.count <= 2 && !recentUniqueArtists.isEmpty {
            guidance += """

            VARIETY: I've been hearing too much from \(recentUniqueArtists.joined(separator: " and ")). Pick a DIFFERENT artist this time — someone new!
            """
        } else if uniqueArtists.count <= 3 && uniqueArtists.count > 0 {
            guidance += """

            VARIETY: Try to pick an artist I haven't heard from recently. Avoid: \(recentUniqueArtists.joined(separator: ", ")).
            """
        }

        return guidance
    }

    private func buildFartlekGuidance(isFartlek: Bool, effectiveIntensity: Intensity) -> String {
        guard isFartlek else { return "" }

        return """

        FARTLEK INTERVAL WORKOUT: This is a fartlek-style run with rapid alternating intensity changes (hard bursts followed by easy recovery, repeating). The segments switch frequently — some as short as 30 seconds. The effective intensity over the next few minutes is \(effectiveIntensity.label).

        MUSIC STRATEGY FOR FARTLEK:
        - Choose a song that sustains energy through repeated hard/easy swings.
        - Do NOT pick a chill or calming song — even during brief recovery segments, the runner needs to stay mentally engaged for the next hard effort.
        - Favor consistently driving, motivating music that works across intensity changes.
        - The song should feel right for both pushing hard AND recovering briefly without feeling out of place during either.
        - Think "workout anthem" energy — songs that keep adrenaline up even during short rest periods.
        """
    }

    private func buildWorkoutSummary(_ segments: [RunSegment]) -> String {
        // Group segments by intensity to create a summary
        let intensityGroups = Dictionary(grouping: segments) { $0.intensity }

        var summaryParts: [String] = []

        for intensity in [Intensity.easy, .medium, .hard] {
            if let segments = intensityGroups[intensity], !segments.isEmpty {
                let totalTime = segments.compactMap { segment in
                    if case .time(let seconds) = segment.target {
                        return seconds
                    }
                    return nil
                }.reduce(0, +)

                let totalDistance = segments.compactMap { segment in
                    if case .distance(let meters) = segment.target {
                        return meters
                    }
                    return nil
                }.reduce(0, +)

                var part = "\(segments.count) \(intensity.label) segment"
                if segments.count > 1 { part += "s" }

                if totalTime > 0 {
                    part += " totaling \(totalTime.formattedTime())"
                } else if totalDistance > 0 {
                    part += " totaling \(totalDistance.formattedDistanceMeters())"
                }

                summaryParts.append(part)
            }
        }

        return summaryParts.joined(separator: ", ")
    }

    private func getHeartRateStatus(heartRate: Int, intensity: Intensity) -> String {
        let ranges = getHeartRateRange(for: intensity)

        if heartRate < ranges.min {
            return "Heart rate is low - pick up the pace!"
        } else if heartRate > ranges.max {
            return "Heart rate is high - ease up a bit!"
        } else {
            return "Heart rate is perfect!"
        }
    }

    private func getHeartRateRange(for intensity: Intensity) -> (min: Int, max: Int) {
        switch intensity {
        case .easy:
            return (130, 150)
        case .medium:
            return (140, 170)
        case .hard:
            return (160, 185)
        }
    }
}

// MARK: - Fallback Suggestions

extension MusicAIService {
    /// Pre-curated suggestions when AI is unavailable
    static func fallbackSuggestion(for intensity: Intensity) -> MusicSuggestion {
        let suggestions: [Intensity: [MusicSuggestion]] = [
            .easy: [
                MusicSuggestion(songTitle: "Walking on Sunshine", artist: "Katrina and the Waves", reason: "Upbeat classic for easy pace", mood: .upbeat, confidence: 0.7),
                MusicSuggestion(songTitle: "Good Vibrations", artist: "The Beach Boys", reason: "Feel-good vibes for relaxed running", mood: .chill, confidence: 0.7),
                MusicSuggestion(songTitle: "Here Comes the Sun", artist: "The Beatles", reason: "Gentle energy for easy effort", mood: .chill, confidence: 0.7)
            ],
            .medium: [
                MusicSuggestion(songTitle: "Can't Stop the Feeling", artist: "Justin Timberlake", reason: "Energetic tempo for steady pace", mood: .energetic, confidence: 0.7),
                MusicSuggestion(songTitle: "Uptown Funk", artist: "Bruno Mars", reason: "High energy for medium effort", mood: .energetic, confidence: 0.7),
                MusicSuggestion(songTitle: "Shake It Off", artist: "Taylor Swift", reason: "Fun tempo for moderate running", mood: .upbeat, confidence: 0.7)
            ],
            .hard: [
                MusicSuggestion(songTitle: "Lose Yourself", artist: "Eminem", reason: "Intense motivation for hard effort", mood: .intense, confidence: 0.7),
                MusicSuggestion(songTitle: "Eye of the Tiger", artist: "Survivor", reason: "Classic power song for pushing hard", mood: .motivational, confidence: 0.7),
                MusicSuggestion(songTitle: "Stronger", artist: "Kanye West", reason: "Driving beat for maximum effort", mood: .intense, confidence: 0.7)
            ]
        ]
        return suggestions[intensity]?.randomElement() ?? MusicSuggestion(
            songTitle: "Don't Stop Me Now",
            artist: "Queen",
            reason: "Classic workout anthem",
            mood: .energetic,
            confidence: 0.5
        )
    }

    static let fallbackMotivationalSpeeches: [String] = [
        "Let's crush this workout! Your body is ready, your mind is strong. Time to run!",
        "Today's the day you prove what you're made of. Every step counts. Let's go!",
        "You've got this! Focus on your breathing, trust your training, and enjoy the run!"
    ]

    static func fallbackWorkoutMotivation(for intensity: Intensity) -> String {
        let motivations: [Intensity: [String]] = [
            .easy: ["Keep that easy pace, you're doing great!", "Nice and steady, saving energy for later!", "Smooth and relaxed, that's the way!"],
            .medium: ["You're in the zone! Keep pushing!", "Halfway there, stay strong!", "This pace is perfect, maintain it!"],
            .hard: ["This is where champions are made! Push through!", "Give it everything you've got!", "Dig deep, you're stronger than you think!"]
        ]
        return motivations[intensity]?.randomElement() ?? "Keep going, you've got this!"
    }
}

// MARK: - RunSegment Extension

extension RunSegment {
    var targetDescription: String {
        switch target {
        case .time(let seconds):
            return "\(seconds.formattedTime())"
        case .distance(let meters):
            return meters.formattedDistanceMeters()
        }
    }
}
