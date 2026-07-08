import SwiftUI

struct ContentView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var workoutManager = WorkoutSessionManager.shared
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared

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
                        isStarting: workoutManager.isStarting,
                        onStartWorkout: startWorkout,
                        onDismissPlan: dismissPlan
                    )
                } else {
                    WaitingForPlanView(
                        isReachable: watchConnectivity.isReachable,
                        isStarting: workoutManager.isStarting,
                        onQuickRun: startQuickRun
                    )
                }
            }
        }
        .overlay {
            if showWorkoutProgress {
                WorkoutProgressView(manager: workoutManager) {
                    showWorkoutProgress = false
                }
                .background(Color.black)
                .ignoresSafeArea()
            } else if workoutManager.isStarting {
                StartingWorkoutView()
                    .background(Color.black)
                    .ignoresSafeArea()
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
            startErrorMessage = nil

            if !hasSentWorkoutStarted {
                watchConnectivity.clearReceivedRunPlan()
                WatchConnectivityManager.shared.sendWorkoutStarted()
                hasSentWorkoutStarted = true
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                showWorkoutProgress = true
            }
        }
        .onChange(of: workoutManager.error?.localizedDescription) { _, message in
            guard isStartAttemptActive, let message else { return }
            isStartAttemptActive = false
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

    private func startWorkout() {
        guard !workoutManager.isStarting else { return }
        let segments = watchConnectivity.receivedRunPlan
        isStartAttemptActive = true
        hasSentWorkoutStarted = false
        startErrorMessage = nil
        workoutManager.startOutdoorRun(segments: segments)
    }

    /// Starts an easy run without an iPhone plan. Matches the default context
    /// the iPhone assumes when a workout starts without a received plan.
    private func startQuickRun() {
        guard !workoutManager.isStarting else { return }
        isStartAttemptActive = true
        hasSentWorkoutStarted = false
        startErrorMessage = nil
        workoutManager.startOutdoorRun(segments: [
            RunSegment(intensity: .zone2, target: .time(seconds: 1800))
        ])
    }

    private func dismissPlan() {
        guard !workoutManager.isStarting else { return }
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
        WorkoutSessionManager.shared.startOutdoorRun(segments: segments)

        guard await waitForWorkoutToRun() else {
            PancakeSimulatorLog("PANCAKE_SIM: Watch timed out waiting for simulated workout start")
            return
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        WatchConnectivityManager.shared.sendMusicControl("adaptiveMix")
        PancakeSimulatorLog("PANCAKE_SIM: Watch requested Adaptive Mix")

        try? await Task.sleep(nanoseconds: 14_000_000_000)
        WatchConnectivityManager.shared.sendMusicControl("next")
        PancakeSimulatorLog("PANCAKE_SIM: Watch requested next song")

        try? await Task.sleep(nanoseconds: 16_000_000_000)
        WatchConnectivityManager.shared.sendMusicControl("next")
        PancakeSimulatorLog("PANCAKE_SIM: Watch requested next song")
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
    let isStarting: Bool
    let onQuickRun: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.right.inward")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                Text("Open Pancake on iPhone to plan your run")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Connectivity status
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReachable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(isReachable ? "iPhone Connected" : "iPhone Not Connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    onQuickRun()
                } label: {
                    Label("Quick Run", systemImage: "figure.run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isStarting)

                Text("30 min easy run, no plan needed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pancake")
    }
}

// MARK: - Received Plan View
struct ReceivedPlanView: View {
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
                    value: totalDistanceMeters.formattedDistanceMeters(),
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
                Text(meters.formattedDistanceMeters())
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
