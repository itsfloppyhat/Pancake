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
    
    private let chatGPTService = ChatGPTService.shared
    private let profileManager = UserProfileManager.shared
    private var musicPlayer: MPMusicPlayerController
    private var playbackTimer: Timer?
    private var suggestionTimer: Timer?
    private var currentWorkoutContext: WorkoutContext?
    private var lastSuggestionTime: Date = Date.distantPast
    
    // MARK: - Apple Music Integration
    
    func playAppleMusicSuggestion(_ suggestion: MusicSuggestion) async {
        print("🎵 Attempting to play Apple Music suggestion: '\(suggestion.songTitle)' by \(suggestion.artist)")
        
        // First try to find the exact song in Apple Music
        do {
            let songs = try await MusicKitService.shared.searchSongs(query: "\(suggestion.songTitle) \(suggestion.artist)", limit: 10)
            
            if let exactMatch = songs.first(where: { song in
                let normalizedTitle = normalize(song.title)
                let normalizedArtist = normalize(song.artistName)
                let normalizedSuggestionTitle = normalize(suggestion.songTitle)
                let normalizedSuggestionArtist = normalize(suggestion.artist)
                
                return normalizedTitle == normalizedSuggestionTitle && normalizedArtist == normalizedSuggestionArtist
            }) {
                print("🎯 Found exact Apple Music match: '\(exactMatch.title)' by \(exactMatch.artistName)")
                try await MusicKitService.shared.playSong(exactMatch)
                return
            }
            
            // Try to find a close match
            if let closeMatch = songs.first {
                print("🎯 Found close Apple Music match: '\(closeMatch.title)' by \(closeMatch.artistName)")
                try await MusicKitService.shared.playSong(closeMatch)
                return
            }
            
            print("❌ No Apple Music matches found for '\(suggestion.songTitle)' by \(suggestion.artist)")
            playbackError = MusicError.searchFailed
            
        } catch {
            print("❌ Apple Music search error: \(error)")
            playbackError = error
        }
    }
    
    // MARK: - Matching Helpers
    private func normalize(_ text: String) -> String {
        // Lowercase, trim, remove punctuation
        var s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove common parentheticals like (feat. ...), (live), (remastered 2011), [radio edit]
        // Remove anything in parentheses or brackets
        s = s.replacingOccurrences(of: #"\s*\([^\)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        // Remove common hyphen suffixes like "- remastered", "- live"
        s = s.replacingOccurrences(of: #"\s*-\s*(remaster(ed)?(\s*\d{4})?|live|radio edit|single version)"#, with: "", options: .regularExpression)
        // Collapse multiple spaces
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s
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
    
    private init() {
        musicPlayer = MPMusicPlayerController.systemMusicPlayer
        setupMusicPlayer()
        
        // Additional setup for better reliability
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
    
    // MARK: - Workout Integration
    
    func startWorkoutMusic(workoutContext: WorkoutContext) {
        print("🎵 MusicPlaybackManager.startWorkoutMusic called")
        currentWorkoutContext = workoutContext
        
        // Start with initial song suggestion
        print("🎵 Starting initial song generation...")
        Task {
            await generateAndPlayStartingSong()
        }
        
        // Set up suggestion timer for interval changes
        print("⏰ Starting suggestion timer...")
        startSuggestionTimer()
    }
    
    func stopWorkoutMusic() {
        musicPlayer.stop()
        isPlaying = false
        currentSong = nil
        currentWorkoutContext = nil
        
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
            let suggestion = try await chatGPTService.generateStartingSongSuggestion(
                workoutPlan: context.segments,
                userPreferences: profileManager.userProfile.musicPreferences,
                currentIntensity: context.currentSegment.intensity
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
            print("❌ No workout context for next song generation")
            return 
        }
        
        print("🎵 Generating next song suggestion...")
        isGeneratingSuggestion = true
        
        do {
            let suggestion = try await chatGPTService.generateIntervalChangeSuggestion(
                context: context.musicContext,
                userPreferences: profileManager.userProfile.musicPreferences,
                currentDistance: context.totalDistance,
                currentTime: context.totalTime,
                upcomingIntensity: context.upcomingSegment?.intensity
            )
            
            print("🤖 Generated next song: '\(suggestion.songTitle)' by \(suggestion.artist)")
            await playSuggestedSong(suggestion)
            
        } catch {
            playbackError = error
            print("❌ Failed to generate next song: \(error)")
        }
        
        isGeneratingSuggestion = false
    }
    
    func playSuggestedSong(_ suggestion: MusicSuggestion) async {
        lastSuggestion = suggestion
        
        print("🎵 Attempting to play suggested song: '\(suggestion.songTitle)' by \(suggestion.artist)")
        
        // Check music authorization first
        let authStatus = MPMediaLibrary.authorizationStatus()
        print("🔐 Music authorization status: \(authStatus.rawValue)")
        
        guard authStatus == .authorized else {
            print("❌ Music not authorized. Status: \(authStatus.rawValue)")
            playbackError = MusicError.notAuthorized
            return
        }
        
        // Search for the song in Apple Music with multiple strategies
        let query = MPMediaQuery.songs()
        
        // First try exact title match
        let exactPredicate = MPMediaPropertyPredicate(
            value: suggestion.songTitle,
            forProperty: MPMediaItemPropertyTitle,
            comparisonType: .contains
        )
        query.addFilterPredicate(exactPredicate)
        
        if let items = query.items, !items.isEmpty {
            print("✅ Found \(items.count) songs matching '\(suggestion.songTitle)'")
            if let song = findBestSongMatch(items: items, suggestion: suggestion) {
                print("🎯 Playing best match: '\(song.title ?? "Unknown")' by \(song.artist ?? "Unknown")")
                await playSong(song)
                return
            } else {
                print("❌ No good match from title query, trying artist query with local filtering...")
                // Try artist query and then filter locally by title with scoring
                let artistQuery = MPMediaQuery.songs()
                let artistPredicate = MPMediaPropertyPredicate(
                    value: suggestion.artist,
                    forProperty: MPMediaItemPropertyArtist,
                    comparisonType: .contains
                )
                artistQuery.addFilterPredicate(artistPredicate)
                if let artistItems = artistQuery.items, !artistItems.isEmpty {
                    print("✅ Found \(artistItems.count) items for artist '\(suggestion.artist)' - filtering by title...")
                    // Score artist items by title/artist against suggestion
                    var bestItem: MPMediaItem?
                    var bestScore = 0
                    for item in artistItems {
                        guard let t = item.title, let a = item.artist else { continue }
                        let s = scoreMatch(itemTitle: t, itemArtist: a, sugTitle: suggestion.songTitle, sugArtist: suggestion.artist)
                        if s > bestScore {
                            bestScore = s
                            bestItem = item
                        }
                    }
                    if let bestItem = bestItem, isGoodEnough(score: bestScore) {
                        print("🎯 Playing best artist-filtered match: '\(bestItem.title ?? "Unknown")' by \(bestItem.artist ?? "Unknown") (score: \(bestScore))")
                        await playSong(bestItem)
                        return
                    } else {
                        print("❌ No good match after artist filtering (best score: \(bestScore)). Not playing unrelated song.")
                    }
                } else {
                    print("❌ No items found for artist query either.")
                }
            }
        } else {
            print("❌ No songs found matching '\(suggestion.songTitle)' in title query.")
        }
        
        // At this point, we failed to find a good match. Report error instead of playing unrelated track.
        self.playbackError = MusicError.searchFailed
        return
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
    
    private func tryFuzzySongSearch(_ suggestion: MusicSuggestion) async {
        print("🔍 Starting fuzzy search for '\(suggestion.songTitle)' by \(suggestion.artist)")
        
        // Get all songs and search manually for better matching
        let allSongsQuery = MPMediaQuery.songs()
        guard let allSongs = allSongsQuery.items, !allSongs.isEmpty else {
            print("❌ No songs in library for fuzzy search")
            await playRandomSong()
            return
        }
        
        print("📚 Searching through \(allSongs.count) songs in library...")
        
        // Try different matching strategies
        let matchingSongs = findFuzzyMatches(in: allSongs, for: suggestion)
        
        // Debug: Log top matches with scores
        if !matchingSongs.isEmpty {
            print("🔍 Top fuzzy matches found:")
            let scoredMatches = findFuzzyMatchesWithScores(in: allSongs, for: suggestion)
            for (index, match) in scoredMatches.prefix(5).enumerated() {
                print("   \(index + 1). '\(match.item.title ?? "Unknown")' by \(match.item.artist ?? "Unknown") (score: \(match.score))")
            }
        }
        
        if let bestMatch = matchingSongs.first {
            print("🎯 Found fuzzy match: '\(bestMatch.title ?? "Unknown")' by \(bestMatch.artist ?? "Unknown")")
            await playSong(bestMatch)
        } else {
            print("❌ No fuzzy matches found, trying artist search...")
            await searchAndPlayByArtist(suggestion)
        }
    }
    
    private func findFuzzyMatches(in songs: [MPMediaItem], for suggestion: MusicSuggestion) -> [MPMediaItem] {
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
            
            // Only proceed with title matching if we have an artist match
            guard hasArtistMatch else { continue }
            
            // Exact title match (highest priority)
            if title == targetTitle {
                score += 100
            }
            // Title starts with target (high priority) - more strict than contains
            else if title.hasPrefix(targetTitle) {
                score += 80
            }
            // Target starts with title (medium priority)
            else if targetTitle.hasPrefix(title) {
                score += 60
            }
            // Word-by-word matching (more strict)
            else {
                let titleWords = title.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)).filter { !$0.isEmpty }
                let targetWords = targetTitle.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)).filter { !$0.isEmpty }
                
                // Check if any target word exactly matches any title word
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
            
            // Only include songs with both artist and title match
            if score > 30 { // Must have at least artist match + some title match
                matches.append((song, score))
            }
        }
        
        // Sort by score (highest first) and return items
        return matches.sorted { $0.score > $1.score }.map { $0.item }
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
            
            // Only proceed with title matching if we have an artist match
            guard hasArtistMatch else { continue }
            
            // Exact title match (highest priority)
            if title == targetTitle {
                score += 100
            }
            // Title starts with target (high priority) - more strict than contains
            else if title.hasPrefix(targetTitle) {
                score += 80
            }
            // Target starts with title (medium priority)
            else if targetTitle.hasPrefix(title) {
                score += 60
            }
            // Word-by-word matching (more strict)
            else {
                let titleWords = title.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)).filter { !$0.isEmpty }
                let targetWords = targetTitle.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)).filter { !$0.isEmpty }
                
                // Check if any target word exactly matches any title word
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
            
            // Only include songs with both artist and title match
            if score > 30 { // Must have at least artist match + some title match
                matches.append((song, score))
            }
        }
        
        // Sort by score (highest first) and return with scores
        return matches.sorted { $0.score > $1.score }
    }
    
    private func searchAndPlayByArtist(_ suggestion: MusicSuggestion) async {
        print("🎤 Searching for artist: '\(suggestion.artist)'")
        
        let query = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(
            value: suggestion.artist,
            forProperty: MPMediaItemPropertyArtist,
            comparisonType: .contains
        )
        query.addFilterPredicate(predicate)
        
        if let items = query.items, !items.isEmpty {
            print("✅ Found \(items.count) items for artist '\(suggestion.artist)'. Filtering by title...")
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
                print("🎯 Playing best artist match: '\(bestItem.title ?? "Unknown")' by \(bestItem.artist ?? "Unknown") (score: \(bestScore))")
                await playSong(bestItem)
            } else {
                print("❌ No sufficiently good artist match (best score: \(bestScore)). Not playing unrelated song.")
                playbackError = MusicError.searchFailed
            }
        } else {
            print("❌ No items found for artist '\(suggestion.artist)'")
            playbackError = MusicError.searchFailed
        }
    }
    
    private func playRandomSong() async {
        print("🎲 Fallback: Playing random song from library (not used for AI suggestion mismatch)")
        print("📚 Total songs in library: \(MPMediaQuery.songs().items?.count ?? 0)")
        
        if let allSongs = MPMediaQuery.songs().items, !allSongs.isEmpty {
            let randomSong = allSongs.randomElement()!
            print("🎵 Selected random song: '\(randomSong.title ?? "Unknown")' by \(randomSong.artist ?? "Unknown")")
            await playSong(randomSong)
        } else {
            print("❌ No songs found in music library at all!")
            playbackError = MusicError.searchFailed
        }
    }
    
    private func playSong(_ mediaItem: MPMediaItem) async {
        print("🎵 Setting up playback for: '\(mediaItem.title ?? "Unknown")' by \(mediaItem.artist ?? "Unknown")")
        
        // Check if the media item has required properties
        guard mediaItem.title != nil && mediaItem.artist != nil else {
            print("❌ Media item missing title or artist")
            playbackError = MusicError.searchFailed
            return
        }
        
        print("✅ Media item has required properties")
        
        let collection = MPMediaItemCollection(items: [mediaItem])
        musicPlayer.setQueue(with: collection)
        
        print("📋 Queue set with \(collection.items.count) items")
        print("▶️ Starting playback...")
        
        // Check playback state before and after
        let stateBefore = musicPlayer.playbackState
        print("🎵 Playback state before: \(stateBefore.rawValue)")
        
        // Try to start playback
        musicPlayer.play()
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let stateAfter = musicPlayer.playbackState
        print("🎵 Playback state after: \(stateAfter.rawValue)")
        
        // If still not playing, try a different approach
        if stateAfter != .playing {
            print("🔄 First attempt failed, trying alternative approach...")
            
            // Stop any current playback first
            musicPlayer.stop()
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            // Set the queue again and try playing
            musicPlayer.setQueue(with: collection)
            musicPlayer.play()
            
            // Wait a bit longer
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            let finalState = musicPlayer.playbackState
            print("🎵 Final playback state: \(finalState.rawValue)")
            
            if finalState == .playing {
                print("✅ Playback started successfully on second attempt")
            } else {
                print("❌ Playback failed to start after multiple attempts. Final state: \(finalState.rawValue)")
                print("🔍 Debug info:")
                print("   - Now playing item: \(musicPlayer.nowPlayingItem?.title ?? "None")")
                print("   - Media item duration: \(mediaItem.playbackDuration)")
                print("   - Media item title: \(mediaItem.title ?? "Unknown")")
                print("   - Media item artist: \(mediaItem.artist ?? "Unknown")")
                playbackError = MusicError.searchFailed
            }
        } else {
            print("✅ Playback started successfully")
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
        
        currentSongDuration = mediaItem.playbackDuration
        startPlaybackTimer()
        
        print("✅ Song setup complete. Duration: \(mediaItem.playbackDuration) seconds")
    }
    
    // MARK: - Playback Control
    
    func playSongDirectly(_ mediaItem: MPMediaItem) async {
        print("🎵 Direct playback for: '\(mediaItem.title ?? "Unknown")' by \(mediaItem.artist ?? "Unknown")")
        
        let collection = MPMediaItemCollection(items: [mediaItem])
        musicPlayer.setQueue(with: collection)
        
        print("▶️ Starting direct playback...")
        musicPlayer.play()
        
        // Wait and check
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let state = musicPlayer.playbackState
        print("🎵 Direct playback state: \(state.rawValue)")
        
        if state == .playing {
            print("✅ Direct playback successful!")
        } else {
            print("❌ Direct playback failed. State: \(state.rawValue)")
        }
    }
    
    func play() {
        musicPlayer.play()
    }
    
    func pause() {
        musicPlayer.pause()
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
        
        // Check every 60 seconds for song transitions (much less aggressive)
        suggestionTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForNextSongSuggestion()
            }
        }
        print("⏰ Suggestion timer started (checking every 60 seconds)")
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
        guard currentWorkoutContext != nil && !isGeneratingSuggestion else { 
            print("❌ No workout context or already generating suggestion")
            return 
        }
        
        // Check if we need a new song suggestion
        let timeRemainingInSong = currentSongDuration - currentPlaybackTime
        print("⏰ Song check: \(timeRemainingInSong) seconds remaining in current song")
        
        // Only suggest new song if:
        // 1. Current song is ending soon (within 60 seconds) - increased from 30
        // 2. We don't have a current song (song finished)
        // 3. Song duration is 0 (no song playing)
        // 4. AND we haven't generated a suggestion in the last 2 minutes
        
        let shouldGenerate = (timeRemainingInSong <= 60 || currentSongDuration == 0 || currentSong == nil)
        
        if shouldGenerate {
            // Check if we've generated a suggestion recently to prevent rapid looping
            let timeSinceLastSuggestion = Date().timeIntervalSince(lastSuggestionTime)
            if timeSinceLastSuggestion > 120 { // 2 minutes minimum between suggestions
                print("🎵 Time for next song! Generating suggestion...")
                lastSuggestionTime = Date()
                await generateNextSongSuggestion()
            } else {
                print("⏰ Skipping suggestion - too soon since last one (\(Int(timeSinceLastSuggestion))s ago)")
            }
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func playbackStateChanged() {
        isPlaying = musicPlayer.playbackState == .playing
    }
    
    @objc private func playbackDidEnd() {
        // Check if playback stopped and we're in a workout
        if musicPlayer.playbackState == .stopped && currentWorkoutContext != nil && !isGeneratingSuggestion {
            let timeSinceLastSuggestion = Date().timeIntervalSince(lastSuggestionTime)
            if timeSinceLastSuggestion > 120 { // 2 minutes minimum between suggestions
                print("🎵 Playback ended - generating next song")
                lastSuggestionTime = Date()
                Task {
                    await generateNextSongSuggestion()
                }
            } else {
                print("⏰ Skipping playback end generation - too soon since last one (\(Int(timeSinceLastSuggestion))s ago)")
            }
        }
    }
    
    @objc private func nowPlayingItemChanged() {
        if let nowPlayingItem = musicPlayer.nowPlayingItem {
            print("🎵 Now playing changed to: '\(nowPlayingItem.title ?? "Unknown")' by \(nowPlayingItem.artist ?? "Unknown")")
            currentSong = MusicSong(
                id: "\(nowPlayingItem.persistentID)",
                title: nowPlayingItem.title ?? "Unknown",
                artist: nowPlayingItem.artist ?? "Unknown",
                album: nowPlayingItem.albumTitle,
                artwork: nil,
                duration: nowPlayingItem.playbackDuration
            )
            currentSongDuration = nowPlayingItem.playbackDuration
        } else {
            print("🎵 No song playing")
            currentSong = nil
            currentSongDuration = 0
            
            // Only generate next song if we're in a workout AND not already generating a suggestion
            // AND the playback state indicates the song actually ended (not just paused)
            // AND we haven't generated a suggestion recently
            if currentWorkoutContext != nil && !isGeneratingSuggestion && musicPlayer.playbackState == .stopped {
                let timeSinceLastSuggestion = Date().timeIntervalSince(lastSuggestionTime)
                if timeSinceLastSuggestion > 120 { // 2 minutes minimum between suggestions
                    print("🎵 Song ended during workout - generating next song")
                    lastSuggestionTime = Date()
                    Task {
                        await generateNextSongSuggestion()
                    }
                } else {
                    print("⏰ Skipping song generation - too soon since last one (\(Int(timeSinceLastSuggestion))s ago)")
                }
            }
        }
    }
    
    // MARK: - Music Fade Controls
    
    func fadeOutMusic() {
        // For MPMusicPlayerController, we can't directly control volume
        // We'll use a subtle approach - brief pause during speech
        print("🎵 Pausing music for speech")
        musicPlayer.pause()
    }
    
    func fadeInMusic() {
        // Resume music after speech
        print("🎵 Resuming music after speech")
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
        targetHeartRate: Int?
    ) {
        self.segments = segments
        self.currentSegmentIndex = currentSegmentIndex
        self.currentSegment = segments[currentSegmentIndex]
        self.upcomingSegment = currentSegmentIndex + 1 < segments.count ? segments[currentSegmentIndex + 1] : nil
        self.totalDistance = totalDistance
        self.totalTime = totalTime
        
        // Calculate current pace (meters per second)
        let currentPace = totalTime > 0 ? totalDistance / totalTime : nil
        
        // Determine if user is actively exercising based on distance and time
        let isActive = totalDistance > 10 && totalTime > 30 // At least 10 meters in 30 seconds
        
        self.musicContext = MusicContext(
            currentHeartRate: heartRate,
            targetHeartRate: targetHeartRate,
            currentIntensity: currentSegment.intensity,
            timeRemainingInSegment: currentSegment.targetDuration,
            currentSongEndingIn: nil, // Will be updated by MusicPlaybackManager
            userPreferences: UserProfileManager.shared.userProfile.musicPreferences,
            recentSongs: [], // Will be updated by MusicPlaybackManager
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

// MARK: - Extensions
extension RunSegment {
    var targetDuration: TimeInterval {
        switch target {
        case .time(let seconds):
            return TimeInterval(seconds)
        case .distance:
            return 0 // Will be calculated based on pace
        }
    }
}

