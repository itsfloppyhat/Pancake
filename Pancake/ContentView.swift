//
//  ContentView.swift
//  Pancake
//
//  Created by Matthew Lucas on 8/7/25.
//

import SwiftUI
import Charts

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var onboarding = OnboardingManager.shared

    var body: some View {
        Group {
            if !onboarding.hasCompletedOnboarding {
                OnboardingView()
            } else {
                MainAppView()
            }
        }
        .onAppear {
            Task {
                await viewModel.refreshAuthorizationState()
            }
            AuthManager.shared.validateCredentialState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AuthManager.shared.validateCredentialState()
            }
        }
    }
}

// MARK: - Sign In View
struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.pastelLavender)
                
                Text("Welcome to Pancake")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your personal running companion")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                SignInWithAppleButtonView(authManager: AuthManager.shared)
                    .padding(.horizontal, 40)
                
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(Color.pastelCoral)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pastelGroupedBackground)
    }
}

// MARK: - Permissions View
struct PermissionsView: View {
    @StateObject private var viewModel = PermissionsViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.pastelMint)
                        
                        Text("Permissions Required")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Pancake needs access to your health and location data to track your runs effectively.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Permission Cards
                    VStack(spacing: 16) {
                        PermissionCardView(
                            title: "Health Data",
                            description: "Access to heart rate, calories, and workout data",
                            icon: "heart.fill",
                            isGranted: viewModel.healthKitAuthorized,
                            isRequesting: viewModel.isRequestingHealth,
                            onRequest: { viewModel.requestHealthAuthorization() }
                        )
                        
                        PermissionCardView(
                            title: "Location Services",
                            description: "Access to location for tracking running distance and pace",
                            icon: "location.fill",
                            isGranted: viewModel.locationAuthorized,
                            isRequesting: viewModel.isRequestingLocation,
                            onRequest: { viewModel.requestLocationAuthorization() }
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Permission Card View
struct PermissionCardView: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let isRequesting: Bool
    let onRequest: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isGranted ? Color.pastelMint : Color.pastelLavender)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.pastelMint)
                }
            }
            
            if !isGranted {
                Button(action: onRequest) {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        Text(isRequesting ? "Requesting..." : "Grant Permission")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(LinearGradient.pastelPrimary)
                            .shadow(color: Color.pastelLavender.opacity(0.4), radius: 6, x: 0, y: 3)
                    )
                    .clipShape(Capsule())
                }
                .disabled(isRequesting)
            }
        }
        .bubblyCard()
    }
}

// MARK: - Main App View
struct MainAppView: View {
    @StateObject private var musicCoordinator = WorkoutMusicCoordinator.shared

    var body: some View {
        TabView {
            NavigationStack {
                RunSetupView()
            }
            .tabItem {
                Label("Run", systemImage: "figure.run")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            
            NavigationStack {
                UserProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
        }
        .overlay(alignment: .top) {
            if let warning = musicCoordinator.liveMetricsWarning {
                LiveMetricsFallbackBanner(message: warning) {
                    musicCoordinator.dismissLiveMetricsWarning()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private struct LiveMetricsFallbackBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.slash.fill")
                .foregroundStyle(Color.pastelCoral)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Run Setup View
struct RunSetupView: View {
    @StateObject private var viewModel = RunSetupViewModel()
    @StateObject private var onboarding = OnboardingManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !onboarding.requiredRunSetupComplete {
                    RunSetupReadinessCard(onboarding: onboarding)
                }

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.pastelLavender)
                    
                    Text("Plan Your Run")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Set up your workout segments and start on your Apple Watch")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Segment Creation
                SegmentCreationCard(viewModel: viewModel)
                
                // Planned Segments
                if viewModel.hasSegments {
                    PlannedSegmentsCard(viewModel: viewModel)
                    
                    // Workout Summary
                    WorkoutSummaryCard(viewModel: viewModel)
                    
                    // Start Run Button
                    StartRunButton(viewModel: viewModel)
                }
                
                // Quick Templates
                QuickTemplatesCard(viewModel: viewModel)
            }
            .padding()
        }
        .navigationTitle("Run Setup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Apple Watch", isPresented: $viewModel.showingWatchAlert) {
            Button("OK", role: .cancel) { 
                viewModel.dismissAlert()
            }
        } message: {
            Text(viewModel.watchAlertMessage)
        }
    }
}

private struct RunSetupReadinessCard: View {
    @ObservedObject var onboarding: OnboardingManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.pastelPeach)

                Text("Finish setup")
                    .font(.headline)

                Spacer()
            }

            Text(onboarding.missingRunSetupMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Open setup guide") {
                onboarding.resetOnboarding()
            }
            .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeach))
        }
        .pastelTintedCard(.pastelPeach)
    }
}

