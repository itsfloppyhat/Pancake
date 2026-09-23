import Foundation

struct RunReplaySample: Identifiable {
    let id: Int
    let timestamp: Double
    let distanceMeters: Double
    let heartRate: Int?
    let targetHeartRate: Int?
    let pace: Double?
    let songIndex: Int?
    let route: RunRoutePoint?
    let section: Int
}

struct RunDistanceSplit: Identifiable {
    let id: Int
    let distanceMeters: Double
    let duration: Double
    let endTimestamp: Double
    let averageHeartRate: Int?
    var pace: Double { duration / (distanceMeters / 1000) }
    let unit: DistanceUnit
    var isPartial: Bool { distanceMeters < unit.metersPerUnit - 1 }
}

enum ReplayHeartEffort: Equatable {
    case below, onTarget, above, unknown

    static func classify(heartRate: Int?, target: Int?) -> Self {
        guard let heartRate, heartRate > 0 else { return .unknown }
        if let target, target > 0 {
            if Double(heartRate) < Double(target) * 0.95 { return .below }
            if Double(heartRate) > Double(target) * 1.05 { return .above }
            return .onTarget
        }
        // Older records have no target; these are explicitly labeled estimates.
        if heartRate < 114 { return .below }
        if heartRate > 152 { return .above }
        return .onTarget
    }
}

struct RunReplayAnalysis {
    let samples: [RunReplaySample]
    let songs: [SongPeriod]
    let duration: Double
    let splits: [RunDistanceSplit]

    init(event: RunEvent) {
        let duration = Double(max(1, event.totalTimeSeconds))
        let songs = Self.normalizedSongs(event.songHistory, duration: duration)
        self.duration = duration
        self.songs = songs
        let route = event.routePoints.filter { $0.isValid && $0.timestamp <= duration + 2 }.sorted { $0.timestamp < $1.timestamp }
        let points = event.dataPoints.filter {
            $0.timestamp.isFinite && $0.timestamp >= 0 && $0.timestamp <= duration + 2 &&
            $0.distanceMeters.isFinite && $0.distanceMeters >= 0
        }.sorted { $0.timestamp < $1.timestamp }
        var built: [RunReplaySample] = []
        var section = 0
        if !route.isEmpty {
            for point in route {
                guard point.timestamp > (built.last?.timestamp ?? -1) else { continue }
                if point.startsNewSection || built.last.map({ point.timestamp - $0.timestamp > 20 }) == true { section += 1 }
                let rawPace = point.speedMetersPerSecond.flatMap { speed in
                    speed.isFinite && speed >= 0.5 && speed <= 12 ? 1000 / speed : nil
                }
                // A trailing 15-second speed window makes the stripe readable,
                // without blending across stops, pauses or missing GPS sections.
                let recent = built.suffix(8).filter { $0.section == section && point.timestamp - $0.timestamp <= 15 }
                let pace: Double?
                if let rawPace {
                    let speeds = recent.compactMap { $0.pace.map { 1000 / $0 } } + [1000 / rawPace]
                    pace = 1000 / (speeds.reduce(0, +) / Double(speeds.count))
                } else if point.speedMetersPerSecond.map({ $0.isFinite && $0 < 0.5 }) == true {
                    pace = nil
                } else {
                    pace = Self.localPace(timestamp: point.timestamp, distance: point.distanceMeters, previous: built, section: section)
                }
                built.append(RunReplaySample(
                    id: built.count, timestamp: point.timestamp, distanceMeters: point.distanceMeters,
                    heartRate: point.heartRate, targetHeartRate: point.targetHeartRate,
                    pace: pace, songIndex: Self.songIndex(at: point.timestamp, songs: songs), route: point, section: section
                ))
            }
        } else {
            for point in points {
                guard point.timestamp > (built.last?.timestamp ?? -1) else { continue }
                if built.last.map({ point.timestamp - $0.timestamp > 20 }) == true { section += 1 }
                let pace = Self.localPace(timestamp: point.timestamp, distance: point.distanceMeters, previous: built, section: section)
                built.append(RunReplaySample(
                    id: built.count, timestamp: point.timestamp, distanceMeters: point.distanceMeters,
                    heartRate: point.heartRate, targetHeartRate: point.targetHeartRate,
                    pace: pace, songIndex: Self.songIndex(at: point.timestamp, songs: songs), route: nil, section: section
                ))
            }
        }
        samples = built
        splits = Self.makeSplits(samples: built, unit: .kilometers)
    }

