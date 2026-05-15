import Foundation

// MARK: - Music Models

struct MusicSong: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artwork: URL?
    let duration: TimeInterval
    let tempo: Int? // BPM
    let energy: Double? // 0.0 to 1.0
    let valence: Double? // 0.0 to 1.0 (mood: sad to happy)
    
    init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        artwork: URL? = nil,
        duration: TimeInterval,
        tempo: Int? = nil,
        energy: Double? = nil,
        valence: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.duration = duration
        self.tempo = tempo
        self.energy = energy
        self.valence = valence
    }
}

struct MusicArtist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let artwork: URL?
    let genres: [String]
    
    init(
        id: String,
        name: String,
        artwork: URL? = nil,
        genres: [String] = []
    ) {
        self.id = id
        self.name = name
        self.artwork = artwork
        self.genres = genres
    }
}

struct MusicGenre: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var isSelected: Bool
    
    init(
        id: String,
        name: String,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
    }
}

struct ImportedPlaylist: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let songCount: Int

    init(id: String, name: String, songCount: Int) {
        self.id = id
        self.name = name
        self.songCount = songCount
    }
}

struct MusicPreferences: Codable, Equatable {
    var favoriteArtists: [MusicArtist]
    var favoriteSongs: [MusicSong]
    var favoriteGenres: [MusicGenre]
    var selectedPlaylist: ImportedPlaylist?
    var importedPlaylistArtists: [MusicArtist]
    var importedPlaylistSongs: [MusicSong]
    var importedPlaylistGenres: [MusicGenre]
    var preferredMoodForIntensity: [Intensity: MusicMood]
    var autoPlayEnabled: Bool
    var crossfadeDuration: TimeInterval
    var volumeBoost: Double
    
    init(
        favoriteArtists: [MusicArtist] = [],
        favoriteSongs: [MusicSong] = [],
        favoriteGenres: [MusicGenre] = [],
        selectedPlaylist: ImportedPlaylist? = nil,
        importedPlaylistArtists: [MusicArtist] = [],
        importedPlaylistSongs: [MusicSong] = [],
        importedPlaylistGenres: [MusicGenre] = [],
        preferredMoodForIntensity: [Intensity: MusicMood] = [:],
        autoPlayEnabled: Bool = true,
        crossfadeDuration: TimeInterval = 4.0,
        volumeBoost: Double = 0.0
    ) {
        self.favoriteArtists = favoriteArtists
        self.favoriteSongs = favoriteSongs
        self.favoriteGenres = favoriteGenres
        self.selectedPlaylist = selectedPlaylist
        self.importedPlaylistArtists = importedPlaylistArtists
        self.importedPlaylistSongs = importedPlaylistSongs
        self.importedPlaylistGenres = importedPlaylistGenres
        self.preferredMoodForIntensity = preferredMoodForIntensity
        self.autoPlayEnabled = autoPlayEnabled
        self.crossfadeDuration = crossfadeDuration
        self.volumeBoost = volumeBoost
        
        // Set default mood preferences for each intensity
        if self.preferredMoodForIntensity.isEmpty {
            self.preferredMoodForIntensity[.zone1] = .calming
            self.preferredMoodForIntensity[.zone2] = .chill
            self.preferredMoodForIntensity[.zone3] = .energetic
            self.preferredMoodForIntensity[.zone4] = .motivational
            self.preferredMoodForIntensity[.zone5] = .intense
        }
    }

    var allFavoriteArtists: [MusicArtist] {
        deduplicatedByID(favoriteArtists + importedPlaylistArtists)
    }

    var allFavoriteSongs: [MusicSong] {
        deduplicatedByID(favoriteSongs + importedPlaylistSongs)
    }

    var allFavoriteGenres: [MusicGenre] {
        mergedGenres(favoriteGenres + importedPlaylistGenres)
    }

    var hasImportedPlaylistContent: Bool {
        selectedPlaylist != nil && (!importedPlaylistSongs.isEmpty || !importedPlaylistArtists.isEmpty || !importedPlaylistGenres.isEmpty)
    }

    private func deduplicatedByID<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        var result: [T] = []

        for item in items {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }

        return result
    }

    private func mergedGenres(_ genres: [MusicGenre]) -> [MusicGenre] {
        var indexByID: [String: Int] = [:]
        var result: [MusicGenre] = []

        for genre in genres {
            if let existingIndex = indexByID[genre.id] {
                let existing = result[existingIndex]
                result[existingIndex] = MusicGenre(
                    id: existing.id,
                    name: existing.name,
                    isSelected: existing.isSelected || genre.isSelected
                )
            } else {
                indexByID[genre.id] = result.count
                result.append(genre)
            }
        }

        return result
    }
}

