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

struct MusicPreferences: Codable, Equatable {
    var favoriteArtists: [MusicArtist]
    var favoriteSongs: [MusicSong]
    var favoriteGenres: [MusicGenre]
    var preferredMoodForIntensity: [Intensity: MusicMood]
    var autoPlayEnabled: Bool
    var crossfadeDuration: TimeInterval
    var volumeBoost: Double
    
    init(
        favoriteArtists: [MusicArtist] = [],
        favoriteSongs: [MusicSong] = [],
        favoriteGenres: [MusicGenre] = [],
        preferredMoodForIntensity: [Intensity: MusicMood] = [:],
        autoPlayEnabled: Bool = true,
        crossfadeDuration: TimeInterval = 5.0,
        volumeBoost: Double = 0.0
    ) {
        self.favoriteArtists = favoriteArtists
        self.favoriteSongs = favoriteSongs
        self.favoriteGenres = favoriteGenres
        self.preferredMoodForIntensity = preferredMoodForIntensity
        self.autoPlayEnabled = autoPlayEnabled
        self.crossfadeDuration = crossfadeDuration
        self.volumeBoost = volumeBoost
        
        // Set default mood preferences for each intensity
        if self.preferredMoodForIntensity.isEmpty {
            self.preferredMoodForIntensity[.easy] = .chill
            self.preferredMoodForIntensity[.medium] = .energetic
            self.preferredMoodForIntensity[.hard] = .intense
        }
    }
}

struct MusicContext: Codable {
    let currentHeartRate: Int?
    let targetHeartRate: Int?
    let currentIntensity: Intensity
    let timeRemainingInSegment: TimeInterval
    let currentSongEndingIn: TimeInterval?
    let userPreferences: MusicPreferences
    let recentSongs: [MusicSong]
    let currentDistance: Double?
    let currentPace: Double? // meters per second
    let isActive: Bool // whether user is actually moving/exercising
    
    var heartRateZone: HeartRateZone {
        guard let current = currentHeartRate, let target = targetHeartRate else {
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
        // Determine actual workout intensity based on real-time data
        if !isActive || (currentDistance ?? 0) < 10 {
            return .resting
        }
        
        guard let heartRate = currentHeartRate else {
            return .unknown
        }
        
        if heartRate < 100 {
            return .veryLight
        } else if heartRate < 120 {
            return .light
        } else if heartRate < 140 {
            return .moderate
        } else if heartRate < 160 {
            return .vigorous
        } else {
            return .maximum
        }
    }
    
    var shouldAdjustMusic: Bool {
        // Should we adjust music based on actual vs planned intensity?
        switch (currentIntensity, actualWorkoutIntensity) {
        case (.easy, .vigorous), (.easy, .maximum):
            return true // Easy workout but high intensity - need calming music
        case (.medium, .veryLight), (.medium, .light), (.hard, .veryLight), (.hard, .light):
            return true // Hard workout but low intensity - need energizing music
        case (.easy, .veryLight), (.easy, .light):
            return true // Easy workout and low intensity - need energizing music
        default:
            return false
        }
    }
}

// MARK: - Enums

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
