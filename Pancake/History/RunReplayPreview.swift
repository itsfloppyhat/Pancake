#if DEBUG
import SwiftUI

/// A separate, in-memory preview. Never inserted into the runner's real history.
struct RunReplayPreview: View {
    var body: some View {
        NavigationStack {
            RunEventDetailView(event: Self.sample)
                .safeAreaInset(edge: .top) {
                    Text("Sample run · interface preview")
                        .font(.caption).frame(maxWidth: .infinity).padding(6)
                        .background(.yellow.opacity(0.2))
                }
        }
    }

    static let sample: RunEvent = {
        var points: [RunRoutePoint] = []
        var metrics: [WorkoutDataPoint] = []
        var distance = 0.0
        for second in stride(from: 0, through: 1200, by: 5) {
            let t = Double(second)
            let speed = 2.8 + 0.9 * sin(t / 85)
            if second > 0 { distance += speed * 5 }
            let angle = t / 1200 * .pi * 2
            let target = second < 400 || second >= 800 ? 135 : 160
            let hr = target + Int(22 * sin(t / 100))
            points.append(RunRoutePoint(
                timestamp: t,
                latitude: 40.7829 + (460 * sin(angle) + 70 * sin(3 * angle)) / 111_111,
                longitude: -73.9654 + (250 * cos(angle) + 80 * sin(2 * angle)) / 84_000,
                horizontalAccuracy: 5, distanceMeters: distance, heartRate: hr, targetHeartRate: target,
                speedMetersPerSecond: speed, startsNewSection: second == 0
            ))
            metrics.append(WorkoutDataPoint(timestamp: t, heartRate: hr, cadence: nil, distanceMeters: distance,
                paceSecondsPerKm: 1000 / speed, currentSongTitle: nil, currentSongArtist: nil, targetHeartRate: target))
        }
        let titles = ["First light", "Find your rhythm", "Open road", "Higher ground", "Second wind", "Home stretch"]
        let songs = titles.enumerated().map { index, title in
            SongPeriod(songTitle: title, artist: "Sample soundtrack", startTimestamp: Double(index * 200), endTimestamp: Double((index + 1) * 200))
        }
        return RunEvent(date: Date(timeIntervalSince1970: 1_789_963_200), totalDistanceMeters: Int(distance),
                        totalTimeSeconds: 1200, segments: [
                            RunSegment(intensity: .zone2, target: .time(seconds: 400)),
                            RunSegment(intensity: .zone4, target: .time(seconds: 400)),
                            RunSegment(intensity: .zone2, target: .time(seconds: 400))
                        ], dataPoints: metrics, songHistory: songs, routePoints: points)
    }()
}
#endif
