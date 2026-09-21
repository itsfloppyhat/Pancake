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
            try testFallbackSuggestionsComeOnlyFromSavedTaste()
            try testPlayedSongIsBlockedForFourRuns()
            try testRunWithoutMusicDoesNotAgeOutSongHistory()
            try testPromptAvoidListIsCappedNewestFirst()
            try testRecoveredRunKeepsWatchTotalsAndSnapshotDetail()
            try testRecoveredRunSurvivesTotalLossOfLiveState()
            try testEmptyRunIsNotSaved()
            try testStaleSnapshotDetection()
            try testNormalizedSongIdentityCollapsesVariants()
            try testAdaptiveMixGoalScoring()
            try testUpcomingIntervalPrecurationWindow()
            try testAdaptiveMixQueuedSongsRemainEligibleUntilPlayed()
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

    private static func testFallbackSuggestionsComeOnlyFromSavedTaste() throws {
        let preferences = MusicPreferences(
            favoriteSongs: [
                MusicSong(id: "song-1", title: "Saved Favorite", artist: "Runner", duration: 210)
            ],
            selectedPlaylist: ImportedPlaylist(id: "playlist-1", name: "Tempo Builder", songCount: 12),
            importedPlaylistSongs: [
                MusicSong(id: "song-2", title: "Playlist Gem", artist: "Imported Runner", duration: 190)
            ]
        )

        let candidates = MusicRecommendationPolicy.fallbackSuggestions(
            preferences: preferences,
            intensity: .zone3
        )

        try assertEqual(
            candidates.map(\.songTitle),
            ["Saved Favorite", "Playlist Gem"],
            "Fallback candidates should be the runner's own songs, favorites first."
        )
        try assertTrue(
            MusicRecommendationPolicy.fallbackSuggestions(
                preferences: MusicPreferences(),
                intensity: .zone3
            ).isEmpty,
            "An empty taste profile should yield no fallback candidates rather than a shared hard-coded list."
        )
    }

    private static func testPlayedSongIsBlockedForFourRuns() throws {
        let song = MusicSong(id: "song-1", title: "Good as Hell", artist: "Lizzo", duration: 219)

        // Run 1 plays the song.
        var runs = CrossRunSongHistoryPolicy.beginningRun(in: [])
        runs = CrossRunSongHistoryPolicy.recordingPlayedSong(song, in: runs)

        try assertTrue(
            CrossRunSongHistoryPolicy.avoidedSongKeys(in: runs).contains(song.sessionSongKey),
            "A song should be blocked for the rest of the run it played in."
        )

        // Runs 2, 3 and 4 must still block it.
        for run in 2...4 {
            runs = CrossRunSongHistoryPolicy.beginningRun(in: runs)
            try assertTrue(
                CrossRunSongHistoryPolicy.avoidedSongKeys(in: runs).contains(song.sessionSongKey),
                "A song played in run 1 should still be blocked in run \(run)."
            )
            runs = CrossRunSongHistoryPolicy.recordingPlayedSong(
                MusicSong(id: "filler-\(run)", title: "Filler \(run)", artist: "Filler Artist", duration: 200),
                in: runs
            )
        }

        // Run 5 ages it out.
        runs = CrossRunSongHistoryPolicy.beginningRun(in: runs)
        try assertTrue(
            !CrossRunSongHistoryPolicy.avoidedSongKeys(in: runs).contains(song.sessionSongKey),
            "A song played in run 1 should be eligible again on the fifth run."
        )
    }

    /// The window advances per run that actually played music. A start that
    /// played nothing — abandoned, or a run done without music — does not
    /// consume a slot, because it does nothing to make an old song feel fresh.
    private static func testRunWithoutMusicDoesNotAgeOutSongHistory() throws {
        let song = MusicSong(id: "song-1", title: "Good as Hell", artist: "Lizzo", duration: 219)

        var runs = CrossRunSongHistoryPolicy.beginningRun(in: [])
        runs = CrossRunSongHistoryPolicy.recordingPlayedSong(song, in: runs)

        // Three starts that never played anything should collapse into one slot.
        for _ in 0..<3 {
            runs = CrossRunSongHistoryPolicy.beginningRun(in: runs)
        }

        try assertEqual(runs.count, 2, "Runs that played no songs should not each consume a history slot.")
        try assertTrue(
            CrossRunSongHistoryPolicy.avoidedSongKeys(in: runs).contains(song.sessionSongKey),
            "A music-free start should not age real history out of the window early."
        )
    }

    private static func testPromptAvoidListIsCappedNewestFirst() throws {
        var runs = CrossRunSongHistoryPolicy.beginningRun(in: [])

        for index in 0..<20 {
            runs = CrossRunSongHistoryPolicy.recordingPlayedSong(
                MusicSong(id: "song-\(index)", title: "Track \(index)", artist: "Runner \(index)", duration: 200),
                in: runs
            )
        }

        let promptSongs = CrossRunSongHistoryPolicy.recentAvoidedSongs(in: runs)

        try assertEqual(
            promptSongs.count,
            CrossRunSongHistoryPolicy.promptAvoidListLimit,
            "The prompt avoid list should stay capped so it cannot crowd out the rest of the prompt."
        )
        try assertEqual(promptSongs.first?.title, "Track 19", "The prompt avoid list should be newest first.")
        try assertEqual(
            CrossRunSongHistoryPolicy.avoidedSongKeys(in: runs).count,
            20,
            "Key-level blocking should still cover every song in the window, beyond the prompt cap."
        )
    }

    private static func makeSnapshot(startedAt: Date = Date()) -> ActiveRunSnapshot {
        ActiveRunSnapshot(
            startedAt: startedAt,
            segments: [RunSegment(intensity: .zone3, target: .time(seconds: 600))],
            currentSegmentIndex: 0,
            totalDistanceKm: 4.0,
            totalTimeSeconds: 1500,
            dataPoints: [
                WorkoutDataPoint(
                    timestamp: 5,
                    heartRate: 148,
                    cadence: nil,
                    distanceMeters: 20,
                    paceSecondsPerKm: nil,
                    currentSongTitle: "Track",
                    currentSongArtist: "Artist"
                )
            ],
            songHistory: [
                SongPeriod(songTitle: "Track", artist: "Artist", startTimestamp: 0, endTimestamp: 200)
            ]
        )
    }

    /// The watch's final totals arrive with the completion message and must win,
    /// while everything the killed process lost comes back from the snapshot.
    private static func testRecoveredRunKeepsWatchTotalsAndSnapshotDetail() throws {
        let snapshot = makeSnapshot()

        let resolution = RunEventRecoveryPolicy.resolve(
            liveSegments: snapshot.segments,
            liveTotalDistanceKm: 5.25,
            liveTotalTimeSeconds: 1800,
            liveDataPoints: [],
            liveSongHistory: [],
            snapshot: snapshot
        )

        try assertEqual(resolution.totalDistanceMeters, 5250, "Live watch distance should win over the snapshot's last mirror.")
        try assertEqual(resolution.totalTimeSeconds, 1800, "Live watch time should win over the snapshot's last mirror.")
        try assertEqual(resolution.dataPoints.count, 1, "Data points lost with the killed process should come back from the snapshot.")
        try assertEqual(resolution.songHistory.count, 1, "Song history lost with the killed process should come back from the snapshot.")
        try assertEqual(resolution.date, snapshot.startedAt, "A recovered run should be dated when it happened, not when it was saved.")
        try assertTrue(resolution.isSavable, "A run with real distance and time should be savable.")
    }

    /// The case that was silently dropping runs: completion arrives after the
    /// app was killed, so there is no live context at all.
    private static func testRecoveredRunSurvivesTotalLossOfLiveState() throws {
        let snapshot = makeSnapshot()

        let resolution = RunEventRecoveryPolicy.resolve(
            liveSegments: nil,
            liveTotalDistanceKm: nil,
            liveTotalTimeSeconds: nil,
            liveDataPoints: [],
            liveSongHistory: [],
            snapshot: snapshot
        )

        try assertTrue(resolution.isSavable, "A run recovered entirely from its snapshot must still be saved.")
        try assertEqual(resolution.totalDistanceMeters, 4000, "Snapshot distance should be used when no live context survived.")
        try assertEqual(resolution.totalTimeSeconds, 1500, "Snapshot time should be used when no live context survived.")
        try assertEqual(resolution.segments.count, 1, "Snapshot segments should be used when no live context survived.")
    }

    private static func testEmptyRunIsNotSaved() throws {
        let resolution = RunEventRecoveryPolicy.resolve(
            liveSegments: nil,
            liveTotalDistanceKm: nil,
            liveTotalTimeSeconds: nil,
            liveDataPoints: [],
            liveSongHistory: [],
            snapshot: nil
        )

        try assertTrue(!resolution.isSavable, "A run with no distance and no time should not reach history.")
    }

    private static func testStaleSnapshotDetection() throws {
        let startedAt = Date()
        let snapshot = makeSnapshot(startedAt: startedAt)

        try assertTrue(
            !RunEventRecoveryPolicy.isStale(snapshot, now: startedAt.addingTimeInterval(60 * 60)),
            "A run from an hour ago may still get its completion message."
        )
        try assertTrue(
            RunEventRecoveryPolicy.isStale(
                snapshot,
                now: startedAt.addingTimeInterval(RunEventRecoveryPolicy.staleRunInterval + 1)
            ),
            "A run old enough that no completion is coming should be flushed to history."
        )
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

    private static func testAdaptiveMixGoalScoring() throws {
        let easeDown = AdaptiveMixPolicy.goalScore(
            targetIntensity: .zone2,
            targetHeartRate: 130,
            effectiveHeartRate: 146
        )
        let lift = AdaptiveMixPolicy.goalScore(
            targetIntensity: .zone4,
            targetHeartRate: 162,
            effectiveHeartRate: 146
        )
        let missingMetrics = AdaptiveMixPolicy.goalScore(
            targetIntensity: .zone3,
            targetHeartRate: 150,
            effectiveHeartRate: nil
        )

        try assertEqual(easeDown.guidance, .easeDown, "A high heart rate should reduce musical intensity.")
        try assertEqual(easeDown.alignmentScore, 36, "Alignment score should fall as heart rate moves away from target.")
        try assertEqual(lift.guidance, .lift, "A low heart rate should increase musical intensity.")
        try assertEqual(missingMetrics.guidance, .followPlan, "Missing heart-rate data should use the planned interval.")
    }

    private static func testUpcomingIntervalPrecurationWindow() throws {
        try assertEqual(AdaptiveMixPolicy.refreshInterval, 30, "Adaptive Mix should regenerate playlists every 30 seconds.")
        try assertEqual(AdaptiveMixPolicy.upcomingIntervalLeadTime, 10, "Adaptive Mix should pre-curate 10 seconds before a new segment.")
        try assertEqual(AdaptiveMixPolicy.queueDepth, 3, "Adaptive Mix should keep three verified upcoming songs.")
        try assertEqual(AdaptiveMixPolicy.minimumStartSongCount, 2, "Adaptive Mix should be able to start with a partial queue of two verified songs.")

        try assertTrue(
            AdaptiveMixPolicy.shouldPrecurateUpcomingInterval(
                estimatedSecondsRemaining: 10,
                hasUpcomingInterval: true,
                alreadyPrecurated: false
            ),
            "Ten seconds remaining should trigger next-interval curation."
        )
        try assertTrue(
            !AdaptiveMixPolicy.shouldPrecurateUpcomingInterval(
                estimatedSecondsRemaining: 11,
                hasUpcomingInterval: true,
                alreadyPrecurated: false
            ),
            "More than ten seconds remaining should not trigger next-interval curation."
        )
        try assertTrue(
            !AdaptiveMixPolicy.shouldPrecurateUpcomingInterval(
                estimatedSecondsRemaining: 4,
                hasUpcomingInterval: true,
                alreadyPrecurated: true
            ),
            "The same interval should only pre-curate once."
        )
    }

    private static func testAdaptiveMixQueuedSongsRemainEligibleUntilPlayed() throws {
        let songKey = "runner|fresh pick"
        var playedSongKeys = Set<String>()
        let queuedSongKeys: Set<String> = [songKey]

        try assertTrue(
            !AdaptiveMixPolicy.canQueue(
                songKey: songKey,
                playedSongKeys: playedSongKeys,
                temporarilyReservedSongKeys: queuedSongKeys
            ),
            "A queued song should be reserved while it remains in the current three-song buffer."
        )
        try assertTrue(
            AdaptiveMixPolicy.canQueue(
                songKey: songKey,
                playedSongKeys: playedSongKeys,
                temporarilyReservedSongKeys: []
            ),
            "A queued but unplayed song should become eligible again after it leaves the current buffer."
        )

        playedSongKeys = AdaptiveMixPolicy.recordingPlayedSong(songKey, in: playedSongKeys)

        try assertTrue(
            !AdaptiveMixPolicy.canQueue(
                songKey: songKey,
                playedSongKeys: playedSongKeys,
                temporarilyReservedSongKeys: []
            ),
            "A song that played should remain excluded for the rest of the workout."
        )
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
