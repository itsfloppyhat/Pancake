import SwiftUI
import WatchConnectivity
import CoreLocation

struct WorkoutProgressView: View {
    @ObservedObject var manager: WorkoutSessionManager
    @State private var showingEndConfirmation = false
    
    // Callback to dismiss the view
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            // Timer - Large and prominent
            if let startDate = manager.workoutStartDate {
                TimerView(startDate: startDate, isRunning: manager.isRunning)
            }
            
            // GPS Status Indicator
            GPSStatusView(manager: manager)
            
            // Compact Metrics Grid - 3x2 layout
            CompactMetricsGridView(manager: manager)
            
            // Current Segment - Compact
            if manager.currentSegment != nil {
                CompactCurrentSegmentView(segment: manager.currentSegment!, progress: manager.currentSegmentProgress)
            }
            
            // Music Control and End Workout Button Row
            HStack(spacing: 4) {
                // Music Control (Adaptive)
                if isStandaloneMode() {
                    StandaloneMusicControlView()
                } else {
                    ConnectedMusicControlView()
                }
                
                // Red End Workout Button
                Button(action: {
                    showingEndConfirmation = true
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .alert("End Workout", isPresented: $showingEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Workout", role: .destructive) {
                endWorkout()
            }
        } message: {
            Text("Are you sure you want to end this workout?")
        }
    }
    
    private func endWorkout() {
        // Compute totals
        let totalSeconds: Int
        if let start = manager.workoutStartDate {
            totalSeconds = max(0, Int(Date().timeIntervalSince(start)))
        } else {
            totalSeconds = 0
        }
        
        let totalMeters: Int = Int(manager.distanceMeters > 0 ? manager.distanceMeters : (displayedDistanceKm * 1000.0))
        
        // Use the planned segments from the workout manager
        let segments = manager.plannedSegments.isEmpty ? [] : manager.plannedSegments
        
        // Build and save event
        let event = RunEvent(totalDistanceMeters: totalMeters, totalTimeSeconds: totalSeconds, segments: segments)
        RunHistoryStore.shared.add(event: event)
        
        // Send workout completion to iPhone
        WatchConnectivityManager.shared.sendWorkoutCompleted()
        
        manager.stopWorkout()
        onDismiss?()
    }
    
    private func isStandaloneMode() -> Bool {
        return !WCSession.default.isReachable
    }

    private var displayedDistanceKm: Double {
        let hkKm = manager.distanceMeters / 1000.0
        if hkKm > 0 { return hkKm }
        return coreLocationDistanceKm
    }

    private var coreLocationDistanceKm: Double {
        guard manager.locations.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<manager.locations.count {
            total += manager.locations[i].distance(from: manager.locations[i - 1])
        }
        return total / 1000.0
    }
}

// MARK: - Workout Header View
struct WorkoutHeaderView: View {
    @ObservedObject var manager: WorkoutSessionManager
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Workout In Progress")
                .font(.title2)
                .fontWeight(.bold)
            
            if !manager.plannedSegments.isEmpty {
                Text("\(manager.plannedSegments.count) segments planned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Compact Metrics Grid View
struct CompactMetricsGridView: View {
    @ObservedObject var manager: WorkoutSessionManager
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 4) {
            // Row 1: Time, Distance, Heart Rate
            CompactMetricView(
                title: "Time",
                value: formattedTime,
                color: .blue
            )
            
            CompactMetricView(
                title: "Distance",
                value: String(format: "%.2f", displayedDistanceKm),
                color: .green
            )
            
            CompactMetricView(
                title: "HR",
                value: manager.heartRate.map { String(format: "%.0f", $0) } ?? "--",
                color: .red
            )
            
            // Row 2: Calories, Pace, Cadence
            CompactMetricView(
                title: "Cal",
                value: String(format: "%.0f", manager.activeCalories),
                color: .orange
            )
            
            CompactMetricView(
                title: "Pace",
                value: formattedPace,
                color: .purple
            )
            
            CompactMetricView(
                title: "Cad",
                value: String(format: "%.0f", manager.cadence),
                color: .cyan
            )
        }
    }
    
    private var displayedDistanceKm: Double {
        let hkKm = manager.distanceMeters / 1000.0
        if hkKm > 0 { return hkKm }
        return coreLocationDistanceKm
    }
    
    private var coreLocationDistanceKm: Double {
        guard manager.locations.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<manager.locations.count {
            total += manager.locations[i].distance(from: manager.locations[i - 1])
        }
        return total / 1000.0
    }
    
    private var formattedPace: String {
        guard displayedDistanceKm > 0 else { return "--:--" }
        let paceSeconds = manager.workoutDuration / displayedDistanceKm
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var formattedTime: String {
        let totalSeconds = Int(manager.workoutDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var segmentInfo: String {
        if manager.currentSegment != nil {
            let progress = Int(manager.currentSegmentProgress * 100)
            return "\(progress)%"
        }
        return "--"
    }
}

// MARK: - Compact Metric View
struct CompactMetricView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .padding(.horizontal, 1)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Compact Current Segment View
struct CompactCurrentSegmentView: View {
    let segment: RunSegment
    let progress: Double
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Current Segment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(segment.intensity.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(intensityColor)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: intensityColor))
                .scaleEffect(y: 0.8)
            
            HStack {
                Text(segmentDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }
    
    private var intensityColor: Color {
        switch segment.intensity {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
    
    private var segmentDescription: String {
        switch segment.target {
        case .time(let seconds):
            return "\(seconds.formattedTime()) \(segment.intensity.label)"
        case .distance(let meters):
            return "\(meters.formattedDistanceMeters()) \(segment.intensity.label)"
        }
    }
}

// MARK: - Compact End Workout Button
struct CompactEndWorkoutButton: View {
    @Binding var showingConfirmation: Bool
    
    var body: some View {
        Button(role: .destructive) {
            showingConfirmation = true
        } label: {
            HStack {
                Image(systemName: "stop.fill")
                Text("End")
            }
            .font(.caption)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.small)
    }
}

struct TimerView: View {
    let startDate: Date
    let isRunning: Bool
    @State private var now: Date = Date()
    @State private var timer: Timer?

    var body: some View {
        Text(timerString)
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .onAppear {
                if isRunning {
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        now = Date()
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
    private var timerString: String {
        let interval = Int(now.timeIntervalSince(startDate))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(gpsColor.opacity(0.2))
        .cornerRadius(8)
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

#Preview {
    WorkoutProgressView(manager: .shared)
}
