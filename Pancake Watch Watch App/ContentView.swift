import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var workoutManager = WorkoutSessionManager.shared
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    @StateObject private var launchCoordinator = WatchWorkoutLaunchCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var startFlow = WatchWorkoutStartFlow()
    @State private var showWorkoutProgress = false
    @State private var isStartAttemptActive = false
    @State private var hasSentWorkoutStarted = false
    @State private var startErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if !healthKit.isAuthorized {
                    WatchHealthSetupView {
                        healthKit.requestAuthorization()
                    }
                } else if watchConnectivity.hasReceivedRunPlan {
                    ReceivedPlanView(
                        segments: watchConnectivity.receivedRunPlan,
                        isStarting: isPreparingToStart,
                        onStartWorkout: startWorkout,
                        onDismissPlan: dismissPlan
                    )
                } else {
                    WaitingForPlanView(
                        isReachable: watchConnectivity.isReachable,
                        isAwaitingPlanFromPhone: launchCoordinator.wasLaunchedFromPhone
                    )
                }
            }
        }
        .overlay {
            if showWorkoutProgress || workoutManager.isRunning || workoutManager.completedSummary != nil {
                WorkoutProgressView(manager: workoutManager) {
                    showWorkoutProgress = false
                }
                .background(Color.black)
                .ignoresSafeArea()
            } else if startFlow.phase == .choosingMusic {
                AdaptivePlaylistStartPrompt(
                    onChoice: { startFlow.chooseMusic($0) },
                    onCancel: { startFlow.cancelPreparation() }
                )
                .background(Color.black.ignoresSafeArea())
            } else if case .countingDown(let remaining) = startFlow.phase {
                WorkoutCountdownView(remaining: remaining) {
                    startFlow.cancelPreparation()
                }
                .background(Color.black.ignoresSafeArea())
            } else if workoutManager.isStarting || startFlow.phase == .starting {
                StartingWorkoutView()
                    .background(Color.black)
                    .ignoresSafeArea()
            }
        }
        .task(id: startFlow.countdownAttemptID) {
            guard let attemptID = startFlow.countdownAttemptID else { return }
            await countDownToWorkout(attemptID: attemptID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                startFlow.cancelPreparation()
            }
        }
        .onDisappear { startFlow.cancelPreparation() }
        .onChange(of: watchConnectivity.hasReceivedRunPlan) { _, hasPlan in
            if hasPlan {
                launchCoordinator.clearLaunchFromPhone()
            }
        }
        .onChange(of: workoutManager.isRunning) { _, isRunning in
            guard isRunning else {
                if !workoutManager.isStarting {
                    hasSentWorkoutStarted = false
                }
                return
            }

            isStartAttemptActive = false
            startFlow.reset()
            startErrorMessage = nil
            launchCoordinator.clearLaunchFromPhone()

            if !hasSentWorkoutStarted {
                watchConnectivity.clearReceivedRunPlan()
                if let runID = workoutManager.activeRunID, let startedAt = workoutManager.activeRunStartedAt {
                    WatchConnectivityManager.shared.sendWorkoutStarted(
                        runID: runID,
                        startedAt: startedAt,
                        segments: workoutManager.plannedSegments,
                        startAdaptiveMix: workoutManager.shouldStartAdaptiveMix
                    )
                }
                hasSentWorkoutStarted = true
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                showWorkoutProgress = true
            }
            WKInterfaceDevice.current().play(.start)
        }
        .onChange(of: workoutManager.error?.localizedDescription) { _, message in
            guard isStartAttemptActive, let message else { return }
            isStartAttemptActive = false
            startFlow.reset()
            startErrorMessage = message
        }
        .alert("Couldn’t Start Workout", isPresented: Binding(
            get: { startErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    startErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(startErrorMessage ?? "Please try again.")
        }
        #if DEBUG
        .task {
            await DebugWatchSimulatorRunController.startIfRequested()
        }
        #endif
    }

    private var isPreparingToStart: Bool {
        startFlow.phase != .idle || workoutManager.isStarting
    }

    private func startWorkout() {
        prepareToStart(segments: watchConnectivity.receivedRunPlan)
    }

    private func prepareToStart(segments: [RunSegment]) {
        guard !workoutManager.isStarting, !workoutManager.isRunning,
              startFlow.begin(segments: segments) else { return }
        hasSentWorkoutStarted = false
        startErrorMessage = nil
    }

    @MainActor
    private func countDownToWorkout(attemptID: UUID) async {
        while startFlow.countdownAttemptID == attemptID {
            WKInterfaceDevice.current().play(.click)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if let request = startFlow.advanceCountdown(attemptID: attemptID) {
                isStartAttemptActive = true
                workoutManager.startOutdoorRun(
                    segments: request.segments,
                    startAdaptiveMix: request.startAdaptiveMix
                )
                return
            }
        }
    }

    private func dismissPlan() {
        guard !isPreparingToStart else { return }
        watchConnectivity.clearReceivedRunPlan()
    }
}

