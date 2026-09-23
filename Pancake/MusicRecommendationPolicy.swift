import Foundation

enum HeartRateTrend: String, Codable, Equatable, Hashable {
    case rising
    case falling
    case steady
    case unknown

    var promptDescription: String {
        switch self {
        case .rising:
            return "Heart rate trend is rising."
        case .falling:
            return "Heart rate trend is falling."
        case .steady:
            return "Heart rate trend is steady."
        case .unknown:
            return "Heart rate trend is unclear."
        }
    }
}

struct MusicTastePromptProfile: Equatable {
    let primaryArtists: [String]
    let supportingArtists: [String]
    let primarySongs: [String]
    let supportingSongs: [String]
    let genres: [String]
    let playlistName: String?

    var isEmpty: Bool {
        primaryArtists.isEmpty &&
        supportingArtists.isEmpty &&
        primarySongs.isEmpty &&
        supportingSongs.isEmpty &&
        genres.isEmpty &&
        playlistName == nil
    }

    var conciseSummary: String {
        guard !isEmpty else {
            return "no strong taste signals saved yet"
        }

        var components: [String] = []

        if !primaryArtists.isEmpty {
            components.append("strong artist signals: \(primaryArtists.joined(separator: ", "))")
        }

        if !primarySongs.isEmpty {
            components.append("favorite songs: \(primarySongs.joined(separator: ", "))")
        }

        if !genres.isEmpty {
            components.append("genres: \(genres.joined(separator: ", "))")
        }

        if let playlistName {
            var imported = "playlist taste sample '\(playlistName)'"
            if !supportingArtists.isEmpty {
                imported += " with artists \(supportingArtists.joined(separator: ", "))"
            }
            if !supportingSongs.isEmpty {
                imported += " and songs \(supportingSongs.joined(separator: ", "))"
            }
            components.append(imported)
        } else if !supportingArtists.isEmpty || !supportingSongs.isEmpty {
            let importedArtistsText = supportingArtists.isEmpty ? nil : "supporting artists: \(supportingArtists.joined(separator: ", "))"
            let importedSongsText = supportingSongs.isEmpty ? nil : "supporting songs: \(supportingSongs.joined(separator: ", "))"
            components.append([importedArtistsText, importedSongsText].compactMap { $0 }.joined(separator: ", "))
        }

        return components.joined(separator: "; ")
    }

    var libraryArtistPrompt: String {
        let artists = (primaryArtists + supportingArtists).uniqued().joined(separator: ", ")
        return artists.isEmpty ? "None specified" : artists
    }

    var genrePrompt: String {
        let genres = genres.joined(separator: ", ")
        return genres.isEmpty ? "None specified" : genres
    }
}

enum MusicTasteProfileBuilder {
    static func build(from preferences: MusicPreferences) -> MusicTastePromptProfile {
        let primaryArtists = preferences.favoriteArtists
            .map(\.name)
            .filter { !$0.isEmpty }
            .prefix(12)
            .map { $0 }

        let supportingArtists = preferences.importedPlaylistArtists
            .map(\.name)
            .filter { !$0.isEmpty }
            .filter { !primaryArtists.contains($0) }
            .prefix(8)
            .map { $0 }

        let primarySongs = preferences.favoriteSongs
            .map { "\($0.title) by \($0.artist)" }
            .prefix(8)
            .map { $0 }

        let supportingSongs = preferences.importedPlaylistSongs
            .map { "\($0.title) by \($0.artist)" }
            .filter { !primarySongs.contains($0) }
            .prefix(6)
            .map { $0 }

        let genres = preferences.allFavoriteGenres
            .filter(\.isSelected)
            .map(\.name)
            .filter { !$0.isEmpty }
            .prefix(10)
            .map { $0 }

        return MusicTastePromptProfile(
            primaryArtists: Array(primaryArtists),
            supportingArtists: Array(supportingArtists),
            primarySongs: Array(primarySongs),
            supportingSongs: Array(supportingSongs),
            genres: Array(genres),
            playlistName: preferences.selectedPlaylist?.name
        )
    }
}