// MARK: - Segment Creation Card
struct SegmentCreationCard: View {
    @ObservedObject var viewModel: RunSetupViewModel
    @State private var newIntensity: Intensity = .easy
    @State private var isTimeTarget: Bool = true
    @State private var timeSeconds: Int = 300
    @State private var distanceMeters: Int = 1000
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Segment")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Intensity Picker
                HStack {
                    Text("Intensity")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Picker("Intensity", selection: $newIntensity) {
                        ForEach(Intensity.allCases) { intensity in
                            Text(intensity.label).tag(intensity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                // Target Type Selection
                HStack {
                    Text("Target")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: { isTimeTarget = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                Text("Time")
                            }
                            .pastelTag(isSelected: isTimeTarget, activeColor: .pastelLavender)
                        }
                        Button(action: { isTimeTarget = false }) {
                            HStack(spacing: 6) {
                                Image(systemName: "ruler")
                                Text("Distance")
                            }
                            .pastelTag(isSelected: !isTimeTarget, activeColor: .pastelLavender)
                        }
                    }
                }
                
                // Time or Distance Input
                if isTimeTarget {
                    HStack {
                        Text("Duration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Stepper(value: $timeSeconds, in: 30...3600, step: 30) {
                            Text(timeSeconds.formattedTime())
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                } else {
                    HStack {
                        Text("Distance")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Stepper(value: $distanceMeters, in: 100...42000, step: 100) {
                            Text(distanceMeters.formattedDistanceMeters())
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
                
                // Add Button
                Button(action: addSegment) {
                    Label("Add Segment", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelPrimary))
            }
        }
        .bubblyCard()
    }
    
    private func addSegment() {
        let target: Target = isTimeTarget ? .time(seconds: timeSeconds) : .distance(meters: distanceMeters)
        let segment = RunSegment(intensity: newIntensity, target: target)
        viewModel.addSegment(segment)
    }
}

// MARK: - Planned Segments Card
struct PlannedSegmentsCard: View {
    @ObservedObject var viewModel: RunSetupViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Planned Segments")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(Array(viewModel.segments.enumerated()), id: \.offset) { index, segment in
                HStack {
                    // Segment number
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(segment.intensity.pastelColor)
                        .clipShape(Circle())
                    
                    // Segment details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.intensity.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        switch segment.target {
                        case .time(let seconds):
                            Text(seconds.formattedTime())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .distance(let meters):
                            Text(meters.formattedDistanceMeters())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Delete button
                    Button(action: { viewModel.removeSegments(at: IndexSet([index])) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.pastelCoral)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .bubblyCard()
    }
}

// MARK: - Workout Summary Card
struct WorkoutSummaryCard: View {
    @ObservedObject var viewModel: RunSetupViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workout Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalTimeSeconds.formattedTime())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalDistanceMeters.formattedDistanceMeters())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .bubblyCard()
    }
}

// MARK: - Start Run Button
struct StartRunButton: View {
    @ObservedObject var viewModel: RunSetupViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Watch Status
            if viewModel.isWatchPaired && viewModel.isWatchAppInstalled {
                HStack {
                    Image(systemName: "applewatch")
                        .foregroundColor(.pastelMint)
                    Text("Apple Watch Connected")
                        .font(.caption)
                        .foregroundColor(.pastelMint)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "applewatch.slash")
                            .foregroundColor(.pastelPeach)
                        Text("Apple Watch Status")
                            .font(.caption)
                            .foregroundColor(.pastelPeach)
                    }
                    
                    if !viewModel.isWatchPaired {
                        Text("• Watch not paired")
                            .font(.caption2)
                            .foregroundColor(.pastelCoral)
                    }
                    if !viewModel.isWatchAppInstalled {
                        Text("• App not installed on Watch")
                            .font(.caption2)
                            .foregroundColor(.pastelCoral)
                    }
                }
            }
            
