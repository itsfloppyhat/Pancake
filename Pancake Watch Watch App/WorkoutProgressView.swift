import SwiftUI
import WatchKit

/// Totals captured at the moment the workout ends, shown on the summary screen
/// after the session manager has already reset its live state.
struct WorkoutSummary {
    let totalSeconds: Int
    let totalDistanceKm: Double
    let activeCalories: Double
    let segmentCount: Int

    var formattedPace: String? {
        guard totalDistanceKm > 0 else { return nil }
        let paceSeconds = Double(totalSeconds) / totalDistanceKm
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}

struct WorkoutProgressView: View {
    @ObservedObject var manager: WorkoutSessionManager
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @State private var selectedPage = 1
    @State private var showingEndConfirmation = false
    @State private var completedSummary: WorkoutSummary?
    @State private var visibleCheer: ReceivedCheer?
    @State private var cheerDismissTask: Task<Void, Never>?

    // Callback to dismiss the view
    var onDismiss: (() -> Void)?

    var body: some View {
        Group {
            if let summary = completedSummary {
                WorkoutSummaryView(summary: summary) {
                    completedSummary = nil
                    onDismiss?()
                }
            } else {
                workoutPages
            }
        }
    }

    private var workoutPages: some View {
        TabView(selection: $selectedPage) {
            WorkoutControlsPage(
                isPaused: manager.isPaused,
                onEnd: { showingEndConfirmation = true },
                onPauseResume: togglePause,
                onWaterLock: { WKInterfaceDevice.current().enableWaterLock() }
            )
            .tag(0)

            WorkoutMetricsPage(manager: manager)
                .tag(1)

            WorkoutPlanPage(manager: manager)
                .tag(2)

            WorkoutMusicPage()
                .tag(3)
        }
        .tabViewStyle(.verticalPage)
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                if manager.isPlanComplete {
                    PlanCompleteChip()
                        .transition(.opacity)
                }

                if let cheer = visibleCheer {
                    CheerChip(cheer: cheer)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: watchConnectivity.lastCheer?.id) { _, _ in
            guard let cheer = watchConnectivity.lastCheer else { return }
            showCheer(cheer)
        }
        .overlay {
            if manager.showKmMilestone {
                KmMilestoneOverlay(
                    km: manager.lastKmMilestone,
                    pace: currentPace
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: manager.showKmMilestone)
                .allowsHitTesting(false)
            }
        }
        .alert("End Workout", isPresented: $showingEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Workout", role: .destructive) {
                endWorkout()
            }
        } message: {
            Text("Are you sure you want to end this workout?")
        }
    }

    private var currentPace: String? {
        guard manager.displayedDistanceKm > 0 else { return nil }
        let paceSeconds = manager.workoutDuration / manager.displayedDistanceKm
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    private func togglePause() {
        if manager.isPaused {
            manager.resumeWorkout()
        } else {
            manager.pauseWorkout()
        }
    }

    private func showCheer(_ cheer: ReceivedCheer) {
        WKInterfaceDevice.current().play(.notification)
        visibleCheer = cheer

        cheerDismissTask?.cancel()
        cheerDismissTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            visibleCheer = nil
        }
    }

    private func endWorkout() {
        // Compute totals
        let totalSeconds: Int
        if manager.workoutStartDate != nil {
            totalSeconds = max(0, Int(manager.workoutDuration))
        } else {
            totalSeconds = 0
        }

        let totalDistanceKm = manager.displayedDistanceKm
        let totalMeters: Int = Int(totalDistanceKm * 1000.0)

        // Use the planned segments from the workout manager
        let segments = manager.plannedSegments.isEmpty ? [] : manager.plannedSegments

        // Capture the summary before the manager resets its live state.
        let summary = WorkoutSummary(
            totalSeconds: totalSeconds,
            totalDistanceKm: totalDistanceKm,
            activeCalories: manager.activeCalories,
            segmentCount: segments.count
        )

        // Build and save event on Watch
        let event = RunEvent(totalDistanceMeters: totalMeters, totalTimeSeconds: totalSeconds, segments: segments)
        RunHistoryStore.shared.add(event: event)

        // Send workout completion to iPhone with final distance/time data
        // so the iPhone can also save the run event with accurate totals.
        WatchConnectivityManager.shared.sendWorkoutCompleted(
            totalDistanceKm: totalDistanceKm,
            totalTimeSeconds: totalSeconds
        )

        // Now stop the workout session and show the summary
        manager.stopWorkout()
        completedSummary = summary
    }
}