struct MusicContext: Codable {
    let currentHeartRate: Int?
    let guidanceHeartRate: Int?
    let targetHeartRate: Int?
    let heartRateTrend: HeartRateTrend
    let hasStableHeartRateSignal: Bool
    let currentIntensity: Intensity
    let timeRemainingInSegment: TimeInterval
    let currentSongEndingIn: TimeInterval?
    let userPreferences: MusicPreferences
    let recentSongs: [MusicSong]
    let currentDistance: Double?
    let currentPace: Double? // km/h
    let isActive: Bool // whether user is actually moving/exercising

    var effectiveHeartRate: Int? {
        guidanceHeartRate ?? currentHeartRate
    }
    
    var heartRateZone: HeartRateZone {
        guard let current = effectiveHeartRate, let target = targetHeartRate else {
            return .unknown
        }
        
        let difference = abs(current - target)
        if difference <= 5 {
            return .perfect
        } else if current < target - 10 {
            return .tooLow
        } else if current > target + 10 {
            return .tooHigh
        } else {
            return .close
        }
    }
    
    var actualWorkoutIntensity: WorkoutIntensity {
        if !isActive || (currentDistance ?? 0) < 0.01 {
            return .resting
        }
        
        guard let heartRate = effectiveHeartRate else {
            return .unknown
        }
        
        let percentOfMax = Double(heartRate) / Double(Intensity.defaultMaxHeartRate)
        if percentOfMax < 0.50 {
            return .veryLight
        } else if percentOfMax < 0.60 {
            return .light
        } else if percentOfMax < 0.70 {
            return .moderate
        } else if percentOfMax < 0.80 {
            return .vigorous
        } else {
            return .maximum
        }
    }
    
    var shouldAdjustMusic: Bool {
        guard hasStableHeartRateSignal else {
            return false
        }

        switch heartRateZone {
        case .tooLow, .tooHigh:
            return true
        default:
            return false
        }
    }
}

struct MusicPromptSection: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String

    init(title: String, body: String) {
        self.id = title
        self.title = title
        self.body = body
    }
}

struct MusicPromptPreview: Equatable {
    let promptTitle: String
    let sections: [MusicPromptSection]
    let fullPrompt: String
}

// MARK: - Enums

enum WorkoutPhase: String, CaseIterable, Identifiable, Codable, Hashable {
    case starting
    case midway
    case finishing
    case interval
    case recovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .starting:
            return "Starting"
        case .midway:
            return "Midway"
        case .finishing:
            return "Finishing"
        case .interval:
            return "Interval"
        case .recovery:
            return "Recovery"
        }
    }

    var description: String {
        switch self {
        case .starting:
            return "Beginning of the run"
        case .midway:
            return "Settled into the middle of the workout"
        case .finishing:
            return "Closing stretch of the run"
        case .interval:
            return "Switching into a harder interval"
        case .recovery:
            return "Backing off into recovery"
        }
    }
}

enum PromptLabSourceMode: String, CaseIterable, Identifiable, Hashable {
    case allowCatalog
    case preferLibrary
    case libraryOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allowCatalog:
            return "Allow Apple Music"
        case .preferLibrary:
            return "Prefer Library"
        case .libraryOnly:
            return "Library Only"
        }
    }

    var detail: String {
        switch self {
        case .allowCatalog:
            return "Use library or Apple Music catalog"
        case .preferLibrary:
            return "Lean on saved songs first"
        case .libraryOnly:
            return "Force a locally playable pick"
        }
    }

    var prefersLibrary: Bool {
        switch self {
        case .allowCatalog:
            return false
        case .preferLibrary, .libraryOnly:
            return true
        }
    }

    var requiresLibraryOnly: Bool {
        self == .libraryOnly
    }
}

enum WorkoutIntensity: String, CaseIterable, Codable {
    case resting = "resting"
    case veryLight = "veryLight"
    case light = "light"
    case moderate = "moderate"
    case vigorous = "vigorous"
    case maximum = "maximum"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .resting: return "Resting"
        case .veryLight: return "Very Light"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .vigorous: return "Vigorous"
        case .maximum: return "Maximum"
        case .unknown: return "Unknown"
        }
    }
    
    var description: String {
        switch self {
        case .resting: return "Not actively exercising"
        case .veryLight: return "Very light activity, easy pace"
        case .light: return "Light activity, comfortable pace"
        case .moderate: return "Moderate activity, steady pace"
        case .vigorous: return "Vigorous activity, challenging pace"
        case .maximum: return "Maximum effort, very challenging"
        case .unknown: return "Intensity unknown"
        }
    }
}

