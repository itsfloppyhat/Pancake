import Combine
import Foundation
import MusicKit

@MainActor
final class MusicKitService: ObservableObject {
    static let shared = MusicKitService()

    @Published var isAuthorized = false
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var playbackError: Error?

    private let player = ApplicationMusicPlayer.shared
    private var stateCancellable: AnyCancellable?
    private let playbackStartTimeoutSeconds: TimeInterval = 8

    private init() {
        updateAuthorizationStatus()
        observePlaybackState()
    }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authorizationStatus = status
        isAuthorized = (status == .authorized)
    }

    func refreshAuthorizationStatus() {
        updateAuthorizationStatus()
    }

    private func updateAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
        isAuthorized = (authorizationStatus == .authorized)
    }

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

    func playSong(_ song: Song) async throws {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }

        do {
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            try await startPlaybackWithTimeout()
        } catch {
            playbackError = error
            syncPlaybackState()
            throw error
        }

        currentSong = song
        playbackError = nil
        syncPlaybackState()
    }

    func playSongs(_ songs: [Song]) async throws {
        guard isAuthorized else {
            throw MusicKitError.notAuthorized
        }

        guard !songs.isEmpty else {
            playbackError = MusicKitError.playbackFailed
            throw MusicKitError.playbackFailed
        }

        do {
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try await startPlaybackWithTimeout()
        } catch {
            playbackError = error
            syncPlaybackState()
            throw error
        }

        currentSong = songs.first
        playbackError = nil
        syncPlaybackState()
    }

    func pause() async {
        player.pause()
        syncPlaybackState()
    }

    func resume() async {
        do {
            try await player.play()
            playbackError = nil
        } catch {
            playbackError = error
        }
        syncPlaybackState()
    }

    func stop() async {
        player.stop()
        currentSong = nil
        syncPlaybackState()
    }

    private func startPlaybackWithTimeout() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await self.player.prepareToPlay()
                try await self.player.play()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.playbackStartTimeoutSeconds * 1_000_000_000))
                throw MusicKitError.playbackTimedOut
            }

            guard let _ = try await group.next() else {
                throw MusicKitError.playbackTimedOut
            }

            group.cancelAll()
        }
    }

    private func observePlaybackState() {
        stateCancellable = player.state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPlaybackState()
                }
            }
    }

    private func syncPlaybackState() {
        isPlaying = player.state.playbackStatus == .playing
    }
}

enum MusicKitError: Error, LocalizedError {
    case notAuthorized
    case searchFailed
    case playbackFailed
    case playbackTimedOut

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access not authorized"
        case .searchFailed:
            return "Failed to search Apple Music catalog"
        case .playbackFailed:
            return "Failed to play Apple Music song"
        case .playbackTimedOut:
            return "Apple Music playback did not respond. Open the Music app, confirm you are signed in, then try playback again."
        }
    }
}

extension Song {
    var displayTitle: String {
        title
    }

    var displayArtist: String {
        artistName
    }

    var displayDuration: String {
        let minutes = Int(duration ?? 0) / 60
        let seconds = Int(duration ?? 0) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
