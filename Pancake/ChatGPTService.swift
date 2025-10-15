import Foundation
import Combine

// MARK: - ChatGPT Service
@MainActor
final class ChatGPTService: ObservableObject {
    static let shared = ChatGPTService()
    
    @Published var isGenerating = false
    @Published var lastError: Error?
    @Published var apiKey: String = ""
    
    // Configuration for library selection probability
    @Published var librarySelectionProbability: Double = 0.45 // 45% chance to select from library
    
    // Variety tracking to prevent repetitive suggestions
    private var recentSuggestions: [String] = []
    private let maxRecentSuggestions = 5
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let defaultModel = "gpt-3.5-turbo"
    private let maxTokens = 200 // Reduced for faster response
    
    private init() {
        loadAPIKey()
        loadLibrarySelectionProbability()
    }
    
    // MARK: - API Key Management
    
    func setAPIKey(_ key: String) {
        apiKey = key
        saveAPIKey()
    }
    
    private func loadAPIKey() {
        apiKey = UserDefaults.standard.string(forKey: "ChatGPT_API_Key") ?? ""
    }
    
    private func saveAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: "ChatGPT_API_Key")
    }
    
    // MARK: - Library Selection Probability Management
    
    func setLibrarySelectionProbability(_ probability: Double) {
        librarySelectionProbability = max(0.0, min(1.0, probability)) // Clamp between 0 and 1
        saveLibrarySelectionProbability()
    }
    
    private func loadLibrarySelectionProbability() {
        librarySelectionProbability = UserDefaults.standard.double(forKey: "ChatGPT_LibrarySelectionProbability")
        if librarySelectionProbability == 0.0 {
            librarySelectionProbability = 0.45 // Default to 45%
        }
    }
    
    private func saveLibrarySelectionProbability() {
        UserDefaults.standard.set(librarySelectionProbability, forKey: "ChatGPT_LibrarySelectionProbability")
    }
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - Music Suggestion Generation
    
    /// Get a random song from user's library based on their preferences
    func getRandomLibrarySong(
        preferences: MusicPreferences,
        intensity: Intensity
    ) async throws -> MusicSuggestion {
        guard isConfigured else {
            throw ChatGPTError.apiKeyNotSet
        }
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        let prompt = buildRandomLibrarySongPrompt(preferences: preferences, intensity: intensity)
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: buildSystemPrompt()),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: 0.8 // Higher temperature for more randomness
        )
        
        let response = try await makeAPIRequestWithRetry(request)
        
        let suggestion = try parseMusicSuggestion(from: response)
        print("🎲 ChatGPT selected random library song: '\(suggestion.songTitle)' by \(suggestion.artist) (mood: \(suggestion.mood.rawValue))")
        
        return suggestion
    }
    
    func generateMusicSuggestion(
        context: MusicContext,
        userPreferences: MusicPreferences
    ) async throws -> MusicSuggestion {
        guard isConfigured else {
            throw ChatGPTError.apiKeyNotSet
        }
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        // Configurable chance to select from user's library
        let shouldSelectFromLibrary = Double.random(in: 0...1) < librarySelectionProbability
        
        let prompt = buildMusicSuggestionPrompt(
            context: context, 
            preferences: userPreferences, 
            preferLibrarySelection: shouldSelectFromLibrary
        )
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: buildSystemPrompt()),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: 0.7
        )
        
        // Try the request with retry logic
        let response = try await makeAPIRequestWithRetry(request)
        
        let suggestion = try parseMusicSuggestion(from: response)
        
        // Track this suggestion for variety
        trackSuggestion(suggestion)
        
        return suggestion
    }
    
    func generateStartingSongSuggestion(
        workoutPlan: [RunSegment],
        userPreferences: MusicPreferences,
        currentIntensity: Intensity
    ) async throws -> MusicSuggestion {
        guard isConfigured else {
            throw ChatGPTError.apiKeyNotSet
        }
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        // Configurable chance to select from user's library
        let shouldSelectFromLibrary = Double.random(in: 0...1) < librarySelectionProbability
        
        let prompt = buildStartingSongPrompt(
            workoutPlan: workoutPlan,
            preferences: userPreferences,
            currentIntensity: currentIntensity,
            preferLibrarySelection: shouldSelectFromLibrary
        )
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: buildSystemPrompt()),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: 0.7
        )
        
        let response = try await makeAPIRequestWithRetry(request)
        
        let suggestion = try parseMusicSuggestion(from: response)
        
        // Track this suggestion for variety
        trackSuggestion(suggestion)
        
        let sourceType = shouldSelectFromLibrary ? "library" : "general"
        print("🤖 ChatGPT generated starting song: '\(suggestion.songTitle)' by \(suggestion.artist) (mood: \(suggestion.mood.rawValue), source: \(sourceType))")
        
        return suggestion
    }
    
    func generateIntervalChangeSuggestion(
        context: MusicContext,
        userPreferences: MusicPreferences,
        currentDistance: Double,
        currentTime: TimeInterval,
        upcomingIntensity: Intensity?
    ) async throws -> MusicSuggestion {
        guard isConfigured else {
            throw ChatGPTError.apiKeyNotSet
        }
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        // Configurable chance to select from user's library
        let shouldSelectFromLibrary = Double.random(in: 0...1) < librarySelectionProbability
        
        let prompt = buildIntervalChangePrompt(
            context: context,
            preferences: userPreferences,
            currentDistance: currentDistance,
            currentTime: currentTime,
            upcomingIntensity: upcomingIntensity,
            preferLibrarySelection: shouldSelectFromLibrary
        )
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: buildSystemPrompt()),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: 0.7
        )
        
        let response = try await makeAPIRequestWithRetry(request)
        
        let suggestion = try parseMusicSuggestion(from: response)
        
        // Track this suggestion for variety
        trackSuggestion(suggestion)
        
        let sourceType = shouldSelectFromLibrary ? "library" : "general"
        print("🤖 ChatGPT generated interval song: '\(suggestion.songTitle)' by \(suggestion.artist) (mood: \(suggestion.mood.rawValue), source: \(sourceType))")
        
        return suggestion
    }
    
    func generateWorkoutMotivation(
        currentSegment: RunSegment,
        progress: Double,
        heartRate: Int?
    ) async throws -> String {
        guard isConfigured else {
            throw ChatGPTError.apiKeyNotSet
        }
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        let prompt = buildMotivationPrompt(
            segment: currentSegment,
            progress: progress,
            heartRate: heartRate
        )
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: "You are a motivational running coach. Provide short, encouraging messages to help runners push through their workouts."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 100,
            temperature: 0.8
        )
        
        let response = try await makeAPIRequestWithRetry(request)
        
        guard let choice = response.choices.first else {
            throw ChatGPTError.invalidResponse
        }
        
        return choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private Methods
    
    private func buildSystemPrompt() -> String {
        return """
        You are a music curator for running workouts. Suggest songs based on workout intensity and user preferences.
        
        Respond in this JSON format:
        {
            "songTitle": "Song Name",
            "artist": "Artist Name", 
            "reason": "Brief reason",
            "mood": "energetic|intense|chill|motivational|calming|upbeat",
            "confidence": 0.8
        }
        """
    }
    
    private func buildStartingSongPrompt(
        workoutPlan: [RunSegment],
        preferences: MusicPreferences,
        currentIntensity: Intensity,
        preferLibrarySelection: Bool = false
    ) -> String {
        let workoutDescription = buildWorkoutPlanDescription(workoutPlan)
        let musicPreferences = buildMusicPreferencesDescription(preferences)
        let effortMood = getEffortMoodMapping(currentIntensity)
        
        let libraryInstruction = if preferLibrarySelection {
            """
            
            IMPORTANT: You MUST select a song from my music library. Choose from my favorite artists or genres. If I have no favorites, suggest a popular song that matches my workout context.
            """
        } else {
            """
            
            You can suggest any song that matches my workout context, whether from my library or Apple Music catalog. Consider my preferences but feel free to suggest popular songs that would work well for starting my workout. If the song isn't in my library, we can search for it on Apple Music.
            """
        }
        
        // Build heart rate guidance for starting song
        let heartRateGuidance = buildStartingSongHeartRateGuidance(intensity: currentIntensity)
        
        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance()
        
        return """
        I am starting an outdoor run. My plan is to \(workoutDescription). My music preferences are \(musicPreferences). Find a popular, motivating song to get me started. With this being a \(currentIntensity.label) effort, make this a \(effortMood) song.\(heartRateGuidance)\(varietyGuidance)\(libraryInstruction)
        
        Choose a song that will:
        - Get me pumped up and ready to run
        - Match the energy level for a \(currentIntensity.label) effort
        - Be from my favorite artists or genres (if selecting from library)
        - Set the perfect tone for my workout
        - Help me get into my target heart rate zone for \(currentIntensity.label) effort
        - Add variety to keep my playlist fresh and engaging
        """
    }
    
    private func buildIntervalChangePrompt(
        context: MusicContext,
        preferences: MusicPreferences,
        currentDistance: Double,
        currentTime: TimeInterval,
        upcomingIntensity: Intensity?,
        preferLibrarySelection: Bool = false
    ) -> String {
        let heartRateInfo = if let current = context.currentHeartRate, let target = context.targetHeartRate {
            "My heart rate is currently \(current) BPM (target: \(target) BPM)"
        } else {
            "My heart rate is currently unknown"
        }
        
        let effortAnalysis = analyzeHeartRateVsEffort(
            currentHeartRate: context.currentHeartRate,
            targetHeartRate: context.targetHeartRate,
            currentIntensity: context.currentIntensity,
            upcomingIntensity: upcomingIntensity
        )
        
        let musicPreferences = buildMusicPreferencesDescription(preferences)
        
        let libraryInstruction = if preferLibrarySelection {
            """
            
            IMPORTANT: You MUST select a song from my music library. Choose from my favorite artists or genres. If I have no favorites, suggest a popular song that matches my workout context.
            """
        } else {
            """
            
            You can suggest any song that matches my workout context, whether from my library or Apple Music catalog. Consider my preferences but feel free to suggest popular songs that would work well for this moment. If the song isn't in my library, we can search for it on Apple Music.
            """
        }
        
        // Build heart rate zone guidance for interval changes
        let heartRateGuidance = buildHeartRateGuidance(context: context)
        
        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance()
        
        return """
        My current run stats are that I have run \(String(format: "%.2f", currentDistance)) kilometers in \(currentTime.formattedTime()). \(heartRateInfo). The \(upcomingIntensity?.label ?? context.currentIntensity.label) effort is \(upcomingIntensity?.label ?? context.currentIntensity.label). \(effortAnalysis) Based on my preferences (\(musicPreferences)), suggest the next song and fade it in.\(heartRateGuidance)\(varietyGuidance)\(libraryInstruction)
        
        CRITICAL: Heart rate zone management is the top priority. Choose a song that will help me achieve or maintain my target heart rate zone.
        
        Choose a song that will:
        - Help me \(effortAnalysis.lowercased())
        - Match the upcoming \(upcomingIntensity?.label ?? context.currentIntensity.label) intensity
        - Keep me motivated and in the zone
        - Transition smoothly from my current state
        - MOST IMPORTANTLY: Help me get into or stay in my target heart rate zone
        - Add variety to keep the playlist fresh and engaging
        """
    }
    
    private func buildMusicSuggestionPrompt(context: MusicContext, preferences: MusicPreferences, preferLibrarySelection: Bool = false) -> String {
        let heartRateInfo = if let current = context.currentHeartRate, let target = context.targetHeartRate {
            "Current heart rate: \(current) BPM, Target: \(target) BPM (\(context.heartRateZone.description))"
        } else {
            "Heart rate: Unknown"
        }
        
        let activityInfo = if let distance = context.currentDistance, let pace = context.currentPace {
            "Distance: \(String(format: "%.1f", distance))m, Pace: \(String(format: "%.1f", pace * 3.6)) km/h"
        } else {
            "Activity: Unknown"
        }
        
        let favoriteArtists = preferences.favoriteArtists.map { $0.name }.joined(separator: ", ")
        let favoriteGenres = preferences.favoriteGenres.filter { $0.isSelected }.map { $0.name }.joined(separator: ", ")
        
        // Build adaptive music guidance
        let adaptiveGuidance = if context.shouldAdjustMusic {
            """
            
            IMPORTANT: The user's actual workout intensity (\(context.actualWorkoutIntensity.displayName)) doesn't match their planned intensity (\(context.currentIntensity.label)).
            
            Music adjustment needed:
            \(buildAdaptiveMusicGuidance(context: context))
            """
        } else {
            ""
        }
        
        let libraryInstruction = if preferLibrarySelection {
            """
            
            IMPORTANT: You MUST select a song from the user's music library. Choose from their favorite artists: \(favoriteArtists.isEmpty ? "None specified" : favoriteArtists) or favorite genres: \(favoriteGenres.isEmpty ? "None specified" : favoriteGenres). If they have no favorites, suggest a popular song that matches their workout context.
            """
        } else {
            """
            
            You can suggest any song that matches the workout context, whether from their library or Apple Music catalog. Consider their preferences but feel free to suggest popular songs that would work well for this moment. If the song isn't in their library, we can search for it on Apple Music.
            """
        }
        
        // Build heart rate zone guidance
        let heartRateGuidance = buildHeartRateGuidance(context: context)
        
        // Build variety guidance
        let varietyGuidance = buildVarietyGuidance()
        
        return """
        Current workout context:
        - Planned intensity: \(context.currentIntensity.label)
        - Actual intensity: \(context.actualWorkoutIntensity.displayName) (\(context.actualWorkoutIntensity.description))
        - \(heartRateInfo)
        - \(activityInfo)
        - Time remaining in segment: \(Int(context.timeRemainingInSegment)) seconds
        - Current song ending in: \(context.currentSongEndingIn.map { "\(Int($0)) seconds" } ?? "Unknown")
        - User is actively exercising: \(context.isActive ? "Yes" : "No")
        
        User's music preferences:
        - Favorite artists: \(favoriteArtists.isEmpty ? "None specified" : favoriteArtists)
        - Favorite genres: \(favoriteGenres.isEmpty ? "None specified" : favoriteGenres)
        - Preferred mood for \(context.currentIntensity.label): \(preferences.preferredMoodForIntensity[context.currentIntensity]?.displayName ?? "Not set")
        
        Recent songs: \(context.recentSongs.map { "\($0.title) by \($0.artist)" }.joined(separator: ", "))\(adaptiveGuidance)\(heartRateGuidance)\(varietyGuidance)\(libraryInstruction)
        
        CRITICAL: The most important factor is heart rate zone management. Choose a song that will help the user maintain or achieve their target heart rate zone for optimal workout performance.
        
        Suggest the perfect next song for this moment in their workout. Prioritize heart rate zone management above all other factors, but also consider variety to keep the playlist fresh and engaging.
        """
    }
    
    private func buildAdaptiveMusicGuidance(context: MusicContext) -> String {
        switch (context.currentIntensity, context.actualWorkoutIntensity) {
        case (.easy, .vigorous), (.easy, .maximum):
            return "User planned an easy workout but is working very hard (HR: \(context.currentHeartRate ?? 0) BPM). Suggest a CALMING, CHILL song to help them slow down and recover."
        case (.medium, .veryLight), (.medium, .light), (.hard, .veryLight), (.hard, .light):
            return "User planned a challenging workout but is moving slowly (HR: \(context.currentHeartRate ?? 0) BPM). Suggest an ENERGETIC, MOTIVATIONAL song to boost their energy and get them moving."
        case (.easy, .veryLight), (.easy, .light):
            return "User planned an easy workout and is moving slowly (HR: \(context.currentHeartRate ?? 0) BPM). Suggest an UPBEAT, ENERGETIC song to motivate them to pick up the pace."
        case (.easy, .resting):
            return "User planned an easy workout but appears to be resting (not moving much). Suggest an UPBEAT, MOTIVATIONAL song to get them started."
        default:
            return "User's actual intensity matches their planned intensity. Suggest music appropriate for their current state."
        }
    }
    
    private func buildMotivationPrompt(segment: RunSegment, progress: Double, heartRate: Int?) -> String {
        let heartRateText = heartRate.map { " (HR: \($0) BPM)" } ?? ""
        let progressPercent = Int(progress * 100)
        
        return """
        The runner is in a \(segment.intensity.label) segment, \(progressPercent)% complete\(heartRateText).
        Target: \(segment.targetDescription)
        
        Provide a short, motivational message to help them push through.
        """
    }
    
    private func buildRandomLibrarySongPrompt(preferences: MusicPreferences, intensity: Intensity) -> String {
        let favoriteArtists = preferences.favoriteArtists.map { $0.name }.joined(separator: ", ")
        let favoriteGenres = preferences.favoriteGenres.filter { $0.isSelected }.map { $0.name }.joined(separator: ", ")
        let favoriteSongs = preferences.favoriteSongs.map { "\($0.title) by \($0.artist)" }.joined(separator: ", ")
        
        return """
        I need a random song from my music library for a \(intensity.label) intensity workout.
        
        My music library includes:
        - Favorite artists: \(favoriteArtists.isEmpty ? "None specified" : favoriteArtists)
        - Favorite genres: \(favoriteGenres.isEmpty ? "None specified" : favoriteGenres)
        - Favorite songs: \(favoriteSongs.isEmpty ? "None specified" : favoriteSongs)
        
        Please select a random song from my library that would work well for a \(intensity.label) effort workout. Choose something that matches the energy level and would keep me motivated.
        
        If I have no favorites specified, suggest a popular song that would work well for this intensity level.
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
        var components: [String] = []
        
        if !preferences.favoriteArtists.isEmpty {
            let artists = preferences.favoriteArtists.map { $0.name }.joined(separator: ", ")
            components.append("favorite artists: \(artists)")
        }
        
        if !preferences.favoriteSongs.isEmpty {
            let songs = preferences.favoriteSongs.map { "\($0.title) by \($0.artist)" }.joined(separator: ", ")
            components.append("favorite songs: \(songs)")
        }
        
        let selectedGenres = preferences.favoriteGenres.filter { $0.isSelected }.map { $0.name }
        if !selectedGenres.isEmpty {
            components.append("favorite genres: \(selectedGenres.joined(separator: ", "))")
        }
        
        return components.isEmpty ? "no specific preferences set" : components.joined(separator: ", ")
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
        
        // Define specific heart rate zones for each intensity
        let (minHR, maxHR, _) = getHeartRateZone(for: intensity)
        
        if current < minHR {
            return "My heart rate is too low (\(current) BPM) for \(intensity.label) effort (target: \(minHR)-\(maxHR) BPM). I need an energetic, up-tempo song to increase my heart rate and get into the proper zone."
        } else if current > maxHR {
            return "My heart rate is too high (\(current) BPM) for \(intensity.label) effort (target: \(minHR)-\(maxHR) BPM). I need a calmer, more relaxed song to lower my heart rate and get back into the proper zone."
        } else {
            return "My heart rate is perfect (\(current) BPM) for \(intensity.label) effort (target: \(minHR)-\(maxHR) BPM). I need a song that maintains this optimal zone."
        }
    }
    
    private func getHeartRateZone(for intensity: Intensity) -> (min: Int, max: Int, name: String) {
        switch intensity {
        case .easy:
            return (100, 140, "Easy Zone")
        case .medium:
            return (120, 160, "Medium Zone")
        case .hard:
            return (130, 180, "Hard Zone")
        }
    }
    
    private func buildHeartRateGuidance(context: MusicContext) -> String {
        guard let currentHR = context.currentHeartRate else {
            return ""
        }
        
        let (minHR, maxHR, _) = getHeartRateZone(for: context.currentIntensity)
        
        if currentHR < minHR {
            return """
            
            🚨 HEART RATE TOO LOW: Current HR is \(currentHR) BPM, but target for \(context.currentIntensity.label) effort is \(minHR)-\(maxHR) BPM.
            MUSIC STRATEGY: Choose an energetic, high-tempo, motivating song that will increase heart rate and get them into the proper zone. Think upbeat, driving beats, motivational lyrics.
            """
        } else if currentHR > maxHR {
            return """
            
            🚨 HEART RATE TOO HIGH: Current HR is \(currentHR) BPM, but target for \(context.currentIntensity.label) effort is \(minHR)-\(maxHR) BPM.
            MUSIC STRATEGY: Choose a calmer, more relaxed song that will help lower heart rate and get them back into the proper zone. Think steady, calming beats, less intense energy.
            """
        } else {
            return """
            
            ✅ HEART RATE PERFECT: Current HR is \(currentHR) BPM, which is ideal for \(context.currentIntensity.label) effort (target: \(minHR)-\(maxHR) BPM).
            MUSIC STRATEGY: Choose a song that maintains this optimal zone - match the energy level to keep them in this sweet spot.
            """
        }
    }
    
    private func buildStartingSongHeartRateGuidance(intensity: Intensity) -> String {
        let (minHR, maxHR, _) = getHeartRateZone(for: intensity)
        
        return """
        
        🎯 TARGET HEART RATE ZONE: For \(intensity.label) effort, I need to get into the \(minHR)-\(maxHR) BPM range.
        MUSIC STRATEGY: Choose a song that will help me gradually build up to my target heart rate zone. The song should match the energy level needed for \(intensity.label) effort.
        """
    }
    
    // MARK: - Variety Management
    
    private func trackSuggestion(_ suggestion: MusicSuggestion) {
        let suggestionKey = "\(suggestion.artist) - \(suggestion.songTitle)"
        recentSuggestions.append(suggestionKey)
        
        // Keep only the most recent suggestions
        if recentSuggestions.count > maxRecentSuggestions {
            recentSuggestions.removeFirst()
        }
        
        print("📝 Tracked suggestion: \(suggestionKey) (Recent: \(recentSuggestions.count))")
    }
    
    private func buildVarietyGuidance() -> String {
        guard !recentSuggestions.isEmpty else {
            return ""
        }
        
        let recentArtists = recentSuggestions.map { suggestion in
            suggestion.components(separatedBy: " - ").first ?? suggestion
        }
        
        let uniqueArtists = Set(recentArtists)
        
        if uniqueArtists.count <= 2 {
            return """
            
            🎵 VARIETY REQUEST: I've been getting a lot of songs from \(uniqueArtists.joined(separator: " and ")) recently. Please suggest a different artist to add variety to my workout playlist. I want to keep things fresh and exciting!
            """
        }
        
        return ""
    }
    
    // Public method to clear variety tracking (useful for new workouts)
    func clearVarietyTracking() {
        recentSuggestions.removeAll()
        print("🔄 Cleared variety tracking - starting fresh")
    }
    
    private func makeAPIRequestWithRetry(_ request: ChatGPTRequest, maxRetries: Int = 2) async throws -> ChatGPTResponse {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                print("🔄 ChatGPT attempt \(attempt + 1)/\(maxRetries + 1)")
                return try await makeAPIRequest(request)
            } catch {
                lastError = error
                print("❌ Attempt \(attempt + 1) failed: \(error)")
                
                if attempt < maxRetries {
                    // Wait before retrying (exponential backoff)
                    let delay = Double(attempt + 1) * 2.0
                    print("⏳ Waiting \(delay) seconds before retry...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? ChatGPTError.networkError(NSError(domain: "RetryFailed", code: -1, userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"]))
    }
    
    private func makeAPIRequest(_ request: ChatGPTRequest) async throws -> ChatGPTResponse {
        guard let url = URL(string: baseURL) else {
            throw ChatGPTError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add timeout configuration
        urlRequest.timeoutInterval = 20.0 // 20 second timeout
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw ChatGPTError.encodingFailed
        }
        
        do {
            // Use withTimeout to add additional timeout protection
            let (data, response) = try await withTimeout(seconds: 25) {
                try await URLSession.shared.data(for: urlRequest)
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatGPTError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ChatGPTError.apiError(httpResponse.statusCode, errorMessage)
            }
            
            do {
                return try JSONDecoder().decode(ChatGPTResponse.self, from: data)
            } catch {
                throw ChatGPTError.decodingFailed
            }
        } catch {
            if error is ChatGPTError {
                throw error
            } else if error is TimeoutError {
                throw ChatGPTError.networkError(error)
            } else {
                throw ChatGPTError.networkError(error)
            }
        }
    }
    
    // Helper function for timeout handling
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private func parseMusicSuggestion(from response: ChatGPTResponse) throws -> MusicSuggestion {
        guard let choice = response.choices.first else {
            throw ChatGPTError.invalidResponse
        }
        
        let content = choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse JSON response
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let songTitle = json["songTitle"] as? String,
           let artist = json["artist"] as? String,
           let reason = json["reason"] as? String,
           let moodString = json["mood"] as? String,
           let mood = MusicMood(rawValue: moodString),
           let confidence = json["confidence"] as? Double {
            
            return MusicSuggestion(
                songTitle: songTitle,
                artist: artist,
                reason: reason,
                mood: mood,
                confidence: confidence
            )
        }
        
        // Fallback: try to extract information from text response
        return try parseMusicSuggestionFromText(content)
    }
    
    private func parseMusicSuggestionFromText(_ text: String) throws -> MusicSuggestion {
        // Simple text parsing as fallback
        let lines = text.components(separatedBy: .newlines)
        
        var songTitle = "Unknown Song"
        var artist = "Unknown Artist"
        var reason = "AI suggested this song for your workout"
        let mood = MusicMood.energetic
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("song:") || lowercased.contains("title:") {
                songTitle = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Song"
            } else if lowercased.contains("artist:") || lowercased.contains("by:") {
                artist = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Artist"
            } else if lowercased.contains("reason:") || lowercased.contains("why:") {
                reason = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI suggested this song"
            }
        }
        
        return MusicSuggestion(
            songTitle: songTitle,
            artist: artist,
            reason: reason,
            mood: mood,
            confidence: 0.6
        )
    }
    
    // MARK: - Motivational Speech Generation
    
    func generateMotivationalSpeech(workoutPlan: [RunSegment]) async throws -> String {
        guard isConfigured else {
            throw ChatGPTError.apiKeyNotSet
        }
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        let workoutSummary = buildWorkoutSummary(workoutPlan)
        let prompt = buildMotivationalSpeechPrompt(workoutSummary: workoutSummary)
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: "You are a motivational running coach. Provide short, inspiring speeches to prepare runners for their workouts."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 150,
            temperature: 0.8
        )
        
        let response = try await makeAPIRequestWithRetry(request)
        
        guard let choice = response.choices.first else {
            throw ChatGPTError.invalidResponse
        }
        
        return choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    // MARK: - Workout Motivation Generation
    
    func generateWorkoutMotivation(
        segmentChange: Bool,
        distanceMilestone: Bool,
        currentIntensity: Intensity,
        heartRate: Int?,
        totalDistance: Double
    ) async throws -> String {
        let prompt = buildWorkoutMotivationPrompt(
            segmentChange: segmentChange,
            distanceMilestone: distanceMilestone,
            currentIntensity: currentIntensity,
            heartRate: heartRate,
            totalDistance: totalDistance
        )
        
        let request = ChatGPTRequest(
            model: defaultModel,
            messages: [
                ChatMessage(role: "system", content: "You are a motivational running coach. Provide very short, encouraging messages during workouts. Keep it under 15 words."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 50,
            temperature: 0.8
        )
        
        let response = try await makeAPIRequestWithRetry(request)
        
        guard let choice = response.choices.first else {
            throw ChatGPTError.invalidResponse
        }
        
        return choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
        Give a short motivational message for this workout moment:
        \(context)
        
        Keep it under 15 words. Be encouraging and mention the effort level or milestone.
        """
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
            return (100, 140)
        case .medium:
            return (120, 160)
        case .hard:
            return (130, 180)
        }
    }
}

// MARK: - ChatGPT Errors
enum ChatGPTError: LocalizedError {
    case apiKeyNotSet
    case invalidURL
    case encodingFailed
    case decodingFailed
    case networkError(Error)
    case apiError(Int, String)
    case invalidResponse
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotSet:
            return "OpenAI API key is not set. Please configure it in settings."
        case .invalidURL:
            return "Invalid API URL"
        case .encodingFailed:
            return "Failed to encode request"
        case .decodingFailed:
            return "Failed to decode response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        case .invalidResponse:
            return "Invalid response from ChatGPT"
        case .timeout:
            return "Request timed out. Please check your internet connection and try again."
        }
    }
}

// MARK: - Extensions
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