enum MusicRecommendationPolicy {
    private static let maxHeartRateSamples = 5

    static func normalizedHeartRates(from samples: [Int]) -> [Int] {
        Array(samples.suffix(maxHeartRateSamples))
    }

    static func smoothedHeartRate(from samples: [Int]) -> Int? {
        let normalized = normalizedHeartRates(from: samples)
        guard !normalized.isEmpty else { return nil }

        let weightedSum = normalized.enumerated().reduce(0) { partial, pair in
            let weight = pair.offset + 1
            return partial + (pair.element * weight)
        }
        let totalWeight = (1...normalized.count).reduce(0, +)

        return Int((Double(weightedSum) / Double(totalWeight)).rounded())
    }

    static func heartRateTrend(from samples: [Int]) -> HeartRateTrend {
        let normalized = normalizedHeartRates(from: samples)
        guard normalized.count >= 3 else {
            return .unknown
        }

        let splitIndex = max(1, normalized.count / 2)
        let older = Array(normalized.prefix(splitIndex))
        let recent = Array(normalized.suffix(normalized.count - splitIndex))

        guard !older.isEmpty, !recent.isEmpty else {
            return .unknown
        }

        let olderAverage = Double(older.reduce(0, +)) / Double(older.count)
        let recentAverage = Double(recent.reduce(0, +)) / Double(recent.count)
        let delta = recentAverage - olderAverage

        if delta >= 4 {
            return .rising
        }
        if delta <= -4 {
            return .falling
        }
        return .steady
    }

    static func hasStableHeartRateMismatch(targetHeartRate: Int?, samples: [Int], tolerance: Int = 8) -> Bool {
        guard let targetHeartRate else {
            return false
        }

        let recentSamples = Array(normalizedHeartRates(from: samples).suffix(3))
        guard recentSamples.count == 3 else {
            return false
        }

        let deltas = recentSamples.map { $0 - targetHeartRate }
        let allAbove = deltas.allSatisfy { $0 >= tolerance }
        let allBelow = deltas.allSatisfy { $0 <= -tolerance }

        return allAbove || allBelow
    }

    /// Fallback candidates drawn entirely from the runner's own saved taste:
    /// their manual favorites first, then their imported playlist sample.
    /// Returns an empty list when no taste has been saved yet — there is no
    /// shared hard-coded catalog to fall back on.
    static func fallbackSuggestions(
        preferences: MusicPreferences,
        intensity: Intensity
    ) -> [MusicSuggestion] {
        let mood = defaultMood(for: intensity)
        let playlistName = preferences.selectedPlaylist?.name ?? "their imported taste sample"

        let manualFavorites = preferences.favoriteSongs.map { song in
            MusicSuggestion(
                songTitle: song.title,
                artist: song.artist,
                reason: "Candidate from the runner's saved favorites; taste alone does not establish workout fit.",
                mood: mood,
                confidence: 0.66
            )
        }

        let importedPlaylistSongs = preferences.importedPlaylistSongs.map { song in
            MusicSuggestion(
                songTitle: song.title,
                artist: song.artist,
                reason: "Candidate from \(playlistName) matching the runner's taste profile.",
                mood: mood,
                confidence: 0.62
            )
        }

        var seenSongKeys = Set<String>()
        return (manualFavorites + importedPlaylistSongs).filter {
            seenSongKeys.insert($0.sessionSongKey).inserted
        }
    }

    static func fallbackSuggestion(
        preferences: MusicPreferences,
        intensity: Intensity,
        avoiding avoidedSongKeys: Set<String>
    ) -> MusicSuggestion? {
        fallbackSuggestions(preferences: preferences, intensity: intensity)
            .first { !avoidedSongKeys.contains($0.sessionSongKey) }
    }