// MARK: - Controls Page

private struct WorkoutControlsPage: View {
    let isPaused: Bool
    let onEnd: () -> Void
    let onPauseResume: () -> Void
    let onWaterLock: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                WorkoutControlButton(
                    title: "End",
                    systemImage: "xmark",
                    tint: .red,
                    action: onEnd
                )

                WorkoutControlButton(
                    title: isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "arrow.clockwise" : "pause",
                    tint: .yellow,
                    action: onPauseResume
                )
            }

            HStack(spacing: 14) {
                WorkoutControlButton(
                    title: "Water Lock",
                    systemImage: "drop.fill",
                    tint: .cyan,
                    action: onWaterLock
                )
            }
        }
        .navigationTitle("Controls")
    }
}

private struct WorkoutControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(tint)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - Metrics Page

private struct WorkoutMetricsPage: View {
    @ObservedObject var manager: WorkoutSessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(formattedTime)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(manager.isPaused ? .secondary : .primary)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(formattedTime)

                if manager.isPaused {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Spacer(minLength: 0)

                GPSStatusView(manager: manager)
            }

            HeartRateZoneView(manager: manager)

            HStack(spacing: 12) {
                WorkoutMetric(
                    title: "Distance",
                    value: String(format: "%.2f", manager.displayedDistanceKm),
                    unit: "km",
                    color: .green
                )

                WorkoutMetric(
                    title: "Pace",
                    value: formattedPace,
                    unit: "/km",
                    color: .purple
                )

                WorkoutMetric(
                    title: "Cal",
                    value: String(format: "%.0f", manager.activeCalories),
                    unit: nil,
                    color: .orange
                )
            }

