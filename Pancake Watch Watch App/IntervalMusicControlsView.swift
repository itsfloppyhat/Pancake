import SwiftUI

struct IntervalMusicControlsView: View {
    @AppStorage(DistanceUnit.preferenceKey) private var distanceUnit: DistanceUnit = .kilometers
    let interval: IntervalChangePrompt
    @ObservedObject private var notifications = IntervalNotificationManager.shared
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    private var targetDescription: String {
        switch interval.target {
        case .time(let seconds): return seconds.formattedDuration()
        case .distance(let meters): return meters.formattedDistanceMeters(unit: distanceUnit)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("\(interval.intensity.label) starts now")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(targetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let song = connectivity.currentSong {
                    Text("\(song.title) · \(song.artist)")
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Button {
                    notifications.nextSong(for: interval)
                } label: {
                    Label("Next Song", systemImage: "forward.end.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(notifications.isSendingControl)

                Button {
                    notifications.sendMusicControl(connectivity.isPlaying ? "pause" : "play", for: interval)
                } label: {
                    Label(connectivity.isPlaying ? "Pause Music" : "Play Music", systemImage: connectivity.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(notifications.isSendingControl)

                if notifications.isSendingControl {
                    ProgressView("Sending…")
                        .font(.caption2)
                }

                if let error = notifications.musicControlError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else if !connectivity.isReachable {
                    Text("Open Pancake on iPhone to change music.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Keep Current Music") {
                    notifications.clearInterval(for: interval.runID)
                }
                .font(.caption)
            }
            .padding(.horizontal, 6)
        }
    }
}
