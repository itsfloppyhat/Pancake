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
                if watchConnectivity.hasReceivedRunPlan {
                    ReceivedPlanView(
                        segments: watchConnectivity.receivedRunPlan,
                        isStarting: workoutManager.isStarting,
                        onStartWorkout: startWorkout,
                        onDismissPlan: dismissPlan
                    )
                } else {
                    WaitingForPlanView(isReachable: watchConnectivity.isReachable)
                }
            }
        }
        .onAppear {
            if !healthKit.isAuthorized {
                healthKit.requestAuthorization()
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
    }

    private func startWorkout() {
        guard !workoutManager.isStarting else { return }
        let segments = watchConnectivity.receivedRunPlan
        isStartAttemptActive = true
        hasSentWorkoutStarted = false
        startErrorMessage = nil
        workoutManager.startOutdoorRun(segments: segments)
    }

    private func dismissPlan() {
        guard !workoutManager.isStarting else { return }
        watchConnectivity.clearReceivedRunPlan()
    }
}

// MARK: - Waiting For Plan View
struct WaitingForPlanView: View {
    let isReachable: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "iphone.and.arrow.right.inward")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Open Pancake on iPhone to plan your run")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Connectivity status
            HStack(spacing: 6) {
                Circle()
                    .fill(isReachable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isReachable ? "iPhone Connected" : "iPhone Not Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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

            Text("Preparing Health, GPS, and music handoff.")
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
