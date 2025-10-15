import Foundation
import WatchKit
import SwiftUI

// MARK: - Music Models for Watch
struct MusicSong: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artwork: String?
    let duration: TimeInterval
    
    init(id: String, title: String, artist: String, album: String? = nil, artwork: String? = nil, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.duration = duration
    }
}

// MARK: - Standalone Music Manager for Apple Watch
@MainActor
final class StandaloneMusicManager: ObservableObject {
    static let shared = StandaloneMusicManager()
    
    @Published var isPlaying = false
    @Published var currentSong: MusicSong?
    @Published var availablePlaylists: [String] = []
    @Published var currentPlaylist: String?
    
    // For watchOS, we'll use system music controls
    // Note: WKAudioFilePlayer was deprecated in watchOS 6.0
    
    private init() {
        setupMusicPlayer()
        loadAvailablePlaylists()
    }
    
    // MARK: - Setup
    
    private func setupMusicPlayer() {
        // For watchOS, we'll use system music controls
        // No need for MediaPlayer setup
    }
    
    private func loadAvailablePlaylists() {
        // For watchOS, we'll use predefined playlist names
        // that match common Apple Music playlist names
        availablePlaylists = [
            "Running",
            "Workout",
            "Easy Run",
            "Chill",
            "Energy",
            "Pop",
            "Rock",
            "Electronic"
        ]
    }
    
    // MARK: - Workout Music Selection
    
    func selectWorkoutPlaylist(for intensity: Intensity) {
        let playlistName = getPlaylistName(for: intensity)
        
        // Try to find a matching playlist
        if let playlist = availablePlaylists.first(where: { $0.lowercased().contains(playlistName.lowercased()) }) {
            playPlaylist(playlist)
        } else {
            // Fallback: use first available playlist
            if let firstPlaylist = availablePlaylists.first {
                playPlaylist(firstPlaylist)
            }
        }
    }
    
    private func getPlaylistName(for intensity: Intensity) -> String {
        switch intensity {
        case .easy:
            return "Easy Run"
        case .medium:
            return "Running"
        case .hard:
            return "Workout"
        }
    }
    
    func playPlaylist(_ playlist: String) {
        currentPlaylist = playlist
        // For watchOS, we'll simulate playlist selection
        // In a real implementation, this would trigger system music controls
        isPlaying = true
        
        // Create a mock current song for display
        currentSong = MusicSong(
            id: UUID().uuidString,
            title: "Playing from \(playlist)",
            artist: "Apple Music",
            album: nil,
            artwork: nil,
            duration: 180.0
        )
    }
    
    // MARK: - Smart Music Selection (Standalone)
    
    func selectSmartMusicForWorkout(
        intensity: Intensity,
        heartRate: Int?,
        timeRemaining: TimeInterval
    ) {
        // Simple heuristic-based music selection without AI
        let musicStrategy = determineMusicStrategy(
            intensity: intensity,
            heartRate: heartRate,
            timeRemaining: timeRemaining
        )
        
        switch musicStrategy {
        case .calmDown:
            selectCalmingMusic()
        case .energize:
            selectEnergizingMusic()
        case .maintain:
            selectMaintainingMusic()
        case .finishStrong:
            selectFinishingMusic()
        }
    }
    
    private enum MusicStrategy {
        case calmDown
        case energize
        case maintain
        case finishStrong
    }
    
    private func determineMusicStrategy(
        intensity: Intensity,
        heartRate: Int?,
        timeRemaining: TimeInterval
    ) -> MusicStrategy {
        // Simple rules for music selection
        if timeRemaining < 60 {
            return .finishStrong
        }
        
        if let hr = heartRate {
            switch intensity {
            case .easy:
                if hr > 150 {
                    return .calmDown
                } else {
                    return .maintain
                }
            case .medium:
                if hr > 170 {
                    return .calmDown
                } else if hr < 140 {
                    return .energize
                } else {
                    return .maintain
                }
            case .hard:
                if hr > 180 {
                    return .calmDown
                } else if hr < 160 {
                    return .energize
                } else {
                    return .maintain
                }
            }
        }
        
        return .maintain
    }
    
