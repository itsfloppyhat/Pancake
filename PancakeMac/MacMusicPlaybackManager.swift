import AppKit
import Combine
import Foundation
import MusicKit

@MainActor
final class MusicPlaybackManager: ObservableObject {
    static let shared = MusicPlaybackManager()

    @Published var isPlaying = false
    @Published var currentSong: MusicSong?
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var currentSongDuration: TimeInterval = 0
    @Published var isGeneratingSuggestion = false
    @Published var lastSuggestion: MusicSuggestion?
    @Published var playbackError: Error?
    @Published var playbackStateDescription = "stopped"

    private var cancellables = Set<AnyCancellable>()

    var hasLibraryAccess: Bool {
        false
    }

    var hasCatalogAccess: Bool {
        MusicKitService.shared.isAuthorized
    }

    var hasAvailablePlaybackSource: Bool {
        hasCatalogAccess
    }

    private init() {
        MusicKitService.shared.$isPlaying
            .sink { [weak self] isPlaying in
                self?.isPlaying = isPlaying
                self?.playbackStateDescription = isPlaying ? "playing" : "stopped"
            }
            .store(in: &cancellables)

        MusicKitService.shared.$playbackError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.playbackError = error
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func playSuggestedSong(_ suggestion: MusicSuggestion) async -> Bool {
        guard hasCatalogAccess else {
            updatePlaybackFailure(MusicError.catalogAccessRequired, state: "enable Apple Music playback")
            return false
        }

        return await playAppleMusicSuggestion(suggestion.cleanedTitle())
    }

    @discardableResult
    func playAppleMusicSuggestion(_ suggestion: MusicSuggestion) async -> Bool {
        let cleanedSuggestion = suggestion.cleanedTitle()

        do {
            guard hasCatalogAccess else {
                throw MusicError.catalogAccessRequired
            }

            let bestMatch = try await bestMusicKitCatalogSong(for: cleanedSuggestion)
            let resolvedSuggestion = cleanedSuggestion.resolvedToCatalogTrack(
                title: bestMatch.title,
                artist: bestMatch.artistName
            )

            try await MusicKitService.shared.playSong(bestMatch)
            try? await Task.sleep(nanoseconds: 500_000_000)

            guard MusicKitService.shared.isPlaying else {
                updatePlaybackFailure(MusicError.playbackFailed, state: "playback failed")
                return false
            }

            applyAppleMusicNowPlaying(suggestion: resolvedSuggestion, duration: bestMatch.duration)
            clearPlaybackFailure()
            return true
        } catch {
            if await openCatalogFallbackInMusic(for: cleanedSuggestion) {
                updatePlaybackFailure(MusicError.playbackFailed, state: "opened in Music")
            } else {
                updatePlaybackFailure(error, state: "apple music playback failed")
            }
            return false
        }
    }

    func validateAppleMusicSuggestion(_ suggestion: MusicSuggestion) async throws -> MusicSuggestion {
        let cleanedSuggestion = suggestion.cleanedTitle()

        if hasCatalogAccess {
            do {
                let bestMatch = try await bestMusicKitCatalogSong(for: cleanedSuggestion)
                return cleanedSuggestion.resolvedToCatalogTrack(
                    title: bestMatch.title,
                    artist: bestMatch.artistName
                )
            } catch {
                if let fallback = try await bestITunesCatalogMatch(for: cleanedSuggestion) {
                    return cleanedSuggestion.resolvedToCatalogTrack(
                        title: fallback.trackName,
                        artist: fallback.artistName
                    )
                }
                throw error
            }
        }

        guard let fallback = try await bestITunesCatalogMatch(for: cleanedSuggestion) else {
            throw MusicError.songUnavailable
        }

        return cleanedSuggestion.resolvedToCatalogTrack(
            title: fallback.trackName,
            artist: fallback.artistName
        )
    }

    func stop() {
        Task {
            await MusicKitService.shared.stop()
            currentSong = nil
            currentPlaybackTime = 0
            currentSongDuration = 0
            playbackStateDescription = "stopped"
            isPlaying = false
        }
    }

    func play() {
        Task {
            await MusicKitService.shared.resume()
            isPlaying = MusicKitService.shared.isPlaying
            playbackStateDescription = isPlaying ? "playing" : "stopped"
        }
    }

    private func fetchCatalogCandidates(for suggestion: MusicSuggestion) async throws -> [Song] {
        let primaryQuery = "\(suggestion.songTitle) \(suggestion.artist)"
        let primaryResults = try await MusicKitService.shared.searchSongs(query: primaryQuery, limit: 10)
        if bestCatalogMatch(in: primaryResults, for: suggestion) != nil {
            return primaryResults
        }

        var seenSongIDs = Set<String>()
        var combinedResults: [Song] = []

        for song in primaryResults {
            let storeID = song.id.rawValue
            if seenSongIDs.insert(storeID).inserted {
                combinedResults.append(song)
            }
        }

        for query in [suggestion.songTitle, "\(suggestion.artist) \(suggestion.songTitle)"] {
            let songs = try await MusicKitService.shared.searchSongs(query: query, limit: 10)

            for song in songs {
                let storeID = song.id.rawValue
                if seenSongIDs.insert(storeID).inserted {
                    combinedResults.append(song)
                }
            }
        }

        return combinedResults
    }

    private func bestMusicKitCatalogSong(for suggestion: MusicSuggestion) async throws -> Song {
        let songs = try await fetchCatalogCandidates(for: suggestion)

        guard let bestMatch = bestCatalogMatch(in: songs, for: suggestion) else {
            throw MusicError.songUnavailable
        }

        return bestMatch
    }

    private func applyAppleMusicNowPlaying(suggestion: MusicSuggestion, duration: TimeInterval?) {
        lastSuggestion = suggestion
        currentSong = MusicSong(
            id: suggestion.id.uuidString,
            title: suggestion.songTitle,
            artist: suggestion.artist,
            album: nil,
            artwork: nil,
            duration: duration ?? 0
        )
        currentSongDuration = duration ?? 0
        currentPlaybackTime = 0
        isPlaying = true
        playbackStateDescription = "playing"
        playbackError = nil
    }

    private func clearPlaybackFailure() {
        playbackError = nil
        if !isPlaying {
            playbackStateDescription = "stopped"
        }
    }

    private func updatePlaybackFailure(_ error: Error, state: String) {
        playbackError = error
        playbackStateDescription = state
        isPlaying = MusicKitService.shared.isPlaying
    }

    private func normalize(_ text: String) -> String {
        text.normalizedMusicIdentity
    }

    private func scoreMatch(itemTitle: String, itemArtist: String, sugTitle: String, sugArtist: String) -> Int {
        let itemTitle = normalize(itemTitle)
        let itemArtist = normalize(itemArtist)
        let suggestionTitle = normalize(sugTitle)
        let suggestionArtist = normalize(sugArtist)

        var score = 0
        if itemTitle == suggestionTitle {
            score += 3
        } else if itemTitle.contains(suggestionTitle) || suggestionTitle.contains(itemTitle) {
            score += 2
        }

        if itemArtist == suggestionArtist {
            score += 3
        } else if itemArtist.contains(suggestionArtist) || suggestionArtist.contains(itemArtist) {
            score += 1
        }

        return score
    }

    private func isGoodEnough(score: Int) -> Bool {
        score >= 5
    }

    private func bestCatalogMatch(in songs: [Song], for suggestion: MusicSuggestion) -> Song? {
        let exactMatch = songs.first { song in
            normalize(song.title) == normalize(suggestion.songTitle) &&
            normalize(song.artistName) == normalize(suggestion.artist)
        }
        if let exactMatch {
            return exactMatch
        }

        var bestSong: Song?
        var bestScore = 0

        for song in songs {
            let score = scoreMatch(
                itemTitle: song.title,
                itemArtist: song.artistName,
                sugTitle: suggestion.songTitle,
                sugArtist: suggestion.artist
            )

            if score > bestScore {
                bestScore = score
                bestSong = song
            }
        }

        guard let bestSong, isGoodEnough(score: bestScore) else {
            return nil
        }

        return bestSong
    }

    private func bestITunesCatalogMatch(for suggestion: MusicSuggestion) async throws -> ITunesSongResult? {
        let queries = [
            "\(suggestion.songTitle) \(suggestion.artist)",
            "\(suggestion.artist) \(suggestion.songTitle)",
            suggestion.songTitle
        ]

        var seenTrackIDs = Set<Int>()
        var candidates: [ITunesSongResult] = []

        for query in queries {
            let results = try await searchITunesSongs(query: query, limit: 15)
            for result in results where seenTrackIDs.insert(result.trackId).inserted {
                candidates.append(result)
            }
        }

        return bestITunesMatch(in: candidates, for: suggestion)
    }

    private func searchITunesSongs(query: String, limit: Int) async throws -> [ITunesSongResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        guard let url = components?.url else {
            throw MusicError.searchFailed
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw MusicError.searchFailed
        }

        return try JSONDecoder().decode(ITunesSearchResponse.self, from: data).results
    }

    private func bestITunesMatch(in songs: [ITunesSongResult], for suggestion: MusicSuggestion) -> ITunesSongResult? {
        var bestSong: ITunesSongResult?
        var bestScore = 0

        for song in songs {
            let score = scoreMatch(
                itemTitle: song.trackName,
                itemArtist: song.artistName,
                sugTitle: suggestion.songTitle,
                sugArtist: suggestion.artist
            )

            if score > bestScore {
                bestScore = score
                bestSong = song
            }
        }

        guard let bestSong, isGoodEnough(score: bestScore) else {
            return nil
        }

        return bestSong
    }

    private func openCatalogFallbackInMusic(for suggestion: MusicSuggestion) async -> Bool {
        guard let fallback = try? await bestITunesCatalogMatch(for: suggestion),
              let trackURL = fallback.trackViewUrl else {
            return false
        }

        lastSuggestion = suggestion.resolvedToCatalogTrack(
            title: fallback.trackName,
            artist: fallback.artistName
        )
        currentSong = MusicSong(
            id: "itunes-\(fallback.trackId)",
            title: fallback.trackName,
            artist: fallback.artistName,
            duration: TimeInterval(fallback.trackTimeMillis ?? 0) / 1000
        )
        currentPlaybackTime = 0
        currentSongDuration = TimeInterval(fallback.trackTimeMillis ?? 0) / 1000

        return NSWorkspace.shared.open(trackURL)
    }
}

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesSongResult]
}

private struct ITunesSongResult: Decodable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let trackViewUrl: URL?
    let trackTimeMillis: Int?
}
