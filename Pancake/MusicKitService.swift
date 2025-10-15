import Foundation
import MusicKit
import MediaPlayer

@MainActor
class MusicKitService: ObservableObject {
    static let shared = MusicKitService()
    
    @Published var isAuthorized = false
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var playbackError: Error?
    
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    
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
        print("🎵 MusicKit authorization status: \(status)")
    }
    
    private func updateAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
        isAuthorized = (authorizationStatus == .authorized)
        print("🎵 Current MusicKit authorization: \(authorizationStatus)")
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
        
        do {
            // Use MPMusicPlayerController for playback
            let player = MPMusicPlayerController.applicationQueuePlayer
            
            // Create a queue descriptor with the song's store ID
            let storeID = song.id.rawValue
            let queue = MPMusicPlayerStoreQueueDescriptor(storeIDs: [storeID])
            player.setQueue(with: queue)
            player.play()
            
            await MainActor.run {
                self.currentSong = song
                self.isPlaying = true
                self.playbackError = nil
            }
            
            print("🎵 Playing Apple Music song: '\(song.title)' by \(song.artistName)")
        } catch {
            print("❌ Error playing Apple Music song: \(error)")
            await MainActor.run {
                self.playbackError = error
            }
            throw error
        }
    }
    
    func playSongs(_ songs: [Song]) async throws {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }
        
        do {
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
                
                print("🎵 Playing Apple Music playlist with \(songs.count) songs")
            } else {
                throw MusicKitError.playbackFailed
            }
        } catch {
            print("❌ Error playing Apple Music playlist: \(error)")
            await MainActor.run {
                self.playbackError = error
            }
            throw error
        }
    }
    
    func pause() async {
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.pause()
        await MainActor.run {
            self.isPlaying = false
        }
    }
    
    func resume() async {
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.play()
        await MainActor.run {
            self.isPlaying = true
        }
    }
    
    func stop() async {
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.stop()
        await MainActor.run {
            self.isPlaying = false
            self.currentSong = nil
        }
    }
    
    // MARK: - Notifications
    
    private func setupMusicPlayerNotifications() {
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
    }
    
    @objc private func nowPlayingItemDidChange() {
        Task { @MainActor in
            // Update current song if needed
            if let nowPlayingItem = musicPlayer.nowPlayingItem {
                // Convert MPMediaItem to Song if possible
                // This is a simplified approach - in practice you might need more complex conversion
                print("🎵 Now playing: \(nowPlayingItem.title ?? "Unknown") by \(nowPlayingItem.artist ?? "Unknown")")
            }
        }
    }
    
    @objc private func playbackStateDidChange() {
        Task { @MainActor in
            let state = musicPlayer.playbackState
            self.isPlaying = (state == .playing)
            print("🎵 Playback state changed: \(state.rawValue)")
        }
    }
    
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
