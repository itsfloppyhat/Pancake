import Foundation

@main
struct MusicRecommendationPolicyRegression {
    static func main() {
        do {
            try testSmoothedHeartRateWeightsRecentSamples()
            try testHeartRateTrendDetection()
            try testStableHeartRateMismatchDetection()
            try testTasteProfilePrioritizesManualFavorites()
            try testFallbackSuggestionAvoidsPlayedManualFavorites()
            try testFallbackSuggestionUsesImportedTasteSample()
            try testNormalizedSongIdentityCollapsesVariants()
            print("All Pancake music policy regressions passed.")
        } catch {
            fputs("Regression failure: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func testSmoothedHeartRateWeightsRecentSamples() throws {
        let smoothed = MusicRecommendationPolicy.smoothedHeartRate(from: [142, 144, 149, 153, 157])
        try assertEqual(smoothed, 152, "Weighted smoothing should favor recent heart-rate samples.")
    }

    private static func testHeartRateTrendDetection() throws {
        try assertEqual(
            MusicRecommendationPolicy.heartRateTrend(from: [138, 140, 145, 150, 154]),
            .rising,
            "A clear positive delta should be marked as rising."
        )
        try assertEqual(
            MusicRecommendationPolicy.heartRateTrend(from: [160, 156, 151, 148, 145]),
            .falling,
            "A clear negative delta should be marked as falling."
        )
        try assertEqual(
            MusicRecommendationPolicy.heartRateTrend(from: [150, 151, 149, 150, 150]),
            .steady,
            "Small noise should be treated as steady."
        )
    }

    private static func testStableHeartRateMismatchDetection() throws {
        let aboveTarget = MusicRecommendationPolicy.hasStableHeartRateMismatch(
            targetHeartRate: 150,
            samples: [160, 161, 162]
        )
        let nearTarget = MusicRecommendationPolicy.hasStableHeartRateMismatch(
            targetHeartRate: 150,
            samples: [149, 152, 151]
        )

        try assertTrue(aboveTarget, "Three consistently high samples should count as a stable mismatch.")
        try assertTrue(!nearTarget, "Small fluctuations around target should not count as a stable mismatch.")
    }

    private static func testTasteProfilePrioritizesManualFavorites() throws {
        let preferences = MusicPreferences(
            favoriteArtists: [
                MusicArtist(id: "artist-1", name: "Manual Artist"),
                MusicArtist(id: "artist-2", name: "Second Manual Artist")
            ],
            favoriteSongs: [
                MusicSong(id: "song-1", title: "Manual Anthem", artist: "Manual Artist", duration: 215)
            ],
            favoriteGenres: [
                MusicGenre(id: "alt", name: "Alternative", isSelected: true)
            ],
            selectedPlaylist: ImportedPlaylist(id: "playlist-1", name: "Long Run Mix", songCount: 20),
            importedPlaylistArtists: [
                MusicArtist(id: "artist-3", name: "Imported Artist")
            ],
            importedPlaylistSongs: [
                MusicSong(id: "song-2", title: "Imported Track", artist: "Imported Artist", duration: 200)
            ],
            importedPlaylistGenres: [
                MusicGenre(id: "electronic", name: "Electronic", isSelected: true)
            ]
        )

        let profile = MusicTasteProfileBuilder.build(from: preferences)

        try assertEqual(profile.primaryArtists, ["Manual Artist", "Second Manual Artist"], "Manual artists should stay primary.")
        try assertEqual(profile.supportingArtists, ["Imported Artist"], "Imported playlist artists should remain supporting taste signals.")
        try assertEqual(profile.playlistName, "Long Run Mix", "Playlist name should be preserved as a taste sample label.")
    }

    private static func testFallbackSuggestionAvoidsPlayedManualFavorites() throws {
        let repeatedSong = MusicSong(id: "song-1", title: "Again", artist: "Runner", duration: 210)
        let freshSong = MusicSong(id: "song-2", title: "Fresh Pick", artist: "Runner", duration: 200)
        let preferences = MusicPreferences(
            favoriteSongs: [repeatedSong, freshSong]
        )

        let fallback = MusicRecommendationPolicy.fallbackSuggestion(
            preferences: preferences,
            intensity: .zone3,
            avoiding: [repeatedSong.sessionSongKey]
        )

        try assertEqual(fallback?.songTitle, "Fresh Pick", "Fallback should skip already-played manual favorites.")
    }

    private static func testFallbackSuggestionUsesImportedTasteSample() throws {
        let importedSong = MusicSong(id: "song-3", title: "Playlist Gem", artist: "Imported Runner", duration: 190)
        let preferences = MusicPreferences(
            selectedPlaylist: ImportedPlaylist(id: "playlist-2", name: "Tempo Builder", songCount: 12),
            importedPlaylistSongs: [importedSong]
        )

        let fallback = MusicRecommendationPolicy.fallbackSuggestion(
            preferences: preferences,
            intensity: .zone4,
            avoiding: []
        )

        try assertEqual(fallback?.songTitle, "Playlist Gem", "Imported taste samples should provide a fallback when manual favorites are empty.")
        try assertEqual(fallback?.mood, .motivational, "Fallback mood should track workout intensity.")
    }

    private static func testNormalizedSongIdentityCollapsesVariants() throws {
        let normalizedA = "Blinding Lights (Live) - Remastered 2024".normalizedMusicIdentity
        let normalizedB = "Blinding Lights".normalizedMusicIdentity
        let sessionKeyA = MusicSuggestion(
            songTitle: "Blinding Lights - The Weeknd",
            artist: "The Weeknd",
            reason: "test",
            mood: .energetic
        ).cleanedTitle().sessionSongKey
        let sessionKeyB = MusicSong(
            id: "song-4",
            title: "Blinding Lights",
            artist: "The Weeknd",
            duration: 200
        ).sessionSongKey

        try assertEqual(normalizedA, normalizedB, "Normalization should collapse common song-title variants.")
        try assertEqual(sessionKeyA, sessionKeyB, "Suggestion and playback keys should normalize to the same repeat key.")
    }

    private static func assertTrue(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw RegressionError(message)
        }
    }

    private static func assertEqual<T: Equatable>(_ lhs: T?, _ rhs: T?, _ message: String) throws {
        if lhs != rhs {
            throw RegressionError("\(message) Expected \(String(describing: rhs)), got \(String(describing: lhs)).")
        }
    }

    private struct RegressionError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }
}
