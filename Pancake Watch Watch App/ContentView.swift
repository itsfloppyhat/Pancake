import SwiftUI
import HealthKit
import AuthenticationServices
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = RunPlanViewModel()
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var auth = AuthManager.shared
    @StateObject private var workoutManager = WorkoutSessionManager.shared
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    
    // Segment creation state
    @State private var newIntensity: Intensity = .easy
    @State private var isTimeTarget: Bool = true
    @State private var timeSeconds: Int = 300 // 5 minutes default
    @State private var distanceMeters: Int = 1000 // 1 km default

    // Alert and navigation state
    @State private var showGoAlert: Bool = false
    @State private var goAlertMessage: String = ""
    @State private var showWorkoutProgress: Bool = false
    @State private var showLocationAlert = false
    @State private var showRunPlanAlert = false

    var body: some View {
        NavigationStack {
            if auth.isSignedIn {
                RunPlanningView(
                    viewModel: viewModel,
                    healthKit: healthKit,
                    workoutManager: workoutManager,
                    watchConnectivity: watchConnectivity,
                    newIntensity: $newIntensity,
                    isTimeTarget: $isTimeTarget,
                    timeSeconds: $timeSeconds,
                    distanceMeters: $distanceMeters,
                    showGoAlert: $showGoAlert,
                    goAlertMessage: $goAlertMessage,
                    showWorkoutProgress: $showWorkoutProgress,
                    showLocationAlert: $showLocationAlert,
                    showRunPlanAlert: $showRunPlanAlert
                )
            } else {
                SignInView(auth: auth)
            }
        }
        .onChange(of: watchConnectivity.hasReceivedRunPlan) { _, hasReceived in
            if hasReceived {
                // Delay showing the run plan alert to avoid conflicts with other alerts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !showLocationAlert && !showGoAlert {
                        showRunPlanAlert = true
                    } else {
                        // If other alerts are showing, wait a bit more
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showRunPlanAlert = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Run Planning View
struct RunPlanningView: View {
    @ObservedObject var viewModel: RunPlanViewModel
    @ObservedObject var healthKit: HealthKitManager
    @ObservedObject var workoutManager: WorkoutSessionManager
    @ObservedObject var watchConnectivity: WatchConnectivityManager
    
    @Binding var newIntensity: Intensity
    @Binding var isTimeTarget: Bool
    @Binding var timeSeconds: Int
    @Binding var distanceMeters: Int
    @Binding var showGoAlert: Bool
    @Binding var goAlertMessage: String
    @Binding var showWorkoutProgress: Bool
    @Binding var showLocationAlert: Bool
    @Binding var showRunPlanAlert: Bool
    
    var body: some View {
        List {
            SegmentCreationSection(
                newIntensity: $newIntensity,
                isTimeTarget: $isTimeTarget,
                timeSeconds: $timeSeconds,
                distanceMeters: $distanceMeters,
                onAddSegment: addSegment
            )
            
            if !viewModel.segments.isEmpty {
                PlannedSegmentsSection(viewModel: viewModel)
                WorkoutSummarySection(viewModel: viewModel)
                HealthPermissionsSection(healthKit: healthKit)
                GPSStatusSection(workoutManager: workoutManager)
                
                // Debug Section
                Section("Debug") {
                    NavigationLink("Auth Debug") {
                        AuthDebugView(auth: AuthManager.shared)
                    }
                }
                
                StartWorkoutSection(
                    viewModel: viewModel,
                    workoutManager: workoutManager,
                    showGoAlert: $showGoAlert,
                    goAlertMessage: $goAlertMessage,
                    showWorkoutProgress: $showWorkoutProgress,
                    onStartWorkout: startWorkout
                )
            }
        }
        .onAppear(perform: handleAppear)
        .alert(goAlertMessage, isPresented: $showGoAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert("Location Access Needed", isPresented: $showLocationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable location permissions in Settings to allow run tracking.")
        }
        .alert("Run Plan Received", isPresented: $showRunPlanAlert) {
            Button("Start Run") {
                useReceivedRunPlan()
            }
            Button("Keep Current", role: .cancel) {
                watchConnectivity.clearReceivedRunPlan()
            }
        } message: {
            Text("You received a run plan from your iPhone with \(watchConnectivity.receivedRunPlan.count) segments. Tap 'Start Run' to begin immediately, or 'Keep Current' to use your existing plan.")
        }
        .overlay(
            Group {
                if showWorkoutProgress {
                    WorkoutProgressView(manager: workoutManager) {
                        showWorkoutProgress = false
                    }
                    .background(Color.black)
                    .ignoresSafeArea()
                }
            }
        )
    }
    
    private func addSegment() {
        let target: Target = isTimeTarget ? .time(seconds: timeSeconds) : .distance(meters: distanceMeters)
        let segment = RunSegment(intensity: newIntensity, target: target)
        viewModel.addSegment(segment)
    }
    
    private func useReceivedRunPlan() {
        viewModel.clearAllSegments()
        for segment in watchConnectivity.receivedRunPlan {
            viewModel.addSegment(segment)
        }
        watchConnectivity.clearReceivedRunPlan()
        
        // Automatically start the workout after accepting the plan
        goAlertMessage = "Run plan loaded from iPhone! Starting workout..."
        showGoAlert = true
        
        // Start the workout automatically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startWorkout()
        }
    }
    
    private func startWorkout() {
        WorkoutSessionManager.shared.startOutdoorRun(segments: viewModel.segments)
        WatchConnectivityManager.shared.sendWorkoutStarted()
        showWorkoutProgress = true
    }
    
    private func handleAppear() {
        if !healthKit.isAuthorized {
            healthKit.requestAuthorization()
        }
        
        // Check location authorization status asynchronously to avoid main thread warning
        DispatchQueue.global(qos: .userInitiated).async {
            let tempManager = CLLocationManager()
            let status = tempManager.authorizationStatus
            
            DispatchQueue.main.async {
                if status == .notDetermined {
                    tempManager.requestWhenInUseAuthorization()
                } else if status == .denied || status == .restricted {
                    showLocationAlert = true
                }
            }
        }
    }
}

// MARK: - Segment Creation Section
struct SegmentCreationSection: View {
    @Binding var newIntensity: Intensity
    @Binding var isTimeTarget: Bool
    @Binding var timeSeconds: Int
    @Binding var distanceMeters: Int
    let onAddSegment: () -> Void
    
    var body: some View {
        Section("Add segment") {
            Picker("Intensity", selection: $newIntensity) {
                ForEach(Intensity.allCases) { intensity in
                    Text(intensity.label).tag(intensity)
                }
            }
            .pickerStyle(.automatic)

            HStack {
                Text("Target")
                Spacer()
                HStack(spacing: 6) {
                    Button(action: { isTimeTarget = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text("Time")
                        }
                        .font(.footnote)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(isTimeTarget ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { isTimeTarget = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "ruler")
                            Text("Distance")
                        }
                        .font(.footnote)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(!isTimeTarget ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isTimeTarget {
                TimeStepperView(timeSeconds: $timeSeconds)
            } else {
                DistanceStepperView(distanceMeters: $distanceMeters)
            }

            Button(action: onAddSegment) {
                Label("Add Segment", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Time Stepper View
struct TimeStepperView: View {
    @Binding var timeSeconds: Int
    
    var body: some View {
        Stepper(value: $timeSeconds, in: 30...3_600, step: 30) {
            HStack {
                Image(systemName: "timer")
                    .imageScale(.small)
                Text(timeSeconds.formattedTime())
                    .monospacedDigit()
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
        .controlSize(.mini)
    }
}

// MARK: - Distance Stepper View
struct DistanceStepperView: View {
    @Binding var distanceMeters: Int
    
    var body: some View {
        Stepper(value: $distanceMeters, in: 100...42_000, step: 100) {
            HStack {
                Image(systemName: "ruler")
                    .imageScale(.small)
                Text(distanceMeters.formattedDistanceMeters())
                    .monospacedDigit()
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
        .controlSize(.mini)
    }
}

// MARK: - Planned Segments Section
struct PlannedSegmentsSection: View {
    @ObservedObject var viewModel: RunPlanViewModel
    
    var body: some View {
        Section("Planned segments") {
            ForEach(viewModel.segments) { segment in
                SegmentRowView(segment: segment)
            }
            .onDelete(perform: viewModel.removeSegments)
            .onMove(perform: viewModel.moveSegments)
        }
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

// MARK: - Workout Summary Section
struct WorkoutSummarySection: View {
    @ObservedObject var viewModel: RunPlanViewModel
    
    var body: some View {
        Section("Summary") {
            SummaryRowView(
                title: "Time",
                value: viewModel.totalTimeSeconds.formattedTime(),
                icon: "timer"
            )
            SummaryRowView(
                title: "Distance",
                value: viewModel.totalDistanceMeters.formattedDistanceMeters(),
                icon: "ruler"
            )
        }
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

// MARK: - Health Permissions Section
struct HealthPermissionsSection: View {
    @ObservedObject var healthKit: HealthKitManager
    
    var body: some View {
        Section("Health Permissions") {
            if !healthKit.isAuthorized {
                Button {
                    healthKit.requestAuthorization()
                } label: {
                    Label("Authorize Health", systemImage: "heart.fill")
                }
            } else {
                HStack {
                    Label("Health Authorized", systemImage: "heart.circle")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
            
            if let error = healthKit.lastAuthorizationError {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - Start Workout Section
struct StartWorkoutSection: View {
    @ObservedObject var viewModel: RunPlanViewModel
    @ObservedObject var workoutManager: WorkoutSessionManager
    @Binding var showGoAlert: Bool
    @Binding var goAlertMessage: String
    @Binding var showWorkoutProgress: Bool
    let onStartWorkout: () -> Void
    
    var body: some View {
        Section {
            Button {
                onStartWorkout()
            } label: {
                Label("Go", systemImage: "figure.run")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Sign In View
struct SignInView: View {
    @ObservedObject var auth: AuthManager
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text("Sign in to continue")
                .font(.headline)
            
            // Use a simple button that works reliably in Watch simulator
            Button(action: { 
                print("🔐 Watch: Sign in button tapped")
                auth.signIn() 
            }) {
                HStack {
                    Image(systemName: "applelogo")
                        .font(.title2)
                    Text("Sign in with Apple")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            if let error = auth.lastError {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - GPS Status Section
struct GPSStatusSection: View {
    @ObservedObject var workoutManager: WorkoutSessionManager
    
    var body: some View {
        Section("GPS Status") {
            HStack {
                Image(systemName: workoutManager.gpsStatus.icon)
                    .foregroundStyle(gpsColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutManager.gpsStatus.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let accuracy = workoutManager.gpsAccuracy {
                        Text("Accuracy: ±\(Int(accuracy)) meters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for GPS signal...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if workoutManager.isGPSAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    private var gpsColor: Color {
        switch workoutManager.gpsStatus {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        case .unavailable: return .gray
        case .unknown: return .gray
        }
    }
}

#Preview {
    ContentView()
}
