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
            return "This device does not support Apple Intelligence. AI music features require a compatible iPhone."
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
    @Guide(description: "The exact title of a real, commercially released song only, without the artist name. Do not invent titles or reuse a real title with the wrong artist. For example: 'Blinding Lights' not 'Blinding Lights by The Weeknd'")
    let songTitle: String

    @Guide(description: "The real primary artist or band name only, separate from the song title")
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
        preferLibrarySelection: Bool? = nil,
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
        let shouldSelectFromLibrary = mustUseLibrary || (preferLibrarySelection ?? (Double.random(in: 0...1) < librarySelectionProbability))

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
        preferLibrarySelection: Bool? = nil,
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
        let shouldSelectFromLibrary = mustUseLibrary || (preferLibrarySelection ?? (Double.random(in: 0...1) < librarySelectionProbability))

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
        preferLibrarySelection: Bool? = nil,
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
        let shouldSelectFromLibrary = mustUseLibrary || (preferLibrarySelection ?? (Double.random(in: 0...1) < librarySelectionProbability))

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
        let zoneReference = buildHeartRateZoneReference()
        let discoveryGuidance = buildDiscoveryBalanceGuidance()

        let libraryInstruction = if mustUseLibrary {
            """

            CRITICAL PLAYBACK CONSTRAINT: Suggest only a song the runner can realistically play from their local library right now. Choose from saved favorite songs, strong library artists, or other playable library taste signals. Do not suggest catalog-only music. Among playable choices, reject favorites that are weak fits for the target heart-rate zone.
            CATALOG REALITY REQUIREMENT: Recommend only a real song by the stated artist. Do not invent song titles or pair a real title with the wrong artist.
            """
        } else if preferLibrarySelection {
            """

            IMPORTANT: Prefer a song that exists in my music library. Use saved favorites as taste evidence, not as an ordered queue, and use any imported playlist only as a taste sample.
            CATALOG REALITY REQUIREMENT: Recommend only a real, commercially released song. Do not invent song titles or pair a real title with the wrong artist. The app will validate the exact title and primary artist before playback.
            """
        } else {
            """

            You can suggest any song that matches my workout context, whether from my library or Apple Music catalog. Use my saved favorites and imported playlist taste sample to steer the choice, but do not treat any playlist as a required queue.
            CATALOG REALITY REQUIREMENT: Recommend only a real, commercially released Apple Music song by the stated artist. Do not invent song titles or pair a real title with the wrong artist. If using a favorite/listed artist, use a real song from that artist's catalog.
            """
        }

        // Build heart rate guidance for starting song
        let heartRateGuidance = buildStartingSongHeartRateGuidance(intensity: currentIntensity)

        // Build energy fit guidance
        let energyFitGuidance = buildIntensityEnergyFitGuidance(for: currentIntensity)

        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance(avoiding: avoidedSongs)

        // Build fartlek guidance
        let fartlekGuidance = buildFartlekGuidance(isFartlek: isFartlek, effectiveIntensity: currentIntensity)

        let selectionGoals = """
        - Get me pumped up and ready to run
        - Match the energy level for \(currentIntensity.label) (\(currentIntensity.percentDescription))
        - Reflect my strongest taste signals: \(tasteProfile.libraryArtistPrompt) / \(tasteProfile.genrePrompt)
        - Set the perfect tone for my workout
        - Help me get into \(currentIntensity.label), the target heart-rate zone for this segment
        - Add variety to keep my playlist fresh and engaging
        """

        let fullPrompt = """
        You are a music curator for running workouts. I am starting an outdoor run. My plan is to \(workoutDescription). My taste profile is \(musicPreferences). Find a motivating song to get me started. With this being \(currentIntensity.label) (\(currentIntensity.percentDescription), \(currentIntensity.targetDescription)), make this a \(effortMood) song.\(zoneReference)\(heartRateGuidance)\(energyFitGuidance)\(discoveryGuidance)\(varietyGuidance)\(fartlekGuidance)\(libraryInstruction)

        Choose a song that will:
        \(selectionGoals)
        """

        let guidanceBody = joinedPromptSections([
            heartRateGuidance,
            zoneReference,
            energyFitGuidance,
            discoveryGuidance,
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
                    Planned zone: \(currentIntensity.label)
                    Zone definition: \(currentIntensity.percentDescription), \(currentIntensity.targetDescription)
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
        let zoneReference = buildHeartRateZoneReference()
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
        let discoveryGuidance = buildDiscoveryBalanceGuidance()

        let libraryInstruction = if mustUseLibrary {
            """

            CRITICAL PLAYBACK CONSTRAINT: Suggest only a song the runner can realistically play from their local library right now. Choose from saved favorites, known preferred artists, or strong library taste signals. Do not suggest catalog-only songs. Among playable choices, reject favorites that are weak fits for the target heart-rate zone.
            CATALOG REALITY REQUIREMENT: Recommend only a real song by the stated artist. Do not invent song titles or pair a real title with the wrong artist.
            """
        } else if preferLibrarySelection {
            """

            IMPORTANT: Prefer a song from my local library. Use saved favorites as taste evidence, not as an ordered queue, and use imported playlist data only as taste guidance.
            CATALOG REALITY REQUIREMENT: Recommend only a real, commercially released song. Do not invent song titles or pair a real title with the wrong artist. The app will validate the exact title and primary artist before playback.
            """
        } else {
            """

            You can suggest any song that matches my workout context, whether from my library or Apple Music catalog. Use my taste profile as guidance, but do not assume the imported playlist should be played in order.
            CATALOG REALITY REQUIREMENT: Recommend only a real, commercially released Apple Music song by the stated artist. Do not invent song titles or pair a real title with the wrong artist. If using a favorite/listed artist, use a real song from that artist's catalog.
            """
        }

        // Build heart rate zone guidance for interval changes
        let heartRateGuidance = buildHeartRateGuidance(context: context)

        // Build energy fit guidance
        let energyFitGuidance = buildIntensityEnergyFitGuidance(for: targetIntensity)

        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance(avoiding: avoidedSongs)

        // Build fartlek guidance
        let fartlekGuidance = buildFartlekGuidance(isFartlek: isFartlek, effectiveIntensity: targetIntensity)

        let fullPrompt = """
        You are a music curator for running workouts. Suggest the next song based on these priorities:

        PRIORITY 1 — MY MUSIC TASTE PROFILE: \(musicPreferences)

        PRIORITY 2 — WORKOUT GOAL: The upcoming target is \(targetIntensity.label) (\(targetIntensity.percentDescription), \(targetIntensity.targetDescription)). This is what I WANT to be doing. Choose music that fits this intended heart-rate zone.

        PRIORITY 3 — CURRENT METRICS: I have run \(String(format: "%.2f", currentDistance)) km in \(currentTime.formattedTime()). \(heartRateInfo). \(effortAnalysis)\(zoneReference)\(heartRateGuidance)\(energyFitGuidance)\(discoveryGuidance)\(varietyGuidance)\(fartlekGuidance)\(libraryInstruction)

        CRITICAL: Choose music that matches the PLANNED \(targetIntensity.label) heart-rate zone. If my heart rate doesn't match my goal, use the music to guide me back to the target zone. The song should fit both my taste AND my workout goal. Use artists like \(tasteProfile.libraryArtistPrompt) as taste anchors, not automatic picks, and do not let artist fit override zone fit.
        """

        let metricsBody = joinedPromptSections([
            """
            Distance covered: \(String(format: "%.2f", currentDistance)) km
            Elapsed time: \(currentTime.formattedTime())
            \(heartRateInfo)
            \(effortAnalysis)
            """,
            zoneReference,
            heartRateGuidance,
            energyFitGuidance,
            discoveryGuidance,
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
                    Upcoming zone: \(targetIntensity.label)
                    Zone definition: \(targetIntensity.percentDescription), \(targetIntensity.targetDescription)
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
                    body: "Choose music that fits both the runner's taste and the planned \(targetIntensity.label) heart-rate zone. Use favorite artists as taste anchors, not automatic picks."
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
        let zoneReference = buildHeartRateZoneReference()
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

        let discoveryGuidance = buildDiscoveryBalanceGuidance()

        let libraryInstruction = if mustUseLibrary {
            """

            CRITICAL PLAYBACK CONSTRAINT: Suggest only a song the runner can realistically play from their local library right now. Prefer saved favorites, songs by strong preferred library artists, or other playable library taste signals. Do not suggest catalog-only tracks. Among playable choices, reject favorites that are weak fits for the target heart-rate zone.
            CATALOG REALITY REQUIREMENT: Recommend only a real song by the stated artist. Do not invent song titles or pair a real title with the wrong artist.
            """
        } else if preferLibrarySelection {
            """

            IMPORTANT: Prefer a song that exists in the user's library. Their strongest taste signals are \(tasteProfile.libraryArtistPrompt) with genres \(tasteProfile.genrePrompt). Treat those as taste evidence, not as an ordered queue. Any imported playlist is only a taste sample.
            CATALOG REALITY REQUIREMENT: Recommend only a real, commercially released song. Do not invent song titles or pair a real title with the wrong artist. The app will validate the exact title and primary artist before playback.
            """
        } else {
            """

            You can suggest any song that matches the workout context, whether from their library or Apple Music catalog. Use their saved favorites and imported playlist taste sample as guidance, not as a playback queue.
            CATALOG REALITY REQUIREMENT: Recommend only a real, commercially released Apple Music song by the stated artist. Do not invent song titles or pair a real title with the wrong artist. If using a favorite/listed artist, use a real song from that artist's catalog.
            """
        }

        // Build heart rate zone guidance
        let heartRateGuidance = buildHeartRateGuidance(context: context)

        // Build energy fit guidance
        let energyFitGuidance = buildIntensityEnergyFitGuidance(for: context.currentIntensity)

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
        - Planned heart-rate zone: \(context.currentIntensity.label) (\(context.currentIntensity.percentDescription), \(context.currentIntensity.targetDescription)) — this is what the runner WANTS to be doing
        - Time remaining in segment: \(Int(context.timeRemainingInSegment)) seconds

        PRIORITY 3 — CURRENT METRICS (adapt music to guide runner toward their goal):
        - \(heartRateInfo)
        - \(activityInfo)
        - Actual intensity: \(context.actualWorkoutIntensity.displayName)
        - User is actively exercising: \(context.isActive ? "Yes" : "No")
        - Current song ending in: \(context.currentSongEndingIn.map { "\(Int($0)) seconds" } ?? "Unknown")

        Recent songs: \(recentSongsText)\(zoneReference)\(adaptiveGuidance)\(heartRateGuidance)\(energyFitGuidance)\(discoveryGuidance)\(varietyGuidance)\(libraryInstruction)

        CRITICAL: Choose music that matches the PLANNED heart-rate zone (\(context.currentIntensity.label)). If the runner's heart rate doesn't match their goal, use music to guide them back to the target zone. The song should fit both the runner's taste AND their workout goal. Do not let artist fit override zone fit.
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
            zoneReference,
            adaptiveGuidance,
            heartRateGuidance,
            energyFitGuidance,
            discoveryGuidance,
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
                    Planned zone: \(context.currentIntensity.label)
                    Zone definition: \(context.currentIntensity.percentDescription), \(context.currentIntensity.targetDescription)
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
                    body: "Choose music that matches the planned \(context.currentIntensity.label) heart-rate zone and use it to guide the runner back toward target if their heart rate has drifted."
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

    private func buildHeartRateZoneReference() -> String {
        let zones = Intensity.allCases
            .map { "\($0.label): \($0.percentDescription), \($0.targetDescription)" }
            .joined(separator: "; ")

        return """

        HEART RATE ZONE MODEL: \(zones). These zones are based on percentage of maximum heart rate; use personalized target BPM when available, otherwise treat the BPM ranges as estimates.
        """
    }

    private func buildAdaptiveMusicGuidance(context: MusicContext) -> String {
        let heartRate = context.effectiveHeartRate ?? 0

        switch context.heartRateZone {
        case .tooHigh:
            if context.currentIntensity.zoneNumber <= 2 {
                return "CRITICAL MISMATCH: The goal is \(context.currentIntensity.label), but effective HR is too high (\(heartRate) BPM). They need to ease down now. Suggest calming, lower-arousal music with a relaxed or half-time feel. Prefer chill pop, acoustic, folk, country, soft rock, or mellow alternative. Avoid hype, dance-club, aggressive, anthemic, heavy, or emotionally escalating tracks."
            }
            if context.currentIntensity == .zone5 {
                return "SAFETY MISMATCH: The runner is already above the Zone 5 target. Do not push harder. Choose a driving but controlled track that helps them hold form or back off slightly, not a maximal hype song."
            }
            return "The runner is above the planned \(context.currentIntensity.label) target. Choose preference-aligned music that reduces arousal while preserving enough rhythm for safe running form. A calmer, chill, acoustic, or relaxed song can be correct here if it helps bring heart rate down. Avoid maximal hype, aggressive drops, or sprint-finish energy."
        case .tooLow:
            if context.currentIntensity.zoneNumber <= 2 {
                return "The runner is below the planned \(context.currentIntensity.label) target. Suggest gently upbeat, smooth music to lift cadence without turning the segment into high-zone effort."
            }
            return "The runner planned \(context.currentIntensity.label) but effective HR is low (\(heartRate) BPM). Suggest a motivating, higher-energy song with a clear beat to help them move toward the target zone."
        case .perfect, .close:
            return "Actual effort is close to the planned \(context.currentIntensity.label). Suggest music that maintains this state."
        case .unknown:
            return "Heart-rate fit is unknown. Use the planned \(context.currentIntensity.label) as the primary guide."
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
        case .zone1:
            return "calming recovery"
        case .zone2:
            return "relaxed aerobic"
        case .zone3:
            return "rhythmic tempo"
        case .zone4:
            return "driving threshold"
        case .zone5:
            return "controlled peak-effort"
        }
    }

    private func analyzeHeartRateVsEffort(
        currentHeartRate: Int?,
        targetHeartRate: Int?,
        currentIntensity: Intensity,
        upcomingIntensity: Intensity?
    ) -> String {
        guard let current = currentHeartRate else {
            return "I need to maintain my current pace"
        }

        let intensity = upcomingIntensity ?? currentIntensity
        let (minHR, maxHR, _) = getHeartRateZone(for: intensity, targetHeartRate: targetHeartRate)

        if current < minHR {
            let deficit = minHR - current
            if deficit > 20 {
                return "My heart rate is way below \(intensity.label) (\(current) BPM, target: \(minHR)-\(maxHR) BPM). I need music that lifts effort toward this zone without ignoring safety."
            }
            return "My heart rate is below \(intensity.label) (\(current) BPM, target: \(minHR)-\(maxHR) BPM). I need a more motivating, rhythmic song to help increase effort."
        } else if current > maxHR {
            let excess = current - maxHR
            switch intensity {
            case .zone1, .zone2:
                return "My heart rate is \(excess > 15 ? "significantly" : "") too high (\(current) BPM) for \(intensity.label) (target: \(minHR)-\(maxHR) BPM). I must slow down. Choose calming, relaxed, lower-arousal music. Avoid hype, dance-club, aggressive, heavy, anthemic, or emotionally escalating tracks because they would push my heart rate higher when it needs to come down."
            case .zone3:
                return "My heart rate is above \(intensity.label) (\(current) BPM, target: \(minHR)-\(maxHR) BPM). I need preference-aligned music that brings effort down. A calmer, chill, acoustic, or relaxed song can be a good choice here if it helps reduce heart rate while preserving safe running form. Avoid very intense, aggressive, or sprint-finish music."
            case .zone4:
                return "My heart rate is above \(intensity.label) (\(current) BPM, target: \(minHR)-\(maxHR) BPM). I need a song that stays driving but controlled, with no extra sprint-finish push."
            case .zone5:
                return "My heart rate is above the Zone 5 target (\(current) BPM, target: \(minHR)-\(maxHR) BPM). Do not push harder. Choose controlled intensity that supports form or backing off."
            }
        } else {
            return "My heart rate is in \(intensity.label) (\(current) BPM, target: \(minHR)-\(maxHR) BPM). Choose a song that maintains this zone."
        }
    }

    private func getHeartRateZone(for intensity: Intensity, targetHeartRate: Int? = nil) -> (min: Int, max: Int, name: String) {
        if let targetHeartRate {
            let range = intensity.percentRange
            let midpoint = (range.lower + range.upper) / 2
            let inferredMaxHeartRate = Double(targetHeartRate) / midpoint
            let minHR = Int((inferredMaxHeartRate * range.lower).rounded())
            let maxHR = Int((inferredMaxHeartRate * range.upper).rounded())
            return (minHR, maxHR, intensity.label)
        }

        let range = intensity.defaultHeartRateRange
        return (range.lowerBound, range.upperBound, intensity.label)
    }

    private func buildHeartRateGuidance(context: MusicContext) -> String {
        guard let currentHR = context.effectiveHeartRate else {
            return ""
        }

        let (minHR, maxHR, _) = getHeartRateZone(
            for: context.currentIntensity,
            targetHeartRate: context.targetHeartRate
        )

        if !context.hasStableHeartRateSignal {
            return """

            HEART RATE SIGNAL IS STILL SETTLING: Use the current intensity goal as the primary guide and avoid overreacting to a brief spike or dip. \(context.heartRateTrend.promptDescription)
            """
        }

        if currentHR < minHR {
            return """

            HEART RATE TOO LOW: Current HR is \(currentHR) BPM, but target for \(context.currentIntensity.label) is \(minHR)-\(maxHR) BPM.
            MUSIC STRATEGY: Choose music that raises effort toward the target zone. For Zone 1-2, lift gently without hype. For Zone 3-5, stronger beats and higher energy are appropriate.
            """
        } else if currentHR > maxHR {
            let excess = currentHR - maxHR
            let urgency = excess > 15 ? "URGENTLY " : ""
            var guidance = """

            HEART RATE TOO HIGH: Current HR is \(currentHR) BPM (\(excess) BPM above target), but the goal is \(context.currentIntensity.label) (\(minHR)-\(maxHR) BPM).
            MUSIC STRATEGY: \(urgency)Choose a calmer, relaxed, steady-tempo song to help bring heart rate DOWN.
            HEART-RATE CORRECTION OVERRIDES DEFAULT ENERGY: If this conflicts with normal \(context.currentIntensity.label) energy guidance, prioritize lowering arousal. A chill, acoustic, relaxed, or lower-energy taste match can be correct when HR is too high, as long as it still supports safe running form.
            """
            if context.currentIntensity.zoneNumber <= 2 {
                guidance += """

                MANDATORY: Since this is a low-zone goal, DO NOT suggest intense, aggressive, heavy, hard rock, dance-club, anthemic, or high-arousal songs. These would push heart rate UP when it needs to come DOWN. Choose chill, relaxed, or gently upbeat music only.
                """
            }
            return guidance
        } else {
            return """

            HEART RATE IN ZONE: Current HR is \(currentHR) BPM — in \(context.currentIntensity.label) (target: \(minHR)-\(maxHR) BPM).
            MUSIC STRATEGY: Match the current energy level to maintain this zone. Don't push harder or calmer — stay steady.
            """
        }
    }

    private func buildIntensityEnergyFitGuidance(for intensity: Intensity) -> String {
        switch intensity {
        case .zone1:
            return """

            ENERGY FIT REQUIREMENT: For Zone 1, choose very low-arousal recovery music with an easy, steady pulse. Soft pop, acoustic, folk, mellow country, ambient-leaning pop, and relaxed grooves are valid. Avoid anything that feels like a push, a dramatic build, a big sing-along anthem, pop-punk, hard-driving pop rock, forceful drums/guitars, shouted choruses, or a "motivational" favorite. A favorite workout song is still a bad Zone 1 pick if it would make the runner speed up or brace for impact.
            """
        case .zone2:
            return """

            ENERGY FIT REQUIREMENT: For Zone 2, choose relaxed or gently upbeat music that still has a stable, runnable groove for easy aerobic running. Low-arousal acoustic, folk, country, soft pop, chill pop, mellow alternative, and smooth pop are valid only when they keep forward motion. Avoid piano ballads, wedding/torch ballads, dramatic vocal showcases, aggressive tracks, heavy tracks, anthems, maximal hype, or songs whose best justification is only "calm" without a usable running pulse. A favorite ballad is still a bad Zone 2 running pick.
            """
        case .zone3:
            return """

            ENERGY FIT REQUIREMENT: For Zone 3 when heart rate is in-zone or below-zone, the song must feel run-ready, rhythmic, and motivating from the first minute, not just powerful at the chorus. Prefer pop, alternative pop, dance pop, pop rock, EDM, or hip-hop with an obvious beat and moderate energy, roughly 105-145 BPM or an obvious double-time/half-time running groove. When HR is in-zone or below-zone, avoid acoustic or piano ballads, sparse singer-songwriter tracks, emotional pop-rock power ballads, slow crescendos, dark minimal tracks, and songs whose best justification is "calming", "beautiful ballad", or "steady tempo" without a driving beat. If HEART RATE TOO HIGH appears above, this default Zone 3 energy target changes: calming, chill, acoustic, or relaxed preference-aligned music can be a good corrective pick to bring HR down. Related-artist exploration must pass the current HR need before novelty counts.
            """
        case .zone4:
            return """

            ENERGY FIT REQUIREMENT: For Zone 4, choose a driving, high-energy track with urgency, strong percussion, or a forceful hook. The song should help sustain threshold work without sounding chaotic. Avoid chill, sleepy, acoustic, ballad, or low-energy mid-tempo tracks that would flatten the workout.
            """
        case .zone5:
            return """

            ENERGY FIT REQUIREMENT: For Zone 5, choose a peak-effort track for short intervals only: intense, explosive, tightly rhythmic, and motivating from the first 30 seconds. Prefer hard-charging pop, EDM, hip-hop, rock, or pop-punk with urgent percussion, high arousal, and a clear drive to sprint. It should push hard while still feeling controlled enough for safe running form. Avoid chill, sleepy, loose, meandering, relaxed indie/electro-funk, mid-tempo "cool groove" songs, or tracks whose best justification is only a bassline.
            """
        }
    }

    private func buildStartingSongHeartRateGuidance(intensity: Intensity) -> String {
        let (minHR, maxHR, _) = getHeartRateZone(for: intensity)

        return """

        TARGET HEART RATE ZONE: \(intensity.label) is \(intensity.percentDescription). Using the default max-HR estimate, that is roughly \(minHR)-\(maxHR) BPM.
        MUSIC STRATEGY: Choose a song that will help me gradually settle into \(intensity.label). The song should match the energy level needed for \(intensity.targetDescription).
        """
    }

    private func buildDiscoveryBalanceGuidance() -> String {
        """

        TASTE / EXPLORATION BALANCE: Use favorite artists and favorite songs as taste anchors, not a queue. Across repeated recommendations, exact favorite artists or exact favorite songs should be about 40% of picks; about 60% should explore real related artists or adjacent songs that fit the same taste family. Only choose an exact favorite when it is also one of the best heart-rate-zone fits available. A related artist with better zone fit beats a weaker favorite. If the recent-song avoid list already includes exact favorites or obvious favorite artists, treat the 40% favorite quota as satisfied for this turn and default to a real related artist outside the explicit Favorite Artists list when source constraints allow. Do not rationalize a favorite ballad, slow crescendo, dramatic vocal showcase, workout anthem, or low-groove song as a fit just because the artist appears in the taste profile.
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

        if suggestionsToAvoid.count >= 2 {
            guidance += """

            SESSION DISCOVERY: Recent picks already establish the listener's taste. If those picks include exact favorites or artists from the explicit favorite-artist list, treat the 40% favorite quota as already satisfied for this turn. Prefer a real related artist outside the explicit favorite list unless there is no valid heart-rate-zone fit from an adjacent artist. Do not choose another exact favorite merely because it is familiar.
            """
        }

        if suggestionsToAvoid.count >= 6 {
            guidance += """

            VARIETY ESCALATION: The recent-song list is now long, so do not keep mining the obvious favorite-song lane. Prefer a real, workout-appropriate song by a related Apple Music catalog artist outside the recent artists when possible. Use genre adjacency from the saved taste profile to explore, while still validating the exact title and primary artist. If recent picks overuse exact favorites, deliberately choose a related artist with stronger heart-rate-zone fit.
            """
        } else if recentUniqueArtists.count <= 2 && !recentUniqueArtists.isEmpty {
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

        FARTLEK INTERVAL WORKOUT: This is a fartlek-style run with rapid alternating heart-rate zones, usually high-zone bursts followed by low-zone recovery. The segments switch frequently — some as short as 30 seconds. The effective zone over the next few minutes is \(effectiveIntensity.label).

        MUSIC STRATEGY FOR FARTLEK:
        - Choose a song that sustains energy through repeated high/low zone swings.
        - Do NOT pick a chill or calming song — even during brief recovery segments, the runner needs to stay mentally engaged for the next high-zone effort.
        - Favor consistently driving, motivating music that works across intensity changes.
        - The song should feel right for both pushing hard AND recovering briefly without feeling out of place during either.
        - Think "workout anthem" energy — songs that keep adrenaline up even during short rest periods.
        """
    }

    private func buildWorkoutSummary(_ segments: [RunSegment]) -> String {
        // Group segments by intensity to create a summary
        let intensityGroups = Dictionary(grouping: segments) { $0.intensity }

        var summaryParts: [String] = []

        for intensity in Intensity.allCases {
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
        let range = intensity.defaultHeartRateRange
        return (range.lowerBound, range.upperBound)
    }
}

// MARK: - Fallback Suggestions

extension MusicAIService {
    /// Pre-curated suggestions when AI is unavailable
    static func fallbackSuggestion(for intensity: Intensity) -> MusicSuggestion {
        let suggestions: [Intensity: [MusicSuggestion]] = [
            .zone1: [
                MusicSuggestion(songTitle: "Banana Pancakes", artist: "Jack Johnson", reason: "Low-arousal recovery music for Zone 1.", mood: .calming, confidence: 0.7),
                MusicSuggestion(songTitle: "Here Comes the Sun", artist: "The Beatles", reason: "Gentle, relaxed energy for warm-up or cool-down.", mood: .chill, confidence: 0.7),
                MusicSuggestion(songTitle: "Better Together", artist: "Jack Johnson", reason: "Soft acoustic pacing that will not push effort upward.", mood: .calming, confidence: 0.7)
            ],
            .zone2: [
                MusicSuggestion(songTitle: "Good Vibrations", artist: "The Beach Boys", reason: "Feel-good but relaxed energy for aerobic base work.", mood: .chill, confidence: 0.7),
                MusicSuggestion(songTitle: "Riptide", artist: "Vance Joy", reason: "Gently upbeat acoustic pop for easy endurance.", mood: .upbeat, confidence: 0.7),
                MusicSuggestion(songTitle: "Budapest", artist: "George Ezra", reason: "Smooth, controlled rhythm for Zone 2 running.", mood: .chill, confidence: 0.7)
            ],
            .zone3: [
                MusicSuggestion(songTitle: "Can't Stop the Feeling", artist: "Justin Timberlake", reason: "Run-ready rhythm for steady Zone 3 tempo.", mood: .energetic, confidence: 0.7),
                MusicSuggestion(songTitle: "Shake It Off", artist: "Taylor Swift", reason: "Upbeat, rhythmic pop for controlled moderate work.", mood: .upbeat, confidence: 0.7),
                MusicSuggestion(songTitle: "Feel It Still", artist: "Portugal. The Man", reason: "Compact groove that supports a steady tempo.", mood: .energetic, confidence: 0.7)
            ],
            .zone4: [
                MusicSuggestion(songTitle: "Uptown Funk", artist: "Mark Ronson", reason: "Driving, forceful groove for threshold work.", mood: .energetic, confidence: 0.7),
                MusicSuggestion(songTitle: "Eye of the Tiger", artist: "Survivor", reason: "Classic power song for controlled hard running.", mood: .motivational, confidence: 0.7),
                MusicSuggestion(songTitle: "Stronger", artist: "Kanye West", reason: "Driving beat for high-zone effort.", mood: .intense, confidence: 0.7)
            ],
            .zone5: [
                MusicSuggestion(songTitle: "Lose Yourself", artist: "Eminem", reason: "Intense motivation for short peak intervals.", mood: .intense, confidence: 0.7),
                MusicSuggestion(songTitle: "Till I Collapse", artist: "Eminem", reason: "Explosive, controlled intensity for brief Zone 5 work.", mood: .intense, confidence: 0.7),
                MusicSuggestion(songTitle: "Titanium", artist: "David Guetta", reason: "High-energy peak-effort track with a strong hook.", mood: .intense, confidence: 0.7)
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
            .zone1: ["Recover smooth and stay relaxed.", "Easy breathing, light feet.", "Let the effort come down."],
            .zone2: ["Stay conversational and steady.", "Smooth aerobic work, right here.", "Keep this easy rhythm."],
            .zone3: ["Strong tempo, stay controlled.", "Hold this steady effort.", "Rhythm locked, keep moving."],
            .zone4: ["Threshold work, controlled power.", "Hard but smooth, stay composed.", "Drive the pace with control."],
            .zone5: ["Short peak effort, strong form.", "Explode, then recover.", "Powerful and controlled now."]
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
