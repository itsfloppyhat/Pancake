import Foundation
import MediaPlayer
import Combine

@MainActor
final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    @Published var userProfile: UserProfile
    @Published var isMusicAuthorized: Bool = false
    @Published var musicAuthorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published var lastError: Error?
    
    private let storageKey = "UserProfileManager.userProfile"
    private let queue = DispatchQueue(label: "UserProfileManager.queue")
    
    private init() {
        self.userProfile = UserProfile()
        loadProfile()
        checkMusicAuthorization()
    }
    
    // MARK: - Profile Management
    
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
    
    // MARK: - Music Preferences Management
    
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
    
    // MARK: - Apple Music Integration
    
    func requestMusicAuthorization() {
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.musicAuthorizationStatus = status
                self.isMusicAuthorized = status == .authorized
            }
        }
    }
    
    private func checkMusicAuthorization() {
        musicAuthorizationStatus = MPMediaLibrary.authorizationStatus()
        isMusicAuthorized = musicAuthorizationStatus == .authorized
    }
    
    // MARK: - Auto-Populate Music Preferences
    
    func autoPopulateMusicPreferences() async {
        guard isMusicAuthorized else { return }
        
        do {
            // Get most played artists
            let topArtists = try await getMostPlayedArtists()
            for artist in topArtists {
                addFavoriteArtist(artist)
            }
            
            // Get most played songs
            let topSongs = try await getMostPlayedSongs()
            for song in topSongs {
                addFavoriteSong(song)
            }
            
            // Get favorite genres from listening history
            let favoriteGenres = try await getFavoriteGenres()
            for genre in favoriteGenres {
                toggleGenre(genre)
            }
            
        } catch {
            print("Failed to auto-populate music preferences: \(error)")
        }
    }
    
    private func getMostPlayedArtists() async throws -> [MusicArtist] {
        let query = MPMediaQuery.artists()
        query.groupingType = .artist
        
        guard let collections = query.collections else { return [] }
        
        // Sort by play count and take top 10
        let sortedCollections = collections
            .sorted { collection1, collection2 in
                let count1 = collection1.items.reduce(0) { $0 + ($1.playCount) }
                let count2 = collection2.items.reduce(0) { $0 + ($1.playCount) }
                return count1 > count2
            }
            .prefix(10)
        
        return sortedCollections.compactMap { collection in
            guard let representativeItem = collection.representativeItem,
                  let artistName = representativeItem.artist else {
                return nil
            }
            
            return MusicArtist(
                id: artistName,
                name: artistName,
                artwork: nil,
                genres: []
            )
        }
    }
    
    private func getMostPlayedSongs() async throws -> [MusicSong] {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: 0, forProperty: MPMediaItemPropertyPlayCount, comparisonType: .contains))
        
        guard let items = query.items else { return [] }
        
        // Sort by play count and take top 20
        let sortedItems = items
            .sorted { $0.playCount > $1.playCount }
            .prefix(20)
        
        return sortedItems.compactMap { item in
            guard let title = item.title,
                  let artist = item.artist else {
                return nil
            }
            
            return MusicSong(
                id: "\(item.persistentID)",
                title: title,
                artist: artist,
                album: item.albumTitle,
                artwork: nil,
                duration: item.playbackDuration
            )
        }
    }
    
    private func getFavoriteGenres() async throws -> [MusicGenre] {
        let query = MPMediaQuery.songs()
        
        guard let items = query.items else { return [] }
        
        // Count genre occurrences
        var genreCounts: [String: Int] = [:]
        
        for item in items {
            if let genre = item.genre {
                genreCounts[genre, default: 0] += 1
            }
        }
        
        // Get top 5 genres
        let topGenres = genreCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
        
        // Map to our MusicGenre model
        return topGenres.map { genreName in
            MusicGenre(id: genreName.lowercased(), name: genreName, isSelected: true)
        }
    }
    
    // MARK: - Music Library Access
    
    func searchArtists(query: String) async throws -> [MusicArtist] {
        guard isMusicAuthorized else {
            throw MusicError.notAuthorized
        }
        
        // Use MPMediaQuery to search for artists in user's library
        let query = MPMediaQuery.artists()
        let predicate = MPMediaPropertyPredicate(value: query, forProperty: MPMediaItemPropertyArtist, comparisonType: .contains)
        query.addFilterPredicate(predicate)
        
        guard let collections = query.collections else {
            return []
        }
        
        return collections.compactMap { collection in
            guard let representativeItem = collection.representativeItem,
                  let artistName = representativeItem.artist else {
                return nil
            }
            
            return MusicArtist(
                id: artistName,
                name: artistName,
                artwork: nil, // MPMediaItem doesn't provide artwork URLs directly
                genres: []
            )
        }
    }
    
    func searchSongs(query: String) async throws -> [MusicSong] {
        guard isMusicAuthorized else {
            throw MusicError.notAuthorized
        }
        
        // Use MPMediaQuery to search for songs in user's library
        let mediaQuery = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(value: query, forProperty: MPMediaItemPropertyTitle, comparisonType: .contains)
        mediaQuery.addFilterPredicate(predicate)
        
        guard let items = mediaQuery.items else {
            return []
        }
        
        return items.compactMap { item in
            guard let title = item.title,
                  let artist = item.artist else {
                return nil
            }
            
            return MusicSong(
                id: "\(item.persistentID)",
                title: title,
                artist: artist,
                album: item.albumTitle,
                artwork: nil, // MPMediaItem doesn't provide artwork URLs directly
                duration: item.playbackDuration
            )
        }
    }
    
    func getPopularGenres() async throws -> [MusicGenre] {
        guard isMusicAuthorized else {
            throw MusicError.notAuthorized
        }
        
        // Return a curated list of popular genres for running
        return [
            MusicGenre(id: "pop", name: "Pop", isSelected: false),
            MusicGenre(id: "rock", name: "Rock", isSelected: false),
            MusicGenre(id: "electronic", name: "Electronic", isSelected: false),
            MusicGenre(id: "hip-hop", name: "Hip-Hop", isSelected: false),
            MusicGenre(id: "alternative", name: "Alternative", isSelected: false),
            MusicGenre(id: "indie", name: "Indie", isSelected: false),
            MusicGenre(id: "country", name: "Country", isSelected: false),
            MusicGenre(id: "r&b", name: "R&B", isSelected: false),
            MusicGenre(id: "classical", name: "Classical", isSelected: false),
            MusicGenre(id: "jazz", name: "Jazz", isSelected: false)
        ]
    }
    
    // MARK: - AI Context Generation
    
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
        return MusicContext(
            currentHeartRate: currentHeartRate,
            targetHeartRate: targetHeartRate,
            currentIntensity: currentIntensity,
            timeRemainingInSegment: timeRemainingInSegment,
            currentSongEndingIn: currentSongEndingIn,
            userPreferences: userProfile.musicPreferences,
            recentSongs: Array(userProfile.musicPreferences.favoriteSongs.prefix(5)),
            currentDistance: currentDistance,
            currentPace: currentPace,
            isActive: isActive
        )
    }
    
    // MARK: - Storage
    
    private func saveProfile() {
        let profile = userProfile
        let key = storageKey
        
        queue.async {
            do {
                let data = try JSONEncoder().encode(profile)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                print("Failed to save user profile: \(error)")
            }
        }
    }
    
    private func loadProfile() {
        queue.async { [weak self] in
            guard let data = UserDefaults.standard.data(forKey: self?.storageKey ?? "") else {
                DispatchQueue.main.async {
                    self?.userProfile = UserProfile()
                }
                return
            }
            
            do {
                let profile = try JSONDecoder().decode(UserProfile.self, from: data)
                DispatchQueue.main.async {
                    self?.userProfile = profile
                }
            } catch {
                print("Failed to load user profile: \(error)")
                DispatchQueue.main.async {
                    self?.userProfile = UserProfile()
                }
            }
        }
    }
}

// MARK: - Music Errors
enum MusicError: LocalizedError {
    case notAuthorized
    case searchFailed
    case libraryAccessDenied
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music authorization is required"
        case .searchFailed:
            return "Failed to search music library"
        case .libraryAccessDenied:
            return "Access to music library was denied"
        }
    }
}