    var hasRoute: Bool { samples.filter { $0.route != nil }.count > 1 }

    func sample(at time: Double) -> RunReplaySample? {
        // Do not imply a measured value inside a long recording gap.
        guard let nearest = samples.min(by: { abs($0.timestamp - time) < abs($1.timestamp - time) }),
              abs(nearest.timestamp - time) <= 12 else { return nil }
        return nearest
    }

    static func songIndex(at timestamp: Double, songs: [SongPeriod]) -> Int? {
        songs.lastIndex { timestamp >= $0.startTimestamp && timestamp < ($0.endTimestamp ?? .infinity) }
    }

    static func normalizedSongs(_ songs: [SongPeriod], duration: Double) -> [SongPeriod] {
        let sorted = songs.filter { $0.startTimestamp.isFinite && $0.startTimestamp < duration }
            .sorted { $0.startTimestamp < $1.startTimestamp }
        return sorted.enumerated().compactMap { index, song in
            let nextStart = index + 1 < sorted.count ? sorted[index + 1].startTimestamp : duration
            let start = max(0, song.startTimestamp)
            let end = min(duration, nextStart, song.endTimestamp ?? duration)
            guard end.isFinite, end > start else { return nil }
            return SongPeriod(songTitle: song.songTitle, artist: song.artist, startTimestamp: start, endTimestamp: end)
        }
    }

    private static func localPace(timestamp: Double, distance: Double, previous: [RunReplaySample], section: Int) -> Double? {
        let window = previous.suffix(20).filter { $0.section == section && timestamp - $0.timestamp <= 30 }
        guard let first = window.first, let last = window.last,
              timestamp - first.timestamp >= 5, distance - last.distanceMeters > 0.1,
              distance - first.distanceMeters >= 5 else { return nil }
        let pace = (timestamp - first.timestamp) * 1000 / (distance - first.distanceMeters)
        return (84...2000).contains(pace) ? pace : nil
    }

    func splits(in unit: DistanceUnit) -> [RunDistanceSplit] {
        unit == .kilometers ? splits : Self.makeSplits(samples: samples, unit: unit)
    }

    private static func makeSplits(samples: [RunReplaySample], unit: DistanceUnit) -> [RunDistanceSplit] {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else { return [] }
        // Require a start near zero. Partial recordings must not invent earlier splits.
        guard first.distanceMeters < 50, first.timestamp < 20 else { return [] }
        var boundaries: [(distance: Double, time: Double)] = [(0, 0)]
        var next = unit.metersPerUnit
        for pair in zip(samples, samples.dropFirst()) {
            let (a, b) = pair
            guard b.distanceMeters >= a.distanceMeters else { return [] }
            guard b.section == a.section, b.timestamp - a.timestamp <= 20 else { return [] }
            while b.distanceMeters >= next {
                let fraction = (next - a.distanceMeters) / max(0.001, b.distanceMeters - a.distanceMeters)
                boundaries.append((next, a.timestamp + fraction * (b.timestamp - a.timestamp)))
                next += unit.metersPerUnit
            }
        }
        if let boundary = boundaries.last, last.distanceMeters - boundary.distance > 50 {
            boundaries.append((last.distanceMeters, last.timestamp))
        }
        return zip(boundaries, boundaries.dropFirst()).enumerated().compactMap { index, pair in
            let (a, b) = pair
            guard b.time > a.time, b.distance > a.distance else { return nil }
            let rates = samples.filter { $0.timestamp >= a.time && $0.timestamp < b.time }.compactMap(\.heartRate)
            return RunDistanceSplit(id: index + 1, distanceMeters: b.distance - a.distance,
                duration: b.time - a.time, endTimestamp: b.time,
                averageHeartRate: rates.isEmpty ? nil : rates.reduce(0, +) / rates.count, unit: unit)
        }
    }
}
