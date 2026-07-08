import SwiftUI
import WatchConnectivity

struct ConnectedMusicControlView: View {
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @State private var isRequestingSong = false
    /// Track the song ID when the request was made so we know when it actually changes
    @State private var songIDWhenRequested: String?

    var body: some View {
        VStack(spacing: 4) {
            // Current Song Info
            if let currentSong = watchConnectivity.currentSong {
                VStack(spacing: 2) {
                    Text(currentSong.title)
                        .font(.footnote)
                        .fontWeight(.semibold)
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

            // What the mix is doing for the runner right now
            if watchConnectivity.isAdaptiveMixActive,
               let guidance = watchConnectivity.adaptiveMixGuidanceText {
                Text(guidance)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if watchConnectivity.isAdaptiveMixActive,
               let nextTitle = watchConnectivity.adaptiveMixNextSongTitle {
                Text("Next: \(nextTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Next song")
                    .accessibilityValue(nextTitle)
            }

            Button(action: startAdaptiveMix) {
                HStack(spacing: 4) {
                    if watchConnectivity.isAdaptiveMixCurating {
                        ProgressView()
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: watchConnectivity.isAdaptiveMixActive ? "waveform.path.ecg" : "play.circle.fill")
                    }

                    Text(watchConnectivity.isAdaptiveMixActive ? "Adaptive Mix" : "Start Adaptive Mix")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(watchConnectivity.isAdaptiveMixActive ? .green : .blue)
            .disabled(watchConnectivity.isAdaptiveMixActive || watchConnectivity.isAdaptiveMixCurating)

            // Music Controls
            HStack(spacing: 10) {
                // Play / Pause
                Button(action: {
                    sendMusicControl(watchConnectivity.isPlaying ? "pause" : "play")
                }) {
                    Image(systemName: watchConnectivity.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(watchConnectivity.currentSong == nil)

                // Stop
                Button(action: {
                    sendMusicControl("stop")
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(!watchConnectivity.isPlaying && watchConnectivity.currentSong == nil)

                // Advance the Adaptive Mix queue, or request a manual suggestion when it is off.
                Button(action: {
                    requestNextSong()
                }) {
                    if isRequestingSong {
                        ProgressView()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "forward.end.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRequestingSong)
                .accessibilityLabel(watchConnectivity.isAdaptiveMixActive ? "Next Adaptive Mix Song" : "Play New Suggestion")
            }

            // Playback State
            Text(playbackStatusText)
                .font(.caption2)
                .foregroundColor(playbackStatusColor)

            Text(adaptiveMixDetailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
#if os(watchOS)
        .background(Color.gray.opacity(0.15))
#else
        .background(Color(.systemGray6))
#endif
        .cornerRadius(8)
        .onChange(of: watchConnectivity.currentSong?.id) { _, newID in
            // Song changed — if we were waiting for a new song, stop the spinner
            if isRequestingSong, newID != songIDWhenRequested {
                clearPendingSuggestionRequest()
            }
        }
        .onChange(of: watchConnectivity.playbackState) { _, _ in
            if isRequestingSong, isTerminalPlaybackState {
                clearPendingSuggestionRequest()
            }
        }
    }

    private func requestNextSong() {
        guard !isRequestingSong else { return }

        isRequestingSong = true
        songIDWhenRequested = watchConnectivity.currentSong?.id

        // Haptic feedback so the user knows the tap registered
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif

        sendMusicControl(watchConnectivity.isAdaptiveMixActive ? "next" : "suggest")

        // Safety timeout: if no song change within 15 seconds, clear the loading state
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [self] in
            if isRequestingSong {
                clearPendingSuggestionRequest()
            }
        }
    }

    private func startAdaptiveMix() {
        guard !watchConnectivity.isAdaptiveMixActive,
              !watchConnectivity.isAdaptiveMixCurating else {
            return
        }

        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif

        sendMusicControl("adaptiveMix")
    }

    private func sendMusicControl(_ action: String) {
        let message: [String: Any] = [
            "type": "musicControl",
            "action": action
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil as (([String : Any]) -> Void)?) { error in
                print("Failed to send music control: \(error)")
                DispatchQueue.main.async {
                    // Clear loading state on send failure
                    if action == "suggest" || action == "next" {
                        clearPendingSuggestionRequest()
                    }
                }
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    private var playbackStatusText: String {
        if isRequestingSong {
            return watchConnectivity.isAdaptiveMixActive ? "Advancing queue..." : "Finding new song..."
        }

        switch watchConnectivity.playbackState {
        case "playing":
            return "Playing on iPhone"
        case "paused":
            return "Paused"
        case "stopped":
            return "Stopped"
        default:
            return watchConnectivity.playbackState
        }
    }

    private var adaptiveMixDetailText: String {
        if watchConnectivity.isAdaptiveMixCurating {
            return "Curating songs..."
        }

        guard watchConnectivity.isAdaptiveMixActive else {
            return watchConnectivity.adaptiveMixStatus
        }

        let queueCount = watchConnectivity.adaptiveMixQueuedSongCount
        let playedCount = watchConnectivity.adaptiveMixPlayedSongCount
        let zone = watchConnectivity.adaptiveMixTargetZone ?? "Zone --"
        return "\(zone) · \(queueCount) queued · \(playedCount) played"
    }

    private var playbackStatusColor: Color {
        if isRequestingSong {
            return .blue
        }

        switch watchConnectivity.playbackState {
        case "playing":
            return .green
        case "paused", "stopped":
            return .secondary
        default:
            return .orange
        }
    }

    private var isTerminalPlaybackState: Bool {
        switch watchConnectivity.playbackState {
        case "playing", "paused":
            return false
        default:
            return true
        }
    }

    private func clearPendingSuggestionRequest() {
        isRequestingSong = false
        songIDWhenRequested = nil
    }
}

#if DEBUG
struct ConnectedMusicControlView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectedMusicControlView()
    }
}
#endif
