import Foundation
import MediaPlayer
import MusicKit
import AVFoundation
import Combine

// MARK: - Music Playback Manager
@MainActor
final class MusicPlaybackManager: ObservableObject {
    static let shared = MusicPlaybackManager()
    
    @Published var isPlaying = false
    @Published var currentSong: MusicSong?
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var currentSongDuration: TimeInterval = 0
    @Published var isGeneratingSuggestion = false
    @Published var lastSuggestion: MusicSuggestion?
    @Published var playbackError: Error?
    @Published var playbackStateDescription = "stopped"

    /// When true, WorkoutMusicCoordinator is driving song generation.
    /// The playback manager will NOT auto-generate songs on playback end / now-playing change.
    /// Only the crossfade timer will still trigger generation as a safety net.
    var coordinatorDriven = false

    private let aiService = MusicAIService.shared
    private let profileManager = UserProfileManager.shared
    /// Single player for both library and Apple Music so state and observers stay in sync
    private var musicPlayer: MPMusicPlayerController
    private var playbackTimer: Timer?
    private var suggestionTimer: Timer?
    private var currentWorkoutContext: WorkoutContext?
    private var lastSuggestionTime: Date = Date.distantPast
    private var hasConfiguredPlaybackAudioSession = false
    /// Track last song ID to suppress duplicate nowPlayingItemChanged notifications
    private var lastReportedSongID: String?
    
    /// Crossfade: start next song this many seconds before current ends (avoids gap; no true overlap with system player)
    private var crossfadeDuration: TimeInterval { profileManager.userProfile.musicPreferences.crossfadeDuration }

    var hasLibraryAccess: Bool {
        MPMediaLibrary.authorizationStatus() == .authorized
    }

    var hasCatalogAccess: Bool {
        MusicKitService.shared.isAuthorized
    }

    var hasAvailablePlaybackSource: Bool {
        hasLibraryAccess || hasCatalogAccess
    }

    @discardableResult
    func playEmergencyFallback(
        preferences: MusicPreferences,
        intensity: Intensity,
        avoiding avoidedSongKeys: Set<String>
    ) async -> MusicSuggestion? {
        if hasLibraryAccess, let fallbackItem = bestLibraryFallbackItem(
            preferences: preferences,
            avoiding: avoidedSongKeys
        ) {
            let suggestion = MusicSuggestion(
                songTitle: fallbackItem.title ?? "Unknown",
                artist: fallbackItem.artist ?? "Unknown",
                reason: "Using a reliable song from the runner's library to keep the workout moving after a generated suggestion missed.",
                mood: MusicRecommendationPolicy.defaultMood(for: intensity),
                confidence: 0.58
            )

            if await playSong(fallbackItem) {
                lastSuggestion = suggestion
                return suggestion
            }
        }

        guard hasCatalogAccess else {
            return nil
        }

        let fallbackSuggestion = aiService.fallbackSuggestion(
            preferences: preferences,
            intensity: intensity,
            avoiding: avoidedSongKeys
        ).cleanedTitle()

        guard !avoidedSongKeys.contains(fallbackSuggestion.sessionSongKey) else {
            return nil
        }

        if await playAppleMusicSuggestion(fallbackSuggestion) {
            lastSuggestion = fallbackSuggestion
            return fallbackSuggestion
        }

        return nil
    }
    
    // MARK: - Apple Music Integration (catalog playback when not in library)
    
    @discardableResult
    func playAppleMusicSuggestion(_ suggestion: MusicSuggestion) async -> Bool {
        configureAudioSession()

        guard hasCatalogAccess else {
            updatePlaybackFailure(MusicError.catalogAccessRequired, state: "enable Apple Music playback")
            return false
        }

        do {
            let songs = try await fetchCatalogCandidates(for: suggestion)

            guard let bestMatch = bestCatalogMatch(in: songs, for: suggestion) else {
                updatePlaybackFailure(MusicError.songUnavailable, state: "song unavailable")
                return false
            }

            try await MusicKitService.shared.playSong(bestMatch)
            applyAppleMusicNowPlaying(suggestion: suggestion, duration: bestMatch.duration)
            clearPlaybackFailure()
            return true
        } catch {
            print("❌ Apple Music search/playback error: \(error)")
            updatePlaybackFailure(error, state: "apple music playback failed")
            return false
        }
    }
    
