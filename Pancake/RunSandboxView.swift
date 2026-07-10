#if DEBUG
import SwiftUI

/// DEBUG-only harness for evaluating Adaptive Mix against a live, tunable
/// run on a real device. Drives the production coordinator through the same
/// messages the watch sends; playback is real Apple Music.
struct RunSandboxView: View {
    @StateObject private var driver = RunSandboxDriver.shared
    @StateObject private var recorder = AdaptiveMixEvalRecorder.shared
    @StateObject private var coordinator = WorkoutMusicCoordinator.shared
    @StateObject private var musicManager = MusicPlaybackManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    runControlCard
                    if driver.isRunning {
                        liveMetricsCard
                        heartRateCard
                        speedCard
                    }
                    musicCard
                    evalCard
                }
                .padding()
            }
            .background(Color.pastelGroupedBackground.ignoresSafeArea())
            .navigationTitle("Run Sandbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var runControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sandbox run")
                .font(.headline)

            Text("Zone 2 warm-up, 2x Zone 4 intervals with Zone 2 recovery, Zone 1 cool-down. Nothing is saved to history.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if driver.isRunning {
                Button {
                    driver.stop()
                } label: {
                    Label("End sandbox run", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelCoral))
            } else {
                Button {
                    driver.start()
                } label: {
                    Label("Start sandbox run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelStart))
            }

            if driver.isRunning && !coordinator.isAdaptiveMixActive {
                Button {
                    driver.startAdaptiveMix()
                } label: {
                    Label("Start Adaptive Mix", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelLavender))
            }
        }
        .bubblyCard()
    }

    private var liveMetricsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sandboxMetric("Time", Int(driver.totalTime).formattedTime())
                sandboxMetric("Distance", String(format: "%.2f km", driver.totalDistanceMeters / 1000))
                sandboxMetric("Segment", "\(driver.currentSegmentIndex + 1)/\(driver.plannedSegments.count)")
            }

            HStack {
                sandboxMetric("Zone", driver.currentSegment?.intensity.label ?? "-")
                sandboxMetric("Target HR", driver.currentTargetHeartRate.map(String.init) ?? "-")
                sandboxMetric("Seg left", driver.secondsRemainingInSegment.map { "\($0)s" } ?? "-")
            }
        }
        .bubblyCard()
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Heart rate")
                    .font(.headline)
                Spacer()
                Text("\(Int(driver.heartRate)) bpm")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(heartRateColor)
            }

            Slider(value: $driver.heartRate, in: 85...195, step: 1)

            HStack(spacing: 8) {
                Button("Below zone") {
                    driver.setHeartRateRelativeToTarget(offset: -22)
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))

                Button("In zone") {
                    driver.setHeartRateRelativeToTarget(offset: 0)
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))

                Button("Above zone") {
                    driver.setHeartRateRelativeToTarget(offset: 22)
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelCoral))
            }
        }
        .bubblyCard()
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speed")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f m/s · %@/km", driver.speedMetersPerSecond, paceText))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(value: $driver.speedMetersPerSecond, in: 1.0...6.0, step: 0.1)

            HStack(spacing: 8) {
                Button("Walk 1.5") { driver.speedMetersPerSecond = 1.5 }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
                Button("Jog 2.8") { driver.speedMetersPerSecond = 2.8 }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))
                Button("Fast 4.5") { driver.speedMetersPerSecond = 4.5 }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelCoral))
            }
        }
        .bubblyCard()
    }

    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Music")
                .font(.headline)

            if let song = musicManager.currentSong {
                Text("\(song.title) — \(song.artist)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(musicManager.playbackStateDescription) · \(Int(musicManager.currentPlaybackTime))s / \(Int(musicManager.currentSongDuration))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Nothing playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(coordinator.adaptiveMixDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !musicManager.adaptiveUpcomingSongs.isEmpty {
                Text("Upcoming")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.top, 2)

                ForEach(Array(musicManager.adaptiveUpcomingSongs.prefix(4).enumerated()), id: \.offset) { index, song in
                    Text("\(index + 1). \(song.title) — \(song.artist)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let refreshAt = coordinator.nextAdaptiveMixRefreshAt {
                Text("Next refresh: \(refreshAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .bubblyCard()
    }

    private var evalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eval")
                .font(.headline)

            Text(recorder.sessionFavoritesRatioText)
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(recorder.records.prefix(4)) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.timestamp.formatted(date: .omitted, time: .standard)) · \(record.trigger) · \(record.targetZone) · \(record.guidance)")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text("HR \(record.effectiveHeartRate.map(String.init) ?? "-") vs target \(record.targetHeartRate.map(String.init) ?? "-") · \(record.favoriteCount) fav / \(record.exploratoryCount) explore\(record.applied ? "" : " · NOT APPLIED")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(record.verifiedSongs, id: \.self) { song in
                        Text("• \(song)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .bubblyCard()
    }

    private var paceText: String {
        guard driver.speedMetersPerSecond > 0 else { return "-" }
        let secondsPerKm = 1000.0 / driver.speedMetersPerSecond
        return "\(Int(secondsPerKm) / 60):" + String(format: "%02d", Int(secondsPerKm) % 60)
    }

    private var heartRateColor: Color {
        guard let target = driver.currentTargetHeartRate else { return .primary }
        let delta = Int(driver.heartRate) - target
        if delta > 8 { return .pastelCoral }
        if delta < -8 { return .pastelPeriwinkle }
        return .pastelMint
    }

    private func sandboxMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