    private func selectCalmingMusic() {
        // Look for calming playlists or slower songs
        let calmingKeywords = ["chill", "relax", "easy", "slow", "acoustic"]
        selectPlaylistWithKeywords(calmingKeywords)
    }
    
    private func selectEnergizingMusic() {
        // Look for energizing playlists or faster songs
        let energizingKeywords = ["workout", "energy", "upbeat", "fast", "rock", "pop"]
        selectPlaylistWithKeywords(energizingKeywords)
    }
    
    private func selectMaintainingMusic() {
        // Look for steady, maintaining playlists
        let maintainingKeywords = ["running", "steady", "pace", "endurance"]
        selectPlaylistWithKeywords(maintainingKeywords)
    }
    
    private func selectFinishingMusic() {
        // Look for finishing strong playlists
        let finishingKeywords = ["finish", "strong", "victory", "celebration", "power"]
        selectPlaylistWithKeywords(finishingKeywords)
    }
    
    private func selectPlaylistWithKeywords(_ keywords: [String]) {
        for keyword in keywords {
            if let playlist = availablePlaylists.first(where: { 
                $0.lowercased().contains(keyword) 
            }) {
                playPlaylist(playlist)
                return
            }
        }
        
        // Fallback to first available playlist
        if let firstPlaylist = availablePlaylists.first {
            playPlaylist(firstPlaylist)
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        isPlaying = true
        // In a real implementation, this would trigger system music controls
    }
    
    func pause() {
        isPlaying = false
        // In a real implementation, this would trigger system music controls
    }
    
    func skipToNext() {
        // In a real implementation, this would trigger system music controls
        // For now, we'll just update the mock song
        if let playlist = currentPlaylist {
            currentSong = MusicSong(
                id: UUID().uuidString,
                title: "Next song from \(playlist)",
                artist: "Apple Music",
                album: nil,
                artwork: nil,
                duration: 180.0
            )
        }
    }
    
    func skipToPrevious() {
        // In a real implementation, this would trigger system music controls
        // For now, we'll just update the mock song
        if let playlist = currentPlaylist {
            currentSong = MusicSong(
                id: UUID().uuidString,
                title: "Previous song from \(playlist)",
                artist: "Apple Music",
                album: nil,
                artwork: nil,
                duration: 180.0
            )
        }
    }
    
    func setVolume(_ volume: Float) {
        // Volume control would be handled by system controls on watchOS
    }
}

// MARK: - Standalone Music Control View
struct StandaloneMusicControlView: View {
    @StateObject private var musicManager = StandaloneMusicManager.shared
    @State private var showingPlaylistSelection = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Current Song Info
            if let currentSong = musicManager.currentSong {
                VStack(spacing: 4) {
                    Text(currentSong.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(currentSong.artist)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No song playing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Music Controls
            HStack(spacing: 12) {
                // Previous Song
                Button(action: {
                    musicManager.skipToPrevious()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                // Play/Pause
                Button(action: {
                    if musicManager.isPlaying {
                        musicManager.pause()
                    } else {
                        musicManager.play()
                    }
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                // Next Song
                Button(action: {
                    musicManager.skipToNext()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                // Playlist Selection
                Button(action: {
                    showingPlaylistSelection = true
                }) {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Current Playlist
            if let playlist = musicManager.currentPlaylist, !playlist.isEmpty {
                Text(playlist)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("No Playlist Selected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
        .sheet(isPresented: $showingPlaylistSelection) {
            PlaylistSelectionView()
        }
    }
}

struct PlaylistSelectionView: View {
    @StateObject private var musicManager = StandaloneMusicManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(musicManager.availablePlaylists, id: \.self) { playlist in
                    Button(action: {
                        musicManager.playPlaylist(playlist)
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("Apple Music Playlist")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if musicManager.currentPlaylist == playlist {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    StandaloneMusicControlView()
}