    /// Keep UI in sync after Apple Music starts (same player is observed, but initial state may lag)
    private func applyAppleMusicNowPlaying(suggestion: MusicSuggestion, duration: TimeInterval?) {
        currentSong = MusicSong(
            id: suggestion.id.uuidString,
            title: suggestion.songTitle,
            artist: suggestion.artist,
            album: nil,
            artwork: nil,
            duration: duration ?? 0
        )
        currentSongDuration = duration ?? 0
        currentPlaybackTime = 0
        isPlaying = true
        playbackStateDescription = "playing"
        playbackError = nil
        startPlaybackTimer()
    }

    private func fetchCatalogCandidates(for suggestion: MusicSuggestion) async throws -> [Song] {
        let primaryQuery = "\(suggestion.songTitle) \(suggestion.artist)"
        let primaryResults = try await MusicKitService.shared.searchSongs(query: primaryQuery, limit: 10)
        if bestCatalogMatch(in: primaryResults, for: suggestion) != nil {
            return primaryResults
        }

        var seenSongIDs = Set<String>()
        var combinedResults: [Song] = []

        for song in primaryResults {
            let storeID = song.id.rawValue
            if seenSongIDs.insert(storeID).inserted {
                combinedResults.append(song)
            }
        }

        let searchQueries = [
            suggestion.songTitle,
            "\(suggestion.artist) \(suggestion.songTitle)"
        ]

        for query in searchQueries {
            let songs = try await MusicKitService.shared.searchSongs(query: query, limit: 10)

            for song in songs {
                let storeID = song.id.rawValue
                if seenSongIDs.insert(storeID).inserted {
                    combinedResults.append(song)
                }
            }
        }

        return combinedResults
    }

    private func clearPlaybackFailure() {
        playbackError = nil
        if !isPlaying {
            playbackStateDescription = "stopped"
        }
    }

    private func updatePlaybackFailure(_ error: Error, state: String) {
        playbackError = error
        playbackStateDescription = state
        isPlaying = musicPlayer.playbackState == .playing
    }

