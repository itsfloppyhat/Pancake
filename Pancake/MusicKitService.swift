import Foundation
import MusicKit
#if !os(macOS)
import MediaPlayer
#endif

@MainActor
class MusicKitService: ObservableObject {
    static let shared = MusicKitService()
    
    @Published var isAuthorized = false
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var playbackError: Error?
    
    #if os(macOS)
    private let musicPlayer = ApplicationMusicPlayer.shared
    #else
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    #endif
    
    private init() {
        updateAuthorizationStatus()
        setupMusicPlayerNotifications()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        await MainActor.run {
            self.authorizationStatus = status
            self.isAuthorized = (status == .authorized)
        }
    }

    func refreshAuthorizationStatus() {
        updateAuthorizationStatus()
    }
    
    private func updateAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
        isAuthorized = (authorizationStatus == .authorized)
    }
    
    // MARK: - Search
    
    func searchSongs(query: String, limit: Int = 25) async throws -> [Song] {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }
        
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = limit
        
        let response = try await request.response()
        return Array(response.songs)
    }
    
    func searchSongsByArtist(_ artist: String, limit: Int = 25) async throws -> [Song] {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }
        
        var request = MusicCatalogSearchRequest(term: artist, types: [Song.self])
        request.limit = limit
        
        let response = try await request.response()
        return Array(response.songs).filter { song in
            song.artistName.lowercased().contains(artist.lowercased())
        }
    }
    
    func searchSongsByTitle(_ title: String, limit: Int = 25) async throws -> [Song] {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }
        
        var request = MusicCatalogSearchRequest(term: title, types: [Song.self])
        request.limit = limit
        
        let response = try await request.response()
        return Array(response.songs).filter { song in
            song.title.lowercased().contains(title.lowercased())
        }
    }
    
    // MARK: - Playback
    
    func playSong(_ song: Song) async throws {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }
        
        #if os(macOS)
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [song])
        try await player.prepareToPlay()
        try await player.play()

        try? await Task.sleep(nanoseconds: 500_000_000)
        guard player.state.playbackStatus == .playing else {
            await MainActor.run {
                self.playbackError = MusicKitError.playbackFailed
                self.isPlaying = false
            }
            throw MusicKitError.playbackFailed
        }
        #else
        // Use MPMusicPlayerController for playback
        let player = MPMusicPlayerController.applicationQueuePlayer
        
        // Create a queue descriptor with the song's store ID
        let storeID = song.id.rawValue
        let queue = MPMusicPlayerStoreQueueDescriptor(storeIDs: [storeID])
        player.setQueue(with: queue)
        player.play()

        try? await Task.sleep(nanoseconds: 500_000_000)
        guard player.playbackState == .playing else {
            await MainActor.run {
                self.playbackError = MusicKitError.playbackFailed
                self.isPlaying = false
            }
            throw MusicKitError.playbackFailed
        }
        #endif
        
        await MainActor.run {
            self.currentSong = song
            self.isPlaying = true
            self.playbackError = nil
        }
        
    }
    
    func playSongs(_ songs: [Song]) async throws {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }
        
        #if os(macOS)
        let player = ApplicationMusicPlayer.shared

        guard !songs.isEmpty else {
            await MainActor.run {
                self.playbackError = MusicKitError.playbackFailed
            }
            throw MusicKitError.playbackFailed
        }

        player.queue = ApplicationMusicPlayer.Queue(for: songs)
        try await player.prepareToPlay()
        try await player.play()

        try? await Task.sleep(nanoseconds: 500_000_000)
        guard player.state.playbackStatus == .playing else {
            await MainActor.run {
                self.playbackError = MusicKitError.playbackFailed
                self.isPlaying = false
            }
            throw MusicKitError.playbackFailed
        }

        await MainActor.run {
            self.currentSong = songs.first
            self.isPlaying = true
            self.playbackError = nil
        }
        #else
        let player = MPMusicPlayerController.applicationQueuePlayer
        let storeIDs = songs.map { $0.id.rawValue }
        
        if !storeIDs.isEmpty {
            let queue = MPMusicPlayerStoreQueueDescriptor(storeIDs: storeIDs)
            player.setQueue(with: queue)
            player.play()
            
            await MainActor.run {
                self.currentSong = songs.first
                self.isPlaying = true
                self.playbackError = nil
            }
            
        } else {
            await MainActor.run {
                self.playbackError = MusicKitError.playbackFailed
            }
            throw MusicKitError.playbackFailed
        }
        #endif
    }
    
    func pause() async {
        #if os(macOS)
        let player = ApplicationMusicPlayer.shared
        player.pause()
        #else
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.pause()
        #endif
        await MainActor.run {
            self.isPlaying = false
        }
    }
    
    func resume() async {
        #if os(macOS)
        let player = ApplicationMusicPlayer.shared
        try? await player.play()
        let isNowPlaying = player.state.playbackStatus == .playing
        #else
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.play()
        let isNowPlaying = true
        #endif
        await MainActor.run {
            self.isPlaying = isNowPlaying
        }
    }
    
    func stop() async {
        #if os(macOS)
        let player = ApplicationMusicPlayer.shared
        player.stop()
        #else
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.stop()
        #endif
        await MainActor.run {
            self.isPlaying = false
            self.currentSong = nil
        }
    }
    
    // MARK: - Notifications
    
    private func setupMusicPlayerNotifications() {
        #if !os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemDidChange),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: musicPlayer
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateDidChange),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: musicPlayer
        )
        #endif
    }
    
    #if !os(macOS)
    @objc private func nowPlayingItemDidChange() {
        Task { @MainActor in
            // Update current song if needed
        }
    }

    @objc private func playbackStateDidChange() {
        Task { @MainActor in
            let state = musicPlayer.playbackState
            self.isPlaying = (state == .playing)
        }
    }
    #endif
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Errors

enum MusicKitError: Error, LocalizedError {
    case notAuthorized
    case searchFailed
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access not authorized"
        case .searchFailed:
            return "Failed to search Apple Music catalog"
        case .playbackFailed:
            return "Failed to play Apple Music song"
        }
    }
}

// MARK: - Extensions

extension Song {
    var displayTitle: String {
        return title
    }
    
    var displayArtist: String {
        return artistName
    }
    
    var displayDuration: String {
        let minutes = Int(duration ?? 0) / 60
        let seconds = Int(duration ?? 0) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