            if let warning = manager.liveMetricsWarning {
                LiveMetricsWarningView(message: warning)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var formattedTime: String {
        let totalSeconds = Int(manager.workoutDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedPace: String {
        guard manager.displayedDistanceKm > 0 else { return "--:--" }
        let paceSeconds = manager.workoutDuration / manager.displayedDistanceKm
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct WorkoutMetric: View {
    let title: String
    let value: String
    let unit: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(unit ?? "")")
    }
}

// MARK: - Heart Rate Zone View

private struct HeartRateZoneView: View {
    @ObservedObject var manager: WorkoutSessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Text(manager.currentHeartRate.map(String.init) ?? "--")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(statusColor)

                Text("bpm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let range = targetRange {
                    Text("\(range.lowerBound)–\(range.upperBound)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let range = targetRange, let heartRate = manager.currentHeartRate {
                Gauge(value: gaugeValue(heartRate: heartRate, range: range), in: 0...1) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .tint(Gradient(colors: [.blue, .green, .green, .red]))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(accessibilityValue)
    }

    private var targetRange: ClosedRange<Int>? {
        manager.currentSegment?.intensity.defaultHeartRateRange
    }

    /// Maps the heart rate onto the gauge so the target zone occupies the
    /// middle half: below-zone readings fall in the first quarter, above-zone
    /// readings in the last quarter.
    private func gaugeValue(heartRate: Int, range: ClosedRange<Int>) -> Double {
        let zoneWidth = Double(range.upperBound - range.lowerBound)
        guard zoneWidth > 0 else { return 0.5 }

        let position = (Double(heartRate) - Double(range.lowerBound)) / zoneWidth
        return min(1, max(0, 0.25 + position * 0.5))
    }

    private var statusColor: Color {
        guard let heartRate = manager.currentHeartRate, let range = targetRange else {
            return .secondary
        }

        if heartRate < range.lowerBound {
            return .blue
        }
        if heartRate > range.upperBound {
            return .red
        }
        return .green
    }

    private var accessibilityValue: String {
        guard let heartRate = manager.currentHeartRate else {
            return "Unknown"
        }

        guard let range = targetRange else {
            return "\(heartRate) beats per minute"
        }

        let status = heartRate < range.lowerBound
            ? "below target zone"
            : (heartRate > range.upperBound ? "above target zone" : "in target zone")
        return "\(heartRate) beats per minute, \(status)"
    }
}

// MARK: - Plan Page

private struct WorkoutPlanPage: View {
    @ObservedObject var manager: WorkoutSessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if manager.isPlanComplete {
                Label("Plan complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Keep running or end the workout from Controls.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let segment = manager.currentSegment {
                HStack(alignment: .firstTextBaseline) {
                    Text(segment.intensity.label)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(intensityColor(segment.intensity))

                    Spacer(minLength: 0)

                    Text("\(manager.currentSegmentIndex + 1) of \(manager.plannedSegments.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let remaining = remainingText {
                    Text(remaining)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .accessibilityLabel("Remaining in segment")
                        .accessibilityValue(remaining)
                }

                ProgressView(value: manager.currentSegmentProgress)
                    .tint(intensityColor(segment.intensity))

                if let next = manager.upcomingSegment {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)

                        Text("Next: \(next.intensity.label) · \(targetText(next))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Last segment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No plan segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Plan")
    }

    private var remainingText: String? {
        guard let segment = manager.currentSegment else { return nil }

        switch segment.target {
        case .time:
            guard let seconds = manager.estimatedSecondsUntilCurrentSegmentEnds else { return nil }
            return "\(Int(seconds).formattedTime()) left"
        case .distance(let meters):
            let remainingMeters = Int(Double(meters) * (1.0 - manager.currentSegmentProgress))
            return "\(remainingMeters.formattedDistanceMeters()) left"
        }
    }

    private func targetText(_ segment: RunSegment) -> String {
        switch segment.target {
        case .time(let seconds):
            return seconds.formattedTime()
        case .distance(let meters):
            return meters.formattedDistanceMeters()
        }
    }

    private func intensityColor(_ intensity: Intensity) -> Color {
        switch intensity {
        case .zone1: return .blue
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }
}

// MARK: - Music Page

private struct WorkoutMusicPage: View {
    var body: some View {
        ScrollView {
            ConnectedMusicControlView()
        }
        .navigationTitle("Music")
    }
}

// MARK: - Summary View

private struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Workout Complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                SummaryMetricRow(title: "Time", value: summary.totalSeconds.formattedTime())
                SummaryMetricRow(title: "Distance", value: String(format: "%.2f km", summary.totalDistanceKm))

                if let pace = summary.formattedPace {
                    SummaryMetricRow(title: "Avg Pace", value: pace)
                }

                if summary.activeCalories > 0 {
                    SummaryMetricRow(title: "Calories", value: String(format: "%.0f", summary.activeCalories))
                }

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Summary")
    }
}

private struct SummaryMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan Complete Chip

private struct PlanCompleteChip: View {
    var body: some View {
        Label("Plan complete", systemImage: "checkmark.circle.fill")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.green.opacity(0.25), in: Capsule())
            .foregroundStyle(.green)
    }
}

// MARK: - Cheer Chip

private struct CheerChip: View {
    let cheer: ReceivedCheer

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "megaphone.fill")
                .font(.caption2)

            VStack(alignment: .leading, spacing: 0) {
                Text(cheer.senderName)
                    .font(.system(size: 11, weight: .semibold))
                Text(cheer.message)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.25), in: Capsule())
        .foregroundStyle(.orange)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cheer from \(cheer.senderName)")
        .accessibilityValue(cheer.message)
    }
}

private struct LiveMetricsWarningView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.slash.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.yellow.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - GPS Status View

struct GPSStatusView: View {
    @ObservedObject var manager: WorkoutSessionManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: manager.gpsStatus.icon)
                .font(.caption)
                .foregroundStyle(gpsColor)

            if let accuracy = manager.gpsAccuracy {
                Text("±\(Int(accuracy))m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(manager.gpsStatus.description)
    }

    private var gpsColor: Color {
        switch manager.gpsStatus {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        case .unavailable: return .gray
        case .unknown: return .gray
        }
    }
}

// MARK: - Km Milestone Overlay

struct KmMilestoneOverlay: View {
    let km: Int
    let pace: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)

                Text("\(km) km")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let pace = pace {
                    Text(pace)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

#if DEBUG
struct WorkoutProgressView_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutProgressView(manager: .shared)
    }
}
#endif
