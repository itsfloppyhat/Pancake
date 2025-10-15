//
//  ContentView.swift
//  Pancake
//
//  Created by Matthew Lucas on 8/7/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        Group {
            if !viewModel.isSignedIn {
                SignInView()
            } else if !viewModel.allPermissionsGranted {
                PermissionsView()
            } else {
                MainAppView()
            }
        }
        .onAppear {
            Task {
                await viewModel.refreshAuthorizationState()
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
                    .foregroundStyle(.blue)
                
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
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
                            .foregroundStyle(.green)
                        
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
                    .foregroundStyle(isGranted ? .green : .blue)
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
                        .foregroundStyle(.green)
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
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isRequesting)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Main App View
struct MainAppView: View {
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
            
            NavigationStack {
                MusicDebugView()
            }
            .tabItem {
                Label("Debug", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}

// MARK: - Run Setup View
struct RunSetupView: View {
    @StateObject private var viewModel = RunSetupViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)
                    
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
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(isTimeTarget ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            .foregroundColor(isTimeTarget ? .blue : .primary)
                            .cornerRadius(8)
                        }
                        Button(action: { isTimeTarget = false }) {
                            HStack(spacing: 6) {
                                Image(systemName: "ruler")
                                Text("Distance")
                            }
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(!isTimeTarget ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            .foregroundColor(!isTimeTarget ? .blue : .primary)
                            .cornerRadius(8)
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
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func addSegment() {
        print("🎯 Add Segment button tapped!")
        print("   - Intensity: \(newIntensity)")
        print("   - Is Time Target: \(isTimeTarget)")
        print("   - Time Seconds: \(timeSeconds)")
        print("   - Distance Meters: \(distanceMeters)")
        
        let target: Target = isTimeTarget ? .time(seconds: timeSeconds) : .distance(meters: distanceMeters)
        print("   - Target: \(target)")
        
        let segment = RunSegment(intensity: newIntensity, target: target)
        print("   - Created segment: \(segment)")
        
        viewModel.addSegment(segment)
        print("   - Segment added to viewModel")
        print("   - Total segments now: \(viewModel.segments.count)")
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
                        .background(Color.blue)
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
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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
                        .foregroundColor(.green)
                    Text("Apple Watch Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "applewatch.slash")
                            .foregroundColor(.orange)
                        Text("Apple Watch Status")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if !viewModel.isWatchPaired {
                        Text("• Watch not paired")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    if !viewModel.isWatchAppInstalled {
                        Text("• App not installed on Watch")
                            .font(.caption2)
                            .foregroundColor(.red)
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
                .background(viewModel.canStartRun ? Color.green : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canStartRun)
            
            // Music Status
            if viewModel.isWorkoutActive {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.blue)
                    Text("Music is starting...")
                        .font(.caption)
                        .foregroundColor(.blue)
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
                            .foregroundColor(.orange)
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
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                
                Button(action: { viewModel.addLongRunTemplate() }) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(.blue)
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
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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

// MARK: - Stat Card View
struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                .background(Color.blue)
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


#Preview {
    ContentView()
}