    static func defaultMood(for intensity: Intensity) -> MusicMood {
        switch intensity {
        case .zone1:
            return .calming
        case .zone2:
            return .chill
        case .zone3:
            return .energetic
        case .zone4:
            return .motivational
        case .zone5:
            return .intense
        }
    }
}

/// The songs played during a single run, kept so later runs can avoid them.
struct RunSongHistory: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    var songs: [MusicSong]

    init(id: UUID = UUID(), startedAt: Date = Date(), songs: [MusicSong] = []) {
        self.id = id
        self.startedAt = startedAt
        self.songs = songs
    }

    var isEmpty: Bool {
        songs.isEmpty
    }
}

/// Keeps a song out of rotation for the run it played in plus the next three,
/// so a repeat is only possible on the fifth run.
enum CrossRunSongHistoryPolicy {
    /// The current run plus the three that must pass before a repeat is allowed.
    static let retainedRunCount = 4

    /// How many recent songs are named in the prompt text. The full retained
    /// set is still enforced by key filtering; this cap only keeps the
    /// on-device model's context window from filling up with avoid lists.
    static let promptAvoidListLimit = 12

    /// Opens a slot for a new run. A previous run that never played a song is
    /// replaced rather than retained, so an abandoned start does not age real
    /// history out of the window early.
    static func beginningRun(
        in runs: [RunSongHistory],
        newRun: RunSongHistory = RunSongHistory()
    ) -> [RunSongHistory] {
        var updated = runs

        if let last = updated.last, last.isEmpty {
            updated.removeLast()
        }

        updated.append(newRun)
        return Array(updated.suffix(retainedRunCount))
    }

    /// Records a played song against the run currently in progress.
    static func recordingPlayedSong(
        _ song: MusicSong,
        in runs: [RunSongHistory]
    ) -> [RunSongHistory] {
        guard var currentRun = runs.last else {
            return beginningRun(in: runs, newRun: RunSongHistory(songs: [song]))
        }

        guard !currentRun.songs.contains(where: { $0.sessionSongKey == song.sessionSongKey }) else {
            return runs
        }

        currentRun.songs.append(song)

        var updated = runs
        updated[updated.count - 1] = currentRun
        return updated
    }

    /// Every song key blocked by the retained window.
    static func avoidedSongKeys(in runs: [RunSongHistory]) -> Set<String> {
        Set(runs.suffix(retainedRunCount).flatMap(\.songs).map(\.sessionSongKey))
    }

    /// The most recently played songs across the retained window, newest first,
    /// capped for prompt use.
    static func recentAvoidedSongs(
        in runs: [RunSongHistory],
        limit: Int = promptAvoidListLimit
    ) -> [MusicSong] {
        var seenSongKeys = Set<String>()
        var songs: [MusicSong] = []

        for run in runs.suffix(retainedRunCount).reversed() {
            for song in run.songs.reversed() {
                guard songs.count < limit else { return songs }
                guard seenSongKeys.insert(song.sessionSongKey).inserted else { continue }
                songs.append(song)
            }
        }

        return songs
    }
}

struct AdaptiveMixGoalScore: Equatable {
    let targetIntensity: Intensity
    let targetHeartRate: Int?
    let effectiveHeartRate: Int?
    let heartRateDelta: Int?
    let alignmentScore: Int
    let guidance: AdaptiveMixGuidance
}

enum AdaptiveMixGuidance: String, Codable, Equatable {
    case easeDown
    case maintain
    case lift
    case followPlan

    var promptDescription: String {
        switch self {
        case .easeDown:
            return "Reduce musical intensity to guide effort down toward the planned target."
        case .maintain:
            return "Maintain musical intensity because live effort is close to the planned target."
        case .lift:
            return "Increase musical intensity to guide effort up toward the planned target."
        case .followPlan:
            return "Use the planned interval intensity because live heart-rate alignment is not available yet."
        }
    }
}