            // Start Button
            Button(action: { viewModel.startRunOnWatch() }) {
                HStack {
                    if viewModel.isStartingRun {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "applewatch")
                    }
                    Text(viewModel.isStartingRun ? "Starting Music..." : "Start Run on Apple Watch")
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(viewModel.canStartRun ? LinearGradient.pastelStart : LinearGradient(colors: [Color.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: viewModel.canStartRun ? Color.pastelMint.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 4)
                )
                .clipShape(Capsule())
            }
            .disabled(!viewModel.canStartRun)
            
            // Music Status
            if viewModel.isWorkoutActive {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.pastelLavender)
                    Text("Music is starting...")
                        .font(.caption)
                        .foregroundColor(.pastelLavender)
                }
            }
        }
    }
}

// MARK: - Quick Templates Card
struct QuickTemplatesCard: View {
    @ObservedObject var viewModel: RunSetupViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Templates")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                Button(action: { viewModel.addIntervalTemplate() }) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.pastelPeach)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interval Workout")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("5min warm-up, 3x2min hard/2min easy, 5min cool-down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .pastelTintedCard(.pastelPeach)
                }

                Button(action: { viewModel.addLongRunTemplate() }) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(.pastelPeriwinkle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Long Run")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("5K easy pace")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .pastelTintedCard(.pastelPeriwinkle)
                }
            }
        }
        .bubblyCard()
    }
}

// MARK: - History View
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    
    var body: some View {
        List {
            if viewModel.hasEvents {
                ForEach(viewModel.events) { event in
                    NavigationLink(value: event) {
                        RunEventRowView(event: event)
                    }
                }
            } else {
                EmptyHistoryView()
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: RunEvent.self) { event in
            RunEventDetailView(event: event)
        }
    }
}

// MARK: - Run Event Row View
struct RunEventRowView: View {
    let event: RunEvent
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.date, style: .date)
                    .font(.headline)
                Text(event.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(event.totalDistanceMeters.formattedDistanceMeters())
                    .font(.subheadline)
                Text(event.totalTimeSeconds.formattedTime())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.segments.count == 1 ? event.effortSummary : "Intervals")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Run on \(event.date.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityValue("\(event.totalDistanceMeters.formattedDistanceMeters()) in \(event.totalTimeSeconds.formattedTime())")
    }
}