enum MusicMood: String, CaseIterable, Codable {
    case chill = "chill"
    case energetic = "energetic"
    case intense = "intense"
    case motivational = "motivational"
    case calming = "calming"
    case upbeat = "upbeat"
    
    var displayName: String {
        switch self {
        case .chill: return "Chill"
        case .energetic: return "Energetic"
        case .intense: return "Intense"
        case .motivational: return "Motivational"
        case .calming: return "Calming"
        case .upbeat: return "Upbeat"
        }
    }
    
    var description: String {
        switch self {
        case .chill: return "Relaxed, easy-going vibes"
        case .energetic: return "High energy, motivating"
        case .intense: return "Aggressive, powerful"
        case .motivational: return "Inspiring, uplifting"
        case .calming: return "Peaceful, soothing"
        case .upbeat: return "Happy, positive"
        }
    }
    
    var icon: String {
        switch self {
        case .chill: return "leaf.fill"
        case .energetic: return "bolt.fill"
        case .intense: return "flame.fill"
        case .motivational: return "heart.fill"
        case .calming: return "moon.fill"
        case .upbeat: return "sun.max.fill"
        }
    }
    
    var color: String {
        switch self {
        case .chill: return "green"
        case .energetic: return "orange"
        case .intense: return "red"
        case .motivational: return "pink"
        case .calming: return "blue"
        case .upbeat: return "yellow"
        }
    }
}

// MARK: - Music Suggestion Models

struct MusicSuggestion: Codable, Identifiable {
    let id: UUID
    let songTitle: String
    let artist: String
    let reason: String
    let mood: MusicMood
    let confidence: Double // 0.0 to 1.0

    init(songTitle: String, artist: String, reason: String, mood: MusicMood, confidence: Double = 0.8) {
        self.id = UUID()
        self.songTitle = songTitle
        self.artist = artist
        self.reason = reason
        self.mood = mood
        self.confidence = confidence
    }

    /// Returns a copy with the artist name stripped from the song title.
    /// The AI often returns titles like "As It Was by Harry Styles" instead of just "As It Was".
    func cleanedTitle() -> MusicSuggestion {
        var title = songTitle

        // Remove trailing " by Artist" (case-insensitive)
        if let range = title.range(of: " by \(artist)", options: [.caseInsensitive, .backwards]) {
            title = String(title[..<range.lowerBound])
        }

        // Also try " - Artist" pattern
        if let range = title.range(of: " - \(artist)", options: [.caseInsensitive, .backwards]) {
            title = String(title[..<range.lowerBound])
        }

        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != songTitle else { return self }

        return MusicSuggestion(songTitle: cleaned, artist: artist, reason: reason, mood: mood, confidence: confidence)
    }

    func resolvedToCatalogTrack(title: String, artist: String) -> MusicSuggestion {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else {
            return self
        }

        return MusicSuggestion(
            songTitle: cleanTitle,
            artist: cleanArtist,
            reason: reason,
            mood: mood,
            confidence: confidence
        )
    }

    var sessionSongKey: String {
        let cleaned = cleanedTitle()
        return "\(cleaned.artist.normalizedMusicIdentity)|\(cleaned.songTitle.normalizedMusicIdentity)"
    }
}

extension MusicSong {
    var sessionSongKey: String {
        "\(artist.normalizedMusicIdentity)|\(title.normalizedMusicIdentity)"
    }
}

extension String {
    var normalizedMusicIdentity: String {
        var value = folding(options: [.diacriticInsensitive], locale: .current).lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        value = value.replacingOccurrences(of: #"\s*\([^\)]*\)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(
            of: #"\s*-\s*(remaster(ed)?(\s*\d{4})?|live|radio edit|single version|album version|explicit|clean)"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VolumePreference: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var volumeLevel: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.9
        }
    }
}

enum HeartRateZone: String, CaseIterable, Codable {
    case perfect = "perfect"
    case close = "close"
    case tooLow = "too_low"
    case tooHigh = "too_high"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .perfect: return "Perfect"
        case .close: return "Close"
        case .tooLow: return "Too Low"
        case .tooHigh: return "Too High"
        case .unknown: return "Unknown"
        }
    }
    
    var description: String {
        switch self {
        case .perfect: return "Perfect heart rate for effort"
        case .close: return "Close to target heart rate"
        case .tooLow: return "Heart rate too low for effort"
        case .tooHigh: return "Heart rate too high for effort"
        case .unknown: return "Heart rate unknown"
        }
    }
}