    private func bestLibraryFallbackItem(
        preferences: MusicPreferences,
        avoiding avoidedSongKeys: Set<String>
    ) -> MPMediaItem? {
        guard let items = MPMediaQuery.songs().items, !items.isEmpty else {
            return nil
        }

        let favoriteSongKeys = Set(preferences.allFavoriteSongs.map(\.sessionSongKey))
        let favoriteArtists = Set(preferences.favoriteArtists.map { $0.name.normalizedMusicIdentity })
        let importedArtists = Set(preferences.importedPlaylistArtists.map { $0.name.normalizedMusicIdentity })
        let selectedGenres = Set(
            preferences.allFavoriteGenres
                .filter(\.isSelected)
                .map { $0.name.normalizedMusicIdentity }
        )

        let scoredItems = items.compactMap { item -> (item: MPMediaItem, score: Int)? in
            guard let title = item.title, let artist = item.artist else {
                return nil
            }

            let songKey = "\(artist.normalizedMusicIdentity)|\(title.normalizedMusicIdentity)"
            guard !avoidedSongKeys.contains(songKey) else {
                return nil
            }

            var score = 0

            if favoriteSongKeys.contains(songKey) {
                score += 300
            }

            let normalizedArtist = artist.normalizedMusicIdentity
            if favoriteArtists.contains(normalizedArtist) {
                score += 180
            }
            if importedArtists.contains(normalizedArtist) {
                score += 120
            }

            if let genre = item.genre?.normalizedMusicIdentity, selectedGenres.contains(genre) {
                score += 90
            }

            score += min(item.playCount, 40)

            if item.playbackDuration >= 90, item.playbackDuration <= 480 {
                score += 10
            }

            return (item, score)
        }

        let sortedItems = scoredItems.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.item.playCount > rhs.item.playCount
            }
            return lhs.score > rhs.score
        }

        if let topScore = sortedItems.first?.score, topScore > 0 {
            let strongestMatches = sortedItems
                .prefix { $0.score == topScore }
                .map(\.item)

            return strongestMatches.randomElement() ?? sortedItems.first?.item
        }

        let anyAvailableSongs = items.filter { item in
            guard let title = item.title, let artist = item.artist else {
                return false
            }
            let songKey = "\(artist.normalizedMusicIdentity)|\(title.normalizedMusicIdentity)"
            return !avoidedSongKeys.contains(songKey)
        }

        return anyAvailableSongs.randomElement()
    }
    
    // MARK: - Matching Helpers
    private func normalize(_ text: String) -> String {
        text.normalizedMusicIdentity
    }

    private func scoreMatch(itemTitle: String, itemArtist: String, sugTitle: String, sugArtist: String) -> Int {
        let nt = normalize(itemTitle)
        let na = normalize(itemArtist)
        let st = normalize(sugTitle)
        let sa = normalize(sugArtist)
        var score = 0
        if nt == st { score += 3 }
        else if nt.contains(st) || st.contains(nt) { score += 2 }
        if na == sa { score += 3 }
        else if na.contains(sa) || sa.contains(na) { score += 1 }
        return score
    }

    private func isGoodEnough(score: Int) -> Bool {
        // Require reasonably strong match
        return score >= 5
    }

    private func bestCatalogMatch(in songs: [Song], for suggestion: MusicSuggestion) -> Song? {
        let exactMatch = songs.first { song in
            normalize(song.title) == normalize(suggestion.songTitle) &&
            normalize(song.artistName) == normalize(suggestion.artist)
        }
        if let exactMatch = exactMatch {
            return exactMatch
        }

        var bestSong: Song?
        var bestScore = 0

        for song in songs {
            let score = scoreMatch(
                itemTitle: song.title,
                itemArtist: song.artistName,
                sugTitle: suggestion.songTitle,
                sugArtist: suggestion.artist
            )

            if score > bestScore {
                bestScore = score
                bestSong = song
            }
        }

        guard let bestSong, isGoodEnough(score: bestScore) else {
            return nil
        }

        return bestSong
    }
    
    private init() {
        // Use applicationQueuePlayer for both library and Apple Music so one observer sees all playback
        musicPlayer = MPMusicPlayerController.applicationQueuePlayer
        setupMusicPlayer()
        musicPlayer.repeatMode = .none
        musicPlayer.shuffleMode = .off
    }
    
    // MARK: - Setup
    
    private func setupMusicPlayer() {
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: musicPlayer
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: musicPlayer
        )
        
        // Listen for playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackDidEnd),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: musicPlayer
        )
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            if !hasConfiguredPlaybackAudioSession || session.category != .playback {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
            hasConfiguredPlaybackAudioSession = true
        } catch {
            hasConfiguredPlaybackAudioSession = false
            print("Failed to configure playback audio session: \(error)")
        }
    }
    
    // MARK: - Workout Integration
    
    func startWorkoutMusic(workoutContext: WorkoutContext) {
        configureAudioSession()
        currentWorkoutContext = workoutContext
        clearPlaybackFailure()

        // NOTE: Do NOT generate the initial song here.
        // WorkoutMusicCoordinator.startWorkoutMusic() calls generateStartingSong()
        // and then feeds the result back via playSuggestedSong(). Generating here too
        // would race for the AI generation lock and one request would be skipped.

        // Set up suggestion timer for crossfade/end-of-song transitions
        startSuggestionTimer()
    }
    
    func stopWorkoutMusic() {
        musicPlayer.stop()
        isPlaying = false
        currentSong = nil
        currentSongDuration = 0
        currentPlaybackTime = 0
        playbackStateDescription = "stopped"
        playbackError = nil
        currentWorkoutContext = nil
        lastReportedSongID = nil
        
        stopSuggestionTimer()
        stopPlaybackTimer()
    }
    
    func updateWorkoutContext(_ context: WorkoutContext) {
        currentWorkoutContext = context
    }
    
    // MARK: - Song Generation and Playback
    
    private func generateAndPlayStartingSong() async {
        guard let context = currentWorkoutContext else { return }

        isGeneratingSuggestion = true

        do {
            let suggestion = try await aiService.generateStartingSongSuggestion(
                workoutPlan: context.segments,
                userPreferences: profileManager.userProfile.musicPreferences,
                currentIntensity: context.currentSegment.intensity,
                mustUseLibrary: hasLibraryAccess && !hasCatalogAccess
            )

            await playSuggestedSong(suggestion)

        } catch {
            playbackError = error
            print("Failed to generate starting song: \(error)")
        }

        isGeneratingSuggestion = false
    }
    
    func generateNextSongSuggestion() async {
        guard let context = currentWorkoutContext else {
            return
        }

        isGeneratingSuggestion = true

        do {
            let suggestion = try await aiService.generateIntervalChangeSuggestion(
                context: context.musicContext,
                userPreferences: profileManager.userProfile.musicPreferences,
                currentDistance: context.totalDistance,
                currentTime: context.totalTime,
                upcomingIntensity: context.upcomingSegment?.intensity,
                mustUseLibrary: hasLibraryAccess && !hasCatalogAccess
            )

            await playSuggestedSong(suggestion)

        } catch {
            playbackError = error
            print("❌ Failed to generate next song: \(error)")
        }

        isGeneratingSuggestion = false
    }
    
    @discardableResult
    func playSuggestedSong(_ suggestion: MusicSuggestion) async -> Bool {
        // Clean up the song title — the AI sometimes appends "by Artist" to the title
        let cleanedSuggestion = suggestion.cleanedTitle()
        lastSuggestion = cleanedSuggestion

        if hasLibraryAccess {
            let foundInLibrary = await tryPlayFromLibrary(suggestion: cleanedSuggestion)
            if foundInLibrary {
                return true
            }
        }

        guard hasCatalogAccess else {
            if hasLibraryAccess {
                updatePlaybackFailure(MusicError.catalogAccessRequired, state: "enable Apple Music playback")
            } else {
                updatePlaybackFailure(MusicError.noPlayableMusicSource, state: "music access needed")
            }
            return false
        }

        // Not in library or library not authorized: play from Apple Music catalog
        return await playAppleMusicSuggestion(cleanedSuggestion)
    }
    
    /// Attempts to find and play the suggestion from the user's local library.
    /// Returns `true` if the song was found and playback started, `false` otherwise.
    @discardableResult
    private func tryPlayFromLibrary(suggestion: MusicSuggestion) async -> Bool {
        let titleQuery = MPMediaQuery.songs()
        let titlePredicate = MPMediaPropertyPredicate(
            value: suggestion.songTitle,
            forProperty: MPMediaItemPropertyTitle,
            comparisonType: .contains
        )
        titleQuery.addFilterPredicate(titlePredicate)

        if let items = titleQuery.items, !items.isEmpty {
            if let song = findBestSongMatch(items: items, suggestion: suggestion) {
                return await playSong(song)
            }
        }

        let artistQuery = MPMediaQuery.songs()
        let artistPredicate = MPMediaPropertyPredicate(
            value: suggestion.artist,
            forProperty: MPMediaItemPropertyArtist,
            comparisonType: .contains
        )
        artistQuery.addFilterPredicate(artistPredicate)

        if let artistItems = artistQuery.items, !artistItems.isEmpty {
            var bestItem: MPMediaItem?
            var bestScore = 0

            for item in artistItems {
                guard let title = item.title, let artist = item.artist else { continue }
                let score = scoreMatch(
                    itemTitle: title,
                    itemArtist: artist,
                    sugTitle: suggestion.songTitle,
                    sugArtist: suggestion.artist
                )
                if score > bestScore {
                    bestScore = score
                    bestItem = item
                }
            }

            if let bestItem, isGoodEnough(score: bestScore) {
                return await playSong(bestItem)
            }
        }

        return await tryFuzzySongSearch(suggestion)
    }
    
    private func findBestSongMatch(items: [MPMediaItem], suggestion: MusicSuggestion) -> MPMediaItem? {
        // First, try exact (normalized) match on title AND artist
        let exact = items.first { item in
            guard let t = item.title, let a = item.artist else { return false }
            return normalize(t) == normalize(suggestion.songTitle) && normalize(a) == normalize(suggestion.artist)
        }
        if let exact = exact { return exact }
        
        // Next, score all candidates and pick the highest-scoring one
        var bestItem: MPMediaItem?
        var bestScore = 0
        for item in items {
            guard let t = item.title, let a = item.artist else { continue }
            let s = scoreMatch(itemTitle: t, itemArtist: a, sugTitle: suggestion.songTitle, sugArtist: suggestion.artist)
            if s > bestScore {
                bestScore = s
                bestItem = item
            }
        }
        
        if let bestItem = bestItem, isGoodEnough(score: bestScore) {
            return bestItem
        }
        
        return nil
    }
    
    private func tryFuzzySongSearch(_ suggestion: MusicSuggestion) async -> Bool {
        // Get all songs and search manually for better matching
        let allSongsQuery = MPMediaQuery.songs()
        guard let allSongs = allSongsQuery.items, !allSongs.isEmpty else {
            return false
        }

        let matchingSongs = findFuzzyMatchesWithScores(in: allSongs, for: suggestion)

        guard let bestMatch = matchingSongs.first, isGoodEnough(score: bestMatch.score) else {
            return false
        }

        return await playSong(bestMatch.item)
    }
    
    private func findFuzzyMatches(in songs: [MPMediaItem], for suggestion: MusicSuggestion) -> [MPMediaItem] {
        return findFuzzyMatchesWithScores(in: songs, for: suggestion).map { $0.item }
    }

    private func findFuzzyMatchesWithScores(in songs: [MPMediaItem], for suggestion: MusicSuggestion) -> [(item: MPMediaItem, score: Int)] {
        let targetTitle = suggestion.songTitle.lowercased()
        let targetArtist = suggestion.artist.lowercased()

        var matches: [(item: MPMediaItem, score: Int)] = []

        for song in songs {
            guard let title = song.title?.lowercased(),
                  let artist = song.artist?.lowercased() else { continue }

            var score = 0
            var hasArtistMatch = false

            // Artist matching (required for any match)
            if artist == targetArtist {
                score += 50
                hasArtistMatch = true
            } else if artist.contains(targetArtist) || targetArtist.contains(artist) {
                score += 30
                hasArtistMatch = true
            }

            guard hasArtistMatch else { continue }

            // Title matching
            if title == targetTitle {
                score += 100
            } else if title.hasPrefix(targetTitle) {
                score += 80
            } else if targetTitle.hasPrefix(title) {
                score += 60
            } else {
                let titleWords = title.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)).filter { !$0.isEmpty }
                let targetWords = targetTitle.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)).filter { !$0.isEmpty }

                for targetWord in targetWords {
                    for titleWord in titleWords {
                        if titleWord == targetWord {
                            score += 25
                        } else if titleWord.hasPrefix(targetWord) || targetWord.hasPrefix(titleWord) {
                            score += 15
                        }
                    }
                }
            }

            if score > 30 {
                matches.append((song, score))
            }
        }

        return matches.sorted { $0.score > $1.score }
    }
    
    private func searchAndPlayByArtist(_ suggestion: MusicSuggestion) async -> Bool {
        
        let query = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(
            value: suggestion.artist,
            forProperty: MPMediaItemPropertyArtist,
            comparisonType: .contains
        )
        query.addFilterPredicate(predicate)
        
        if let items = query.items, !items.isEmpty {
            // Filter with scoring
            var bestItem: MPMediaItem?
            var bestScore = 0
            for item in items {
                guard let t = item.title, let a = item.artist else { continue }
                let s = scoreMatch(itemTitle: t, itemArtist: a, sugTitle: suggestion.songTitle, sugArtist: suggestion.artist)
                if s > bestScore {
                    bestScore = s
                    bestItem = item
                }
            }
            if let bestItem = bestItem, isGoodEnough(score: bestScore) {
                return await playSong(bestItem)
            } else {
                updatePlaybackFailure(MusicError.songUnavailable, state: "song unavailable")
                return false
            }
        } else {
            updatePlaybackFailure(MusicError.songUnavailable, state: "song unavailable")
            return false
        }
    }
    
    private func playRandomSong() async {
        
        if let allSongs = MPMediaQuery.songs().items, !allSongs.isEmpty {
            let randomSong = allSongs.randomElement()!
            await playSong(randomSong)
        } else {
            updatePlaybackFailure(MusicError.songUnavailable, state: "song unavailable")
        }
    }
    
    @discardableResult
    private func playSong(_ mediaItem: MPMediaItem) async -> Bool {
        configureAudioSession()
        
        // Check if the media item has required properties
        guard mediaItem.title != nil && mediaItem.artist != nil else {
            updatePlaybackFailure(MusicError.songUnavailable, state: "song unavailable")
            return false
        }
        
        
        let collection = MPMediaItemCollection(items: [mediaItem])
        let descriptor = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: collection)
        musicPlayer.setQueue(with: descriptor)
        
        
        
        // Try to start playback
        musicPlayer.play()
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let stateAfter = musicPlayer.playbackState
        
        // If still not playing, try a different approach
        if stateAfter != .playing {
            
            // Stop any current playback first
            musicPlayer.stop()
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            // Set the queue again and try playing
            musicPlayer.setQueue(with: descriptor)
            musicPlayer.play()
            
            // Wait a bit longer
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            let finalState = musicPlayer.playbackState
            
            if finalState != .playing {
                print("❌ Playback failed to start after multiple attempts. Final state: \(finalState.rawValue)")
                updatePlaybackFailure(MusicError.playbackFailed, state: "playback failed")
                return false
            }
        }
        
        // Update current song info
        currentSong = MusicSong(
            id: "\(mediaItem.persistentID)",
            title: mediaItem.title ?? "Unknown",
            artist: mediaItem.artist ?? "Unknown",
            album: mediaItem.albumTitle,
            artwork: nil,
            duration: mediaItem.playbackDuration
        )
        
        currentPlaybackTime = 0
        currentSongDuration = mediaItem.playbackDuration
        clearPlaybackFailure()
        playbackStateDescription = "playing"
        startPlaybackTimer()

        return true
    }
    
    // MARK: - Playback Control
    
    func playSongDirectly(_ mediaItem: MPMediaItem) async {
        _ = await playSong(mediaItem)
    }
    
    func play() {
        configureAudioSession()
        musicPlayer.play()
        playbackError = nil
        playbackStateDescription = "playing"
    }
    
    func pause() {
        musicPlayer.pause()
        playbackStateDescription = "paused"
    }
    
    func skipToNext() {
        musicPlayer.skipToNextItem()
    }
    
    func skipToPrevious() {
        musicPlayer.skipToPreviousItem()
    }
    
    func stop() {
        musicPlayer.stop()
        isPlaying = false
        currentSong = nil
        currentSongDuration = 0
        currentPlaybackTime = 0
        playbackStateDescription = "stopped"
        playbackError = nil
        lastReportedSongID = nil
    }
    
    /// System volume can't be set programmatically on iOS. Use MPVolumeView in your UI instead.
    /// This method is a no-op to maintain source compatibility.
    /// - Parameter volume: Desired volume (ignored on iOS)
    @available(iOS, unavailable, message: "Use MPVolumeView in UI to control system volume.")
    func setVolume(_ volume: Float) {
        // Intentionally left blank. MPMusicPlayerController.volume is unavailable on iOS.
    }
    
    // MARK: - Timers
    
    private func startSuggestionTimer() {
        stopSuggestionTimer()
        let interval: TimeInterval = 5.0
        suggestionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForNextSongSuggestion()
            }
        }
    }
    
    private func stopSuggestionTimer() {
        suggestionTimer?.invalidate()
        suggestionTimer = nil
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackTime()
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackTime() {
        currentPlaybackTime = musicPlayer.currentPlaybackTime
    }
    
    private func checkForNextSongSuggestion() async {
        // When coordinator is driving, it handles all song transitions via its own timers.
        // This timer serves as a safety net only for non-coordinator mode.
        guard !coordinatorDriven else { return }
        guard currentWorkoutContext != nil && !isGeneratingSuggestion else {
            return
        }

        // Check if we need a new song suggestion
        let timeRemainingInSong = currentSongDuration - currentPlaybackTime

        // Trigger next song at crossfade point (e.g. 4s before end) so transition happens before song ends
        let shouldGenerate = (timeRemainingInSong <= crossfadeDuration || currentSongDuration == 0 || currentSong == nil)

        if shouldGenerate {
            // Check if we've generated a suggestion recently to prevent rapid looping
            let timeSinceLastSuggestion = Date().timeIntervalSince(lastSuggestionTime)
            if timeSinceLastSuggestion > 15 { // 15 seconds minimum between suggestions
                lastSuggestionTime = Date()
                await generateNextSongSuggestion()
            }
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func playbackStateChanged() {
        isPlaying = musicPlayer.playbackState == .playing
        let nextState = switch musicPlayer.playbackState {
        case .playing:
            "playing"
        case .paused:
            "paused"
        default:
            "stopped"
        }
        if playbackError == nil || nextState == "playing" || nextState == "paused" {
            playbackStateDescription = nextState
        }
    }
    
    @objc private func playbackDidEnd() {
        // When the coordinator is driving, don't auto-generate — it handles song transitions
        guard !coordinatorDriven else {
            return
        }

        // Check if playback stopped and we're in a workout
        if musicPlayer.playbackState == .stopped && currentWorkoutContext != nil && !isGeneratingSuggestion {
            let timeSinceLastSuggestion = Date().timeIntervalSince(lastSuggestionTime)
            if timeSinceLastSuggestion > 10 { // 10 seconds minimum between suggestions
                lastSuggestionTime = Date()
                Task {
                    await generateNextSongSuggestion()
                }
            }
        }
    }
    
    @objc private func nowPlayingItemChanged() {
        if let nowPlayingItem = musicPlayer.nowPlayingItem {
            let songID = "\(nowPlayingItem.persistentID)"

            // Suppress duplicate notifications for the same song
            guard songID != lastReportedSongID else { return }
            lastReportedSongID = songID

            currentSong = MusicSong(
                id: songID,
                title: nowPlayingItem.title ?? "Unknown",
                artist: nowPlayingItem.artist ?? "Unknown",
                album: nowPlayingItem.albumTitle,
                artwork: nil,
                duration: nowPlayingItem.playbackDuration
            )
            currentSongDuration = nowPlayingItem.playbackDuration
            clearPlaybackFailure()
        } else {
            lastReportedSongID = nil
            currentSong = nil
            currentSongDuration = 0
            if playbackError == nil {
                playbackStateDescription = "stopped"
            }

            // When the coordinator is driving, don't auto-generate — it handles song transitions
            guard !coordinatorDriven else { return }

            // Only generate next song if we're in a workout AND not already generating a suggestion
            // AND the playback state indicates the song actually ended (not just paused)
            // AND we haven't generated a suggestion recently
            if currentWorkoutContext != nil && !isGeneratingSuggestion && musicPlayer.playbackState == .stopped {
                let timeSinceLastSuggestion = Date().timeIntervalSince(lastSuggestionTime)
                if timeSinceLastSuggestion > 10 { // 10 seconds minimum between suggestions
                    lastSuggestionTime = Date()
                    Task {
                        await generateNextSongSuggestion()
                    }
                }
            }
        }
    }
    
    // MARK: - Music Fade Controls
    
    func fadeOutMusic() {
        // For MPMusicPlayerController, we can't directly control volume
        // We'll use a subtle approach - brief pause during speech
        musicPlayer.pause()
    }
    
    func fadeInMusic() {
        // Resume music after speech
        musicPlayer.play()
    }
    
    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopSuggestionTimer()
        stopPlaybackTimer()
    }
}

// MARK: - Workout Context
struct WorkoutContext {
    let segments: [RunSegment]
    let currentSegmentIndex: Int
    let currentSegment: RunSegment
    let upcomingSegment: RunSegment?
    let totalDistance: Double
    let totalTime: TimeInterval
    let musicContext: MusicContext
    
    @MainActor
    init(
        segments: [RunSegment],
        currentSegmentIndex: Int,
        totalDistance: Double,
        totalTime: TimeInterval,
        heartRate: Int?,
        smoothedHeartRate: Int?,
        heartRateTrend: HeartRateTrend,
        hasStableHeartRateSignal: Bool,
        targetHeartRate: Int?,
        currentSongEndingIn: TimeInterval?,
        recentSongs: [MusicSong]
    ) {
        self.segments = segments
        self.currentSegmentIndex = min(currentSegmentIndex, segments.count - 1)
        self.currentSegment = segments[self.currentSegmentIndex]
        self.upcomingSegment = self.currentSegmentIndex + 1 < segments.count ? segments[self.currentSegmentIndex + 1] : nil
        self.totalDistance = totalDistance
        self.totalTime = totalTime
        
        // Calculate current speed in km/h. totalDistance is tracked in km.
        let currentPace = totalTime > 0 ? (totalDistance / totalTime) * 3600.0 : nil
        
        // Determine if user is actively exercising based on distance and time
        let isActive = totalDistance > 0.01 && totalTime > 30 // At least 10 meters in 30 seconds
        
        self.musicContext = MusicContext(
            currentHeartRate: heartRate,
            guidanceHeartRate: smoothedHeartRate,
            targetHeartRate: targetHeartRate,
            heartRateTrend: heartRateTrend,
            hasStableHeartRateSignal: hasStableHeartRateSignal,
            currentIntensity: currentSegment.intensity,
            timeRemainingInSegment: currentSegment.targetDuration,
            currentSongEndingIn: currentSongEndingIn,
            userPreferences: UserProfileManager.shared.userProfile.musicPreferences,
            recentSongs: recentSongs,
            currentDistance: totalDistance,
            currentPace: currentPace,
            isActive: isActive
        )
    }
    
    var timeRemainingInSegment: TimeInterval {
        // Estimate remaining time in the current segment.
        // We subtract the elapsed time within this segment from the segment's target duration.
        // Elapsed in current segment = totalTime - sum(targetDuration of prior segments)
        let priorDurations = segments.prefix(currentSegmentIndex).map { $0.targetDuration }.reduce(0, +)
        let elapsedInCurrent = max(0, totalTime - priorDurations)
        let remaining = max(0, currentSegment.targetDuration - elapsedInCurrent)
        return remaining
    }
}