#if DEBUG
func PancakeSimulatorLog(_ message: String) {
    print(message)

    guard let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("pancake-sim.log") else {
        return
    }

    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    let data = Data(line.utf8)

    if FileManager.default.fileExists(atPath: logURL.path),
       let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: logURL, options: .atomic)
    }
}

@MainActor
private enum DebugWatchSimulatorRunController {
    private static let runArgument = "--pancake-simulated-run"
    private static let runEnvironmentKey = "PANCAKE_SIMULATED_RUN"
    private static var didStart = false

    static func startIfRequested() async {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains(runArgument) ||
                processInfo.environment[runEnvironmentKey] == "1" else {
            return
        }
        // Keep synthetic metrics available while exercising the real start UI.
        guard !processInfo.arguments.contains("--pancake-manual-start") else { return }

        guard !didStart else { return }
        didStart = true

        HealthKitManager.shared.isAuthorized = true
        PancakeSimulatorLog("PANCAKE_SIM: Watch waiting for iPhone run plan")

        guard await waitForRunPlan() else {
            PancakeSimulatorLog("PANCAKE_SIM: Watch timed out waiting for run plan")
            return
        }

        let segments = WatchConnectivityManager.shared.receivedRunPlan
        PancakeSimulatorLog("PANCAKE_SIM: Watch received run plan segments=\(segments.count)")
        WorkoutSessionManager.shared.startOutdoorRun(segments: segments, startAdaptiveMix: true)

        guard await waitForWorkoutToRun() else {
            PancakeSimulatorLog("PANCAKE_SIM: Watch timed out waiting for simulated workout start")
            return
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        PancakeSimulatorLog("PANCAKE_SIM: Watch requested Adaptive Mix")

        if processInfo.environment["PANCAKE_SIM_TRANSITION_TEST"] == "1" {
            // Reproduce the reported seated run: no skip at the boundary,
            // followed by manual skips at 1:20 and 1:25.
            for skipTime in [80.0, 85.0] {
                while WorkoutSessionManager.shared.isRunning && WorkoutSessionManager.shared.totalTime < skipTime {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                WatchConnectivityManager.shared.sendMusicControl("next")
                PancakeSimulatorLog("PANCAKE_SIM: Watch requested next song at \(skipTime)")
            }
            return
        }

        try? await Task.sleep(nanoseconds: 14_000_000_000)
        WatchConnectivityManager.shared.sendMusicControl("next")
        PancakeSimulatorLog("PANCAKE_SIM: Watch requested next song")

        try? await Task.sleep(nanoseconds: 16_000_000_000)
        guard let interval = IntervalNotificationManager.shared.currentInterval else {
            PancakeSimulatorLog("PANCAKE_SIM: Missing interval music prompt")
            return
        }
        IntervalNotificationManager.shared.nextSong(for: interval)
        for _ in 0..<20 {
            guard IntervalNotificationManager.shared.isSendingControl else { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !IntervalNotificationManager.shared.isSendingControl,
              IntervalNotificationManager.shared.musicControlError == nil,
              IntervalNotificationManager.shared.currentInterval == nil else {
            PancakeSimulatorLog("PANCAKE_SIM: Interval music action failed")
            return
        }
        PancakeSimulatorLog("PANCAKE_SIM: Watch interval music action acknowledged")

        // Bypass the watch's own stale-action guard to also exercise the phone's
        // rejection path. A rejected old notification must not skip another song.
        for _ in 0..<120 {
            if WorkoutSessionManager.shared.currentSegmentIndex > interval.segmentIndex { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        WatchConnectivityManager.shared.sendIntervalMusicControl("next", interval: interval) { error in
            if (error as NSError?)?.code == 2 {
                PancakeSimulatorLog("PANCAKE_SIM: Stale interval music action rejected")
            } else {
                PancakeSimulatorLog("PANCAKE_SIM: Stale interval music action was not rejected correctly")
            }
        }
    }

    private static func waitForRunPlan() async -> Bool {
        for _ in 0..<120 {
            if WatchConnectivityManager.shared.hasReceivedRunPlan {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private static func waitForWorkoutToRun() async -> Bool {
        for _ in 0..<40 {
            if WorkoutSessionManager.shared.isRunning {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }
}
#else
func PancakeSimulatorLog(_ message: String) {}
#endif

// MARK: - Health Setup View
struct WatchHealthSetupView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)

            Text("Health Access")
                .font(.headline)

            Text("Health access saves workouts and shows live run metrics.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Pancake")
    }
}

// MARK: - Waiting For Plan View
struct WaitingForPlanView: View {
    let isReachable: Bool
    var isAwaitingPlanFromPhone: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.right.inward")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                if isAwaitingPlanFromPhone {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Getting your run plan…")
                            .font(.footnote)
                    }
                    .padding(.horizontal)
                } else {
                    Text("Open Pancake on iPhone to plan your run")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Connectivity status
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReachable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(isReachable ? "iPhone Connected" : "iPhone Not Connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Create a plan on iPhone, then tap Send run plan.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Pancake")
    }
}

// MARK: - Received Plan View
struct ReceivedPlanView: View {
    @AppStorage(DistanceUnit.preferenceKey) private var distanceUnit: DistanceUnit = .kilometers
    let segments: [RunSegment]
    let isStarting: Bool
    let onStartWorkout: () -> Void
    let onDismissPlan: () -> Void

    var body: some View {
        List {
            Section("Run Plan") {
                ForEach(segments) { segment in
                    SegmentRowView(segment: segment)
                }
            }

            Section("Summary") {
                SummaryRowView(
                    title: "Time",
                    value: totalTimeSeconds.formattedTime(),
                    icon: "timer"
                )
                SummaryRowView(
                    title: "Distance",
                    value: totalDistanceMeters.formattedDistanceMeters(unit: distanceUnit),
                    icon: "ruler"
                )
            }

            Section {
                Button {
                    onStartWorkout()
                } label: {
                    HStack {
                        if isStarting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Label(isStarting ? "Starting..." : "Start Workout", systemImage: "figure.run")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.vertical, 4)
                .disabled(isStarting)

                Button(role: .destructive) {
                    onDismissPlan()
                } label: {
                    Label("Dismiss Plan", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(isStarting)
            }
        }
        .navigationTitle("Run Plan")
    }

    private var totalTimeSeconds: Int {
        segments.reduce(0) {
            switch $1.target {
            case .time(let seconds): return $0 + seconds
            case .distance: return $0
            }
        }
    }

    private var totalDistanceMeters: Int {
        segments.reduce(0) {
            switch $1.target {
            case .distance(let meters): return $0 + meters
            case .time: return $0
            }
        }
    }
}

// MARK: - Workout start flow

private struct AdaptivePlaylistStartPrompt: View {
    let onChoice: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Start adaptive playlist?")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button("Yes") { onChoice(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityHint("Start the countdown and request Adaptive Mix for this run")

                Button("No") { onChoice(false) }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Start the countdown without Adaptive Mix")

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkoutCountdownView: View {
    let remaining: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Get ready")
                .font(.headline)

            Text(remaining, format: .number)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.green)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Starting in \(remaining)")

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Starting Workout View
struct StartingWorkoutView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(.green)

            Text("Starting Workout")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Preparing Health and GPS tracking.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Segment Row View
struct SegmentRowView: View {
    @AppStorage(DistanceUnit.preferenceKey) private var distanceUnit: DistanceUnit = .kilometers
    let segment: RunSegment

    var body: some View {
        HStack {
            Text(segment.intensity.label)
                .fontWeight(.semibold)
            Spacer()
            switch segment.target {
            case .time(let seconds):
                Text(seconds.formattedTime())
                    .monospacedDigit()
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            case .distance(let meters):
                Text(meters.formattedDistanceMeters(unit: distanceUnit))
                    .monospacedDigit()
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Summary Row View
struct SummaryRowView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .monospacedDigit()
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
    }
}

#if DEBUG
struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