enum AdaptiveMixPolicy {
    static let refreshInterval: TimeInterval = 30
    static let upcomingIntervalLeadTime = AdaptiveMixTransitionPolicy.preparationLeadTime
    static let queueDepth = 3
    /// Starting playback tolerates a partial queue; refills top it back up to `queueDepth`.
    static let minimumStartSongCount = 1

    static func goalScore(
        targetIntensity: Intensity,
        targetHeartRate: Int?,
        effectiveHeartRate: Int?
    ) -> AdaptiveMixGoalScore {
        guard let targetHeartRate, let effectiveHeartRate else {
            return AdaptiveMixGoalScore(
                targetIntensity: targetIntensity,
                targetHeartRate: targetHeartRate,
                effectiveHeartRate: effectiveHeartRate,
                heartRateDelta: nil,
                alignmentScore: 50,
                guidance: .followPlan
            )
        }

        let delta = effectiveHeartRate - targetHeartRate
        let absoluteDelta = abs(delta)
        let alignmentScore = max(0, 100 - (absoluteDelta * 4))
        let guidance: AdaptiveMixGuidance

        if delta >= 8 {
            guidance = .easeDown
        } else if delta <= -8 {
            guidance = .lift
        } else {
            guidance = .maintain
        }

        return AdaptiveMixGoalScore(
            targetIntensity: targetIntensity,
            targetHeartRate: targetHeartRate,
            effectiveHeartRate: effectiveHeartRate,
            heartRateDelta: delta,
            alignmentScore: alignmentScore,
            guidance: guidance
        )
    }

    static func shouldPrecurateUpcomingInterval(
        estimatedSecondsRemaining: TimeInterval?,
        hasUpcomingInterval: Bool,
        alreadyPrecurated: Bool
    ) -> Bool {
        guard hasUpcomingInterval,
              !alreadyPrecurated,
              let estimatedSecondsRemaining else {
            return false
        }

        return AdaptiveMixTransitionPolicy.isWithin(upcomingIntervalLeadTime, secondsRemaining: estimatedSecondsRemaining)
    }

    static func canQueue(
        songKey: String,
        playedSongKeys: Set<String>,
        temporarilyReservedSongKeys: Set<String>
    ) -> Bool {
        !playedSongKeys.contains(songKey) &&
            !temporarilyReservedSongKeys.contains(songKey)
    }

    static func recordingPlayedSong(
        _ songKey: String,
        in playedSongKeys: Set<String>
    ) -> Set<String> {
        playedSongKeys.union([songKey])
    }
}

enum MusicEnergyLevel: String, Codable {
    case calm, gentle, steady, driving, explosive
}

/// Describes the recording itself, independently of a requested zone or taste.
/// This is a model assessment, not measured audio analysis. Unknown recordings
/// and incomplete assessments are ineligible rather than assumed energetic.
struct MusicEnergyAssessment {
    let level: MusicEnergyLevel
    let hasImmediateBeat: Bool
    let isBallad: Bool
    let confidence: Double

    func fits(_ goal: AdaptiveMixGoalScore) -> Bool {
        guard confidence.isFinite, confidence >= 0.8, confidence <= 1 else { return false }
        let easing = goal.guidance == .easeDown
        switch goal.targetIntensity {
        case .zone1:
            return level == .calm || level == .gentle
        case .zone2:
            return easing ? (level == .calm || level == .gentle) : (level == .gentle || level == .steady)
        case .zone3:
            if easing { return level == .calm || level == .gentle || level == .steady }
            return !isBallad && hasImmediateBeat && (level == .steady || level == .driving)
        case .zone4:
            return !isBallad && hasImmediateBeat &&
                (easing ? (level == .steady || level == .driving) : (level == .driving || level == .explosive))
        case .zone5:
            return !isBallad && hasImmediateBeat && (easing ? level == .driving : level == .explosive)
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