// MARK: - Empty History View
struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Runs Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Complete your first run using your Apple Watch to see it here")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Run Event Detail View
struct RunEventDetailView: View {
    let event: RunEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.date.formatted(date: .complete, time: .shortened))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(event.effortSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Summary Stats
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCardView(
                        title: "Distance",
                        value: event.totalDistanceMeters.formattedDistanceMeters(),
                        icon: "ruler"
                    )

                    StatCardView(
                        title: "Duration",
                        value: event.totalTimeSeconds.formattedTime(),
                        icon: "timer"
                    )

                    if let pace = event.formattedPace {
                        StatCardView(
                            title: "Avg Pace",
                            value: pace,
                            icon: "speedometer"
                        )
                    }

                    if let avgHR = event.averageHeartRate {
                        StatCardView(
                            title: "Avg HR",
                            value: "\(avgHR) bpm",
                            icon: "heart.fill"
                        )
                    }
                }

                // Charts (only for Pancake runs with detailed data)
                if event.hasDetailedData {
                    CombinedWorkoutChartView(
                        dataPoints: event.dataPoints,
                        totalDurationSeconds: event.totalTimeSeconds
                    )

                    // Song Timeline
                    if !event.songHistory.isEmpty {
                        SongTimelineView(
                            songHistory: SongTimelineView.deduplicatedSongs(event.songHistory),
                            totalDuration: Double(event.totalTimeSeconds),
                            allDataPoints: event.dataPoints,
                            segments: event.segments
                        )
                    }
                }

                // Segments
                if !event.segments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Segments")
                            .font(.headline)

                        ForEach(Array(event.segments.enumerated()), id: \.offset) { index, segment in
                            SegmentRowView(segment: segment, index: index + 1)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Combined Workout Chart View (HR + Cadence + Km markers)
struct CombinedWorkoutChartView: View {
    let dataPoints: [WorkoutDataPoint]
    let totalDurationSeconds: Int

    private var hrPoints: [(min: Double, value: Double)] {
        dataPoints.compactMap { dp in
            guard let hr = dp.heartRate else { return nil }
            return (min: dp.timestamp / 60.0, value: Double(hr))
        }
    }

    private var cadencePoints: [(min: Double, value: Double)] {
        dataPoints.compactMap { dp in
            guard let cad = dp.cadence, cad > 0 else { return nil }
            return (min: dp.timestamp / 60.0, value: cad)
        }
    }

    private var pacePoints: [(min: Double, value: Double)] {
        dataPoints.compactMap { dp in
            guard let pace = dp.paceSecondsPerKm, pace > 0 else { return nil }
            return (min: dp.timestamp / 60.0, value: pace / 60.0)
        }
    }

    /// Timestamps (in minutes) where each km was reached
    private var kmMarkers: [(km: Int, min: Double)] {
        var markers: [(km: Int, min: Double)] = []
        var nextKm = 1000.0 // meters
        for dp in dataPoints {
            if dp.distanceMeters >= nextKm {
                markers.append((km: Int(nextKm / 1000.0), min: dp.timestamp / 60.0))
                nextKm += 1000.0
            }
        }
        return markers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Heart Rate + Km markers
            if !hrPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Heart Rate")
                            .font(.headline)
                        Spacer()
                        Text("bpm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Chart {
                        // Km marker vertical lines
                        ForEach(kmMarkers, id: \.km) { marker in
                            RuleMark(x: .value("Km", marker.min))
                                .foregroundStyle(.gray.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, alignment: .center) {
                                    Text("\(marker.km) km")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                        }

                        // HR line
                        ForEach(Array(hrPoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Time", point.min),
                                y: .value("HR", point.value)
                            )
                            .foregroundStyle(Color.pastelCoral)
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(Array(hrPoints.enumerated()), id: \.offset) { _, point in
                            AreaMark(
                                x: .value("Time", point.min),
                                y: .value("HR", point.value)
                            )
                            .foregroundStyle(Color.pastelCoral.opacity(0.15))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxisLabel("Time (min)")
                    .frame(height: 200)
                    .padding(.vertical, 4)
                }
                .padding()
                .pastelTintedCard(.pastelLavender)
            }

            // Pace chart
            if !pacePoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pace")
                            .font(.headline)
                        Spacer()
                        Text("min/km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Chart {
                        ForEach(kmMarkers, id: \.km) { marker in
                            RuleMark(x: .value("Km", marker.min))
                                .foregroundStyle(.gray.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }

                        ForEach(Array(pacePoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Time", point.min),
                                y: .value("Pace", point.value)
                            )
                            .foregroundStyle(Color.pastelLavender)
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(Array(pacePoints.enumerated()), id: \.offset) { _, point in
                            AreaMark(
                                x: .value("Time", point.min),
                                y: .value("Pace", point.value)
                            )
                            .foregroundStyle(Color.pastelLavender.opacity(0.15))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxisLabel("Time (min)")
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                    .padding(.vertical, 4)
                }
                .padding()
                .pastelTintedCard(.pastelLavender)
            }

            // Cadence chart
            if !cadencePoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cadence")
                            .font(.headline)
                        Spacer()
                        Text("spm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Chart {
                        ForEach(kmMarkers, id: \.km) { marker in
                            RuleMark(x: .value("Km", marker.min))
                                .foregroundStyle(.gray.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }

                        ForEach(Array(cadencePoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Time", point.min),
                                y: .value("Cadence", point.value)
                            )
                            .foregroundStyle(Color.pastelSky)
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(Array(cadencePoints.enumerated()), id: \.offset) { _, point in
                            AreaMark(
                                x: .value("Time", point.min),
                                y: .value("Cadence", point.value)
                            )
                            .foregroundStyle(Color.pastelSky.opacity(0.15))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxisLabel("Time (min)")
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 140)
                    .padding(.vertical, 4)
                }
                .padding()
                .pastelTintedCard(.pastelLavender)
            }
        }
    }
}

// MARK: - Song Timeline View
struct SongTimelineView: View {
    let songHistory: [SongPeriod]
    let totalDuration: Double
    var allDataPoints: [WorkoutDataPoint] = []
    var segments: [RunSegment] = []

    @State private var expandedIndex: Int? = nil

    private let colors: [Color] = [.pastelPeriwinkle, .pastelMint, .pastelPeach, .pastelLavender, .pastelRose, .pastelSky, .pastelLemon, .pastelLilac]

    /// Deduplicates song entries that have the same title+artist with timestamps within 30 seconds
    static func deduplicatedSongs(_ songs: [SongPeriod]) -> [SongPeriod] {
        guard !songs.isEmpty else { return [] }
        var result: [SongPeriod] = []

        for song in songs {
            let normalizedTitle = song.songTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedArtist = song.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            if let lastIndex = result.lastIndex(where: {
                let lt = $0.songTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let la = $0.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let titleMatch = lt == normalizedTitle || lt.contains(normalizedTitle) || normalizedTitle.contains(lt)
                let artistMatch = la == normalizedArtist || la.contains(normalizedArtist) || normalizedArtist.contains(la)
                let closeTimestamp = abs($0.startTimestamp - song.startTimestamp) < 30
                return titleMatch && artistMatch && closeTimestamp
            }) {
                // Merge: keep the earlier start, use the later end
                let existing = result[lastIndex]
                let mergedEnd = song.endTimestamp ?? existing.endTimestamp
                result[lastIndex] = SongPeriod(
                    songTitle: existing.songTitle,
                    artist: existing.artist,
                    startTimestamp: min(existing.startTimestamp, song.startTimestamp),
                    endTimestamp: mergedEnd
                )
            } else {
                result.append(song)
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Songs")
                .font(.headline)

            // Timeline bar
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.pastelLavender.opacity(0.15))
                        .frame(height: 24)

                    ForEach(Array(songHistory.enumerated()), id: \.offset) { index, period in
                        let start = totalDuration > 0 ? period.startTimestamp / totalDuration : 0
                        let end = totalDuration > 0 ? (period.endTimestamp ?? totalDuration) / totalDuration : 1
                        let segmentWidth = max((end - start) * width, 2)
                        let offset = start * width

                        RoundedRectangle(cornerRadius: 4)
                            .fill(colors[index % colors.count])
                            .frame(width: segmentWidth, height: 24)
                            .offset(x: offset)
                    }
                }
            }
            .frame(height: 24)

            // Song list with expandable details
            ForEach(Array(songHistory.enumerated()), id: \.offset) { index, period in
                VStack(alignment: .leading, spacing: 0) {
                    // Song header row (tappable)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedIndex = expandedIndex == index ? nil : index
                        }
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colors[index % colors.count])
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(period.songTitle)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(period.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(formatTimestamp(period.startTimestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Image(systemName: expandedIndex == index ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Expanded detail
                    if expandedIndex == index {
                        SongDetailView(
                            period: period,
                            dataPoints: allDataPoints,
                            segments: segments,
                            totalDuration: totalDuration
                        )
                        .padding(.top, 6)
                        .padding(.leading, 18)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .pastelTintedCard(.pastelLavender)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Song Detail View (Expandable)
struct SongDetailView: View {
    let period: SongPeriod
    let dataPoints: [WorkoutDataPoint]
    let segments: [RunSegment]
    let totalDuration: Double

    /// Data points that overlap with this song period
    private var relevantDataPoints: [WorkoutDataPoint] {
        let endTime = period.endTimestamp ?? totalDuration
        return dataPoints.filter { $0.timestamp >= period.startTimestamp && $0.timestamp <= endTime }
    }

    private var avgHeartRate: Int? {
        let hrs = relevantDataPoints.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / hrs.count
    }

    private var avgPace: String? {
        let paces = relevantDataPoints.compactMap { $0.paceSecondsPerKm }
        guard !paces.isEmpty else { return nil }
        let avgSeconds = paces.reduce(0, +) / Double(paces.count)
        let mins = Int(avgSeconds) / 60
        let secs = Int(avgSeconds) % 60
        return String(format: "%d:%02d/km", mins, secs)
    }

    private var avgCadence: Int? {
        let cads = relevantDataPoints.compactMap { $0.cadence }.filter { $0 > 0 }
        guard !cads.isEmpty else { return nil }
        return Int(cads.reduce(0, +) / Double(cads.count))
    }

    private var distanceAtStart: String {
        if let dp = dataPoints.last(where: { $0.timestamp <= period.startTimestamp }) {
            let km = dp.distanceMeters / 1000.0
            return String(format: "%.2f km", km)
        }
        return "--"
    }

    /// Which segment the runner was in when this song started
    private var currentSegmentLabel: String {
        guard !segments.isEmpty else { return "--" }

        // Walk through segments to find which one covers this timestamp
        var elapsed: TimeInterval = 0
        for (i, seg) in segments.enumerated() {
            let segDuration: TimeInterval
            switch seg.target {
            case .time(let seconds): segDuration = TimeInterval(seconds)
            case .distance: segDuration = totalDuration / Double(segments.count) // approximate
            }
            if period.startTimestamp < elapsed + segDuration {
                return "Segment \(i + 1) (\(seg.intensity.label))"
            }
            elapsed += segDuration
        }
        return segments.last.map { "Segment \(segments.count) (\($0.intensity.label))" } ?? "--"
    }

    private var songDurationFormatted: String {
        let endTime = period.endTimestamp ?? totalDuration
        let duration = endTime - period.startTimestamp
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var explanation: String {
        var parts: [String] = []

        // Context about when the song played
        let startMins = Int(period.startTimestamp) / 60
        parts.append("Played at \(startMins) min into the run (\(distanceAtStart)).")

        // Heart rate insight
        if let hr = avgHeartRate {
            if hr > 170 {
                parts.append("High-intensity moment (avg \(hr) bpm) — likely chosen for its driving energy.")
            } else if hr > 150 {
                parts.append("Moderate effort (avg \(hr) bpm) — a solid tempo match for steady running.")
            } else if hr > 130 {
                parts.append("Easy-zone effort (avg \(hr) bpm) — a relaxed pick to keep things comfortable.")
            } else {
                parts.append("Low heart rate (avg \(hr) bpm) — warming up or cooling down.")
            }
        }

        // Segment context
        if !segments.isEmpty {
            parts.append("Running in \(currentSegmentLabel.lowercased()).")
        }

        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Metrics row
            HStack(spacing: 16) {
                if let hr = avgHeartRate {
                    MetricPill(icon: "heart.fill", value: "\(hr)", unit: "bpm", color: .pastelCoral)
                }
                if let pace = avgPace {
                    MetricPill(icon: "speedometer", value: pace, unit: "", color: .pastelLavender)
                }
                if let cad = avgCadence {
                    MetricPill(icon: "figure.walk", value: "\(cad)", unit: "spm", color: .pastelSky)
                }
                MetricPill(icon: "timer", value: songDurationFormatted, unit: "", color: .secondary)
            }

            // Run position
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(distanceAtStart)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(currentSegmentLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // AI explanation blurb
            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

// MARK: - Metric Pill
struct MetricPill: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Stat Card View
struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.pastelPeriwinkle)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .pastelTintedCard(.pastelPeriwinkle)
    }
}

// MARK: - Segment Row View
struct SegmentRowView: View {
    let segment: RunSegment
    let index: Int
    
    var body: some View {
        HStack {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(segment.intensity.pastelColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.intensity.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                switch segment.target {
                case .time(let seconds):
                    Text(seconds.formattedTime())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .distance(let meters):
                    Text(meters.formattedDistanceMeters())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}


#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
