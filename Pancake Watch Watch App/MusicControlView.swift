import SwiftUI

struct MusicControlView: View {
    @ObservedObject private var musicManager = StandaloneMusicManager.shared
    @State private var showingSuggestion = false
    
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
                
                // AI Suggestion (Simplified for Watch)
                Button(action: {
                    // For standalone mode, just cycle through playlists
                    if let currentPlaylist = musicManager.currentPlaylist,
                       let currentIndex = musicManager.availablePlaylists.firstIndex(of: currentPlaylist) {
                        let nextIndex = (currentIndex + 1) % musicManager.availablePlaylists.count
                        musicManager.playPlaylist(musicManager.availablePlaylists[nextIndex])
                    }
                }) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Current Playlist Info
            if let playlist = musicManager.currentPlaylist {
                Text("Playing: \(playlist)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
#if os(watchOS)
        .background(Color.gray.opacity(0.15))
#else
        .background(Color(.systemGray6))
#endif
        .cornerRadius(8)
    }
}


#Preview {
    MusicControlView()
}
