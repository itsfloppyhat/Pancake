import SwiftUI
import WatchConnectivity

struct ConnectedMusicControlView: View {
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @State private var showingSuggestion = false
    
    var body: some View {
        VStack(spacing: 4) {
            // Current Song Info
            if let currentSong = watchConnectivity.currentSong {
                VStack(spacing: 2) {
                    Text(currentSong.title)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(currentSong.artist)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No song playing")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Music Controls
            HStack(spacing: 12) {
                // Play/Pause
                Button(action: {
                    if watchConnectivity.isPlaying {
                        sendMusicControl("pause")
                    } else {
                        sendMusicControl("play")
                    }
                }) {
                    Image(systemName: watchConnectivity.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                // AI Suggestion (Generate New Song)
                Button(action: {
                    sendMusicControl("suggest")
                }) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Playback State
            if watchConnectivity.isPlaying {
                Text("Playing on iPhone")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else if watchConnectivity.playbackState == "paused" {
                Text("Paused on iPhone")
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else {
                Text("Stopped")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
#if os(watchOS)
        .background(Color.gray.opacity(0.15))
#else
        .background(Color(.systemGray6))
#endif
        .cornerRadius(8)
    }
    
    private func sendMusicControl(_ action: String) {
        let message: [String: Any] = [
            "type": "musicControl",
            "action": action
        ]
        
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil as (([String : Any]) -> Void)?) { error in
                print("Failed to send music control: \(error)")
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }
    
}

#Preview {
    ConnectedMusicControlView()
}
