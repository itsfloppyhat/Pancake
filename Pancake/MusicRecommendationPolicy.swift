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
            .prefix(5)
            .map { $0 }

        let supportingArtists = preferences.importedPlaylistArtists
            .map(\.name)
            .filter { !$0.isEmpty }
            .filter { !primaryArtists.contains($0) }
            .prefix(6)
            .map { $0 }

        let primarySongs = preferences.favoriteSongs
            .map { "\($0.title) by \($0.artist)" }
            .prefix(4)
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
            .prefix(6)
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

    static func fallbackSuggestion(
        preferences: MusicPreferences,
        intensity: Intensity,
        avoiding avoidedSongKeys: Set<String>
    ) -> MusicSuggestion? {
        let mood = defaultMood(for: intensity)
        let manualFavorites = preferences.favoriteSongs.filter { !avoidedSongKeys.contains($0.sessionSongKey) }

        if let favoriteSong = manualFavorites.first {
            return MusicSuggestion(
                songTitle: favoriteSong.title,
                artist: favoriteSong.artist,
                reason: "Using one of the runner's saved favorite songs as a fast fallback while keeping the \(intensity.label) effort on track.",
                mood: mood,
                confidence: 0.66
            )
        }

        let importedPlaylistSongs = preferences.importedPlaylistSongs.filter { !avoidedSongKeys.contains($0.sessionSongKey) }
        if let playlistSong = importedPlaylistSongs.first {
            let playlistName = preferences.selectedPlaylist?.name ?? "their imported taste sample"
            return MusicSuggestion(
                songTitle: playlistSong.title,
                artist: playlistSong.artist,
                reason: "Using a song from \(playlistName) as a fast fallback that still matches the runner's taste profile.",
                mood: mood,
                confidence: 0.62
            )
        }

        return nil
    }

    static func defaultMood(for intensity: Intensity) -> MusicMood {
        switch intensity {
        case .easy:
            return .chill
        case .medium:
            return .energetic
        case .hard:
            return .intense
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
