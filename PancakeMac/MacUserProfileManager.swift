import Combine
import Foundation

enum MacMusicLibraryAuthorizationStatus: CustomStringConvertible {
    case unsupported

    var description: String {
        "Unavailable on macOS"
    }
}

@MainActor
final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    @Published var userProfile: UserProfile
    @Published var isMusicAuthorized: Bool = false
    @Published var musicAuthorizationStatus: MacMusicLibraryAuthorizationStatus = .unsupported
    @Published var lastError: Error?

    private let storageKey = "UserProfileManager.userProfile"

    private init() {
        self.userProfile = UserProfile()
        loadProfile()
    }

    func updateProfile(_ profile: UserProfile) {
        userProfile = profile
        saveProfile()
    }

    func updateMusicPreferences(_ preferences: MusicPreferences) {
        userProfile.musicPreferences = preferences
        saveProfile()
    }

    func updateRunningGoals(_ goals: RunningGoals) {
        userProfile.runningGoals = goals
        saveProfile()
    }

    func updatePersonalInfo(_ info: PersonalInfo) {
        userProfile.personalInfo = info
        saveProfile()
    }

    func addFavoriteArtist(_ artist: MusicArtist) {
        if !userProfile.musicPreferences.favoriteArtists.contains(where: { $0.id == artist.id }) {
            userProfile.musicPreferences.favoriteArtists.append(artist)
            saveProfile()
        }
    }

    func removeFavoriteArtist(_ artist: MusicArtist) {
        userProfile.musicPreferences.favoriteArtists.removeAll { $0.id == artist.id }
        saveProfile()
    }

    func addFavoriteSong(_ song: MusicSong) {
        if !userProfile.musicPreferences.favoriteSongs.contains(where: { $0.id == song.id }) {
            userProfile.musicPreferences.favoriteSongs.append(song)
            saveProfile()
        }
    }

    func removeFavoriteSong(_ song: MusicSong) {
        userProfile.musicPreferences.favoriteSongs.removeAll { $0.id == song.id }
        saveProfile()
    }

    func toggleGenre(_ genre: MusicGenre) {
        if let index = userProfile.musicPreferences.favoriteGenres.firstIndex(where: { $0.id == genre.id }) {
            userProfile.musicPreferences.favoriteGenres[index] = MusicGenre(
                id: genre.id,
                name: genre.name,
                isSelected: !genre.isSelected
            )
        } else {
            userProfile.musicPreferences.favoriteGenres.append(
                MusicGenre(id: genre.id, name: genre.name, isSelected: true)
            )
        }
        saveProfile()
    }

    func setMoodForIntensity(_ mood: MusicMood, intensity: Intensity) {
        userProfile.musicPreferences.preferredMoodForIntensity[intensity] = mood
        saveProfile()
    }

    func requestMusicAuthorization() {
        lastError = MusicError.libraryAccessDenied
    }

    func requestCatalogAuthorization() async {
        await MusicKitService.shared.requestAuthorization()
    }

    func refreshMusicAuthorizationStates() {
        isMusicAuthorized = false
        musicAuthorizationStatus = .unsupported
        MusicKitService.shared.refreshAuthorizationStatus()
    }

    func autoPopulateMusicPreferences() async {
        lastError = MusicError.libraryAccessDenied
    }

    func fetchPlaylists() async throws -> [ImportedPlaylist] {
        throw MusicError.libraryAccessDenied
    }

    func selectPlaylist(_ playlist: ImportedPlaylist?) {
        userProfile.musicPreferences.selectedPlaylist = playlist
        if playlist == nil {
            userProfile.musicPreferences.importedPlaylistArtists = []
            userProfile.musicPreferences.importedPlaylistSongs = []
            userProfile.musicPreferences.importedPlaylistGenres = []
        }
        saveProfile()
    }

    func importSelectedPlaylistPreferences() async throws {
        throw MusicError.libraryAccessDenied
    }

    func searchArtists(query: String) async throws -> [MusicArtist] {
        throw MusicError.libraryAccessDenied
    }

    func searchSongs(query: String) async throws -> [MusicSong] {
        throw MusicError.libraryAccessDenied
    }

    func getPopularGenres() async throws -> [MusicGenre] {
        [
            MusicGenre(id: "pop", name: "Pop", isSelected: false),
            MusicGenre(id: "rock", name: "Rock", isSelected: false),
            MusicGenre(id: "electronic", name: "Electronic", isSelected: false),
            MusicGenre(id: "hip-hop", name: "Hip-Hop", isSelected: false),
            MusicGenre(id: "alternative", name: "Alternative", isSelected: false),
            MusicGenre(id: "indie", name: "Indie", isSelected: false),
            MusicGenre(id: "country", name: "Country", isSelected: false),
            MusicGenre(id: "r-b", name: "R&B", isSelected: false),
            MusicGenre(id: "classical", name: "Classical", isSelected: false),
            MusicGenre(id: "jazz", name: "Jazz", isSelected: false)
        ]
    }

    func generateMusicContext(
        currentHeartRate: Int?,
        targetHeartRate: Int?,
        currentIntensity: Intensity,
        timeRemainingInSegment: TimeInterval,
        currentSongEndingIn: TimeInterval? = nil,
        currentDistance: Double? = nil,
        currentPace: Double? = nil,
        isActive: Bool = true
    ) -> MusicContext {
        MusicContext(
            currentHeartRate: currentHeartRate,
            guidanceHeartRate: currentHeartRate,
            targetHeartRate: targetHeartRate,
            heartRateTrend: .unknown,
            hasStableHeartRateSignal: currentHeartRate != nil,
            currentIntensity: currentIntensity,
            timeRemainingInSegment: timeRemainingInSegment,
            currentSongEndingIn: currentSongEndingIn,
            userPreferences: userProfile.musicPreferences,
            recentSongs: Array(userProfile.musicPreferences.allFavoriteSongs.prefix(5)),
            currentDistance: currentDistance,
            currentPace: currentPace,
            isActive: isActive
        )
    }

    private func saveProfile() {
        do {
            let data = try JSONEncoder().encode(userProfile)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            lastError = error
        }
    }

    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            userProfile = try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            lastError = error
            userProfile = UserProfile()
        }
    }
}

enum MusicError: LocalizedError {
    case notAuthorized
    case searchFailed
    case libraryAccessDenied
    case playlistNotFound
    case catalogAccessRequired
    case noPlayableMusicSource
    case songUnavailable
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Library access is required to import music taste from Apple Music."
        case .searchFailed:
            return "Failed to search music library"
        case .libraryAccessDenied:
            return "Local Apple Music library import is not available in the Mac Song Check build. Add taste inputs directly on the Song Check screen."
        case .playlistNotFound:
            return "The selected playlist could not be found in your library"
        case .catalogAccessRequired:
            return "Enable Apple Music playback so Pancake can play generated songs from the Apple Music catalog."
        case .noPlayableMusicSource:
            return "Pancake needs Apple Music playback access before it can play generated songs."
        case .songUnavailable:
            return "That generated song could not be found in Apple Music right now."
        case .playbackFailed:
            return "Pancake found the song, but playback did not start successfully."
        }
    }
}
