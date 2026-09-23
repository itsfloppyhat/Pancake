import SwiftUI
import Charts

struct RunReplayView: View {
    @AppStorage(DistanceUnit.preferenceKey) private var distanceUnit: DistanceUnit = .kilometers
    private let analysis: RunReplayAnalysis
    @State private var selectedTime: Double = 0
    @State private var showMap = true

    init(event: RunEvent) { analysis = RunReplayAnalysis(event: event) }

    var body: some View {
        let replay = analysis
        let selected = replay.sample(at: selectedTime)
        VStack(alignment: .leading, spacing: 20) {
            routeCard(replay)
            if !replay.samples.isEmpty {
                selectionCard(replay, selected: selected)
                timelines(replay)
                if !replay.splits.isEmpty { splits(replay) }
            }
        }
    }

    private func routeCard(_ replay: RunReplayAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Run replay", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
                Spacer()
                if replay.hasRoute {
                    Toggle("Map", isOn: $showMap)
                        .fixedSize()
                        .accessibilityLabel("Show map behind route")
                }
            }
            if replay.hasRoute {
                Text("Trace the route to explore your run.")
                    .font(.subheadline).foregroundStyle(.secondary)
                RunRouteMapView(samples: replay.samples, selectedTime: $selectedTime, showMap: showMap)
                    .frame(height: 320)
                    .overlay(alignment: .topLeading) {
                        routeReadout(replay)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Route with pace, music, and heart rate stripes")
                    .accessibilityHint("Use the run position slider below to explore each point.")
                HStack(spacing: 16) {
                    Label("Pace", systemImage: "speedometer").foregroundStyle(.indigo)
                    Label("Song", systemImage: "music.note").foregroundStyle(Color.pastelPeriwinkle)
                    Label("Heart rate", systemImage: "heart.fill").foregroundStyle(.red)
                }
                .font(.caption)
                Text("Three parallel stripes follow the same GPS route. Gaps mark pauses or missing GPS.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("No GPS route recorded", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                Text("Older runs and summary-only Health imports don't contain coordinates. New watch runs record a route when GPS is available; it can arrive after the run summary.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func routeReadout(_ replay: RunReplayAnalysis) -> some View {
        let selected = replay.sample(at: selectedTime)
        let songIndex = RunReplayAnalysis.songIndex(at: selectedTime, songs: replay.songs)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(Int(selectedTime).formattedTime()).bold()
                Text("\(formatPace(selected?.pace)) /\(distanceUnit.symbol)")
                Text(selected?.heartRate.map { "\($0) bpm" } ?? "— bpm")
                    .foregroundStyle(selected.map(RunReplayPalette.heartRate) ?? .secondary)
            }.font(.caption.monospacedDigit())
            HStack(spacing: 5) {
                Circle().fill(RunReplayPalette.song(songIndex)).frame(width: 7, height: 7)
                Text(songIndex.map { replay.songs[$0].songTitle } ?? "No song recorded")
                    .font(.caption2).lineLimit(1)
            }
        }
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private func selectionCard(_ replay: RunReplayAnalysis, selected: RunReplaySample?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Int(selectedTime).formattedTime()).font(.title2.monospacedDigit().bold())
                Spacer()
                if let selected {
                    Text(distanceUnit.formattedDistance(meters: selected.distanceMeters)).monospacedDigit()
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Pace", systemImage: "speedometer").font(.caption).foregroundStyle(.secondary)
                    Text("\(formatPace(selected?.pace)) /\(distanceUnit.symbol)").font(.headline.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Label("Heart rate", systemImage: "heart.fill").font(.caption).foregroundStyle(.secondary)
                    Text(selected?.heartRate.map { "\($0) bpm" } ?? "— bpm")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(selected.map(RunReplayPalette.heartRate) ?? .secondary)
                }
            }
            let songIndex = RunReplayAnalysis.songIndex(at: selectedTime, songs: replay.songs)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(RunReplayPalette.song(songIndex)).frame(width: 8, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(songIndex.map { replay.songs[$0].songTitle } ?? "No song recorded")
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let songIndex {
                        Text(replay.songs[songIndex].artist).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Slider(value: $selectedTime, in: 0...replay.duration)
                .tint(.indigo)
                .accessibilityLabel("Run position")
                .accessibilityValue("\(Int(selectedTime).formattedTime()), \(formatPace(selected?.pace)) per \(distanceUnit.singular), \(selected?.heartRate.map(String.init) ?? "no") beats per minute")
            HStack {
                Text("Start")
                Spacer()
                Text(Int(replay.duration).formattedTime())
            }.font(.caption2).foregroundStyle(.secondary)
            if selected == nil {
                Text("No measurements at this point in the recording.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .pastelTintedCard(.pastelPeriwinkle)
    }

    private func timelines(_ replay: RunReplayAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pace, effort & music").font(.headline)
            Text("Drag either chart to move the route marker. Pace reflects local changes, rather than your average since the start.")
                .font(.caption).foregroundStyle(.secondary)
            metricChart(replay, heartRate: false)
            metricChart(replay, heartRate: true)
            if !replay.songs.isEmpty {
                Chart {
                    ForEach(Array(replay.songs.enumerated()), id: \.offset) { index, song in
                        RectangleMark(xStart: .value("Start", song.startTimestamp / 60), xEnd: .value("End", (song.endTimestamp ?? replay.duration) / 60), yStart: .value("Bottom", 0), yEnd: .value("Top", 1))
                            .foregroundStyle(RunReplayPalette.song(index))
                    }
                    RuleMark(x: .value("Selected", selectedTime / 60)).foregroundStyle(.primary)
                }
                .chartXScale(domain: 0...replay.duration / 60)
                .chartYAxis(.hidden).chartXAxis(.hidden)
                .frame(height: 20)
                .accessibilityLabel("Song timeline; colors match the route's middle stripe")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Slower")
                    LinearGradient(colors: [.teal, .indigo], startPoint: .leading, endPoint: .trailing).frame(width: 60, height: 6).clipShape(Capsule())
                    Text("Faster · relative to this run")
                }
                HStack(spacing: 12) {
                    Text("● Below").foregroundStyle(.blue)
                    Text("● On target").foregroundStyle(.green)
                    Text("● Above").foregroundStyle(.red)
                }
                Text("Heart rate: within 5% of the recorded target is green. Older records use estimated zones. Gray means no measurement.")
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func metricChart(_ replay: RunReplayAnalysis, heartRate: Bool) -> some View {
        let graph = graphPoints(replay.samples, heartRate: heartRate)
        let points = graph.map(\.sample)
        let paceRange = RunReplayPalette.paceRange(replay.samples)
        return VStack(alignment: .leading, spacing: 5) {
            Text(heartRate ? "Heart rate · bpm · dashed line = target" : "Pace · min/\(distanceUnit.symbol) · faster is higher")
                .font(.caption.weight(.semibold))
            if points.isEmpty {
                Text(heartRate ? "No heart rate recorded" : "Not enough movement data for pace")
                    .font(.caption).foregroundStyle(.secondary).frame(height: 60)
            } else {
                Chart {
                    ForEach(graph) { point in
                        let sample = point.sample
                        let value = heartRate ? Double(sample.heartRate ?? 0) : distanceUnit.pace(secondsPerKm: sample.pace ?? 0) / 60
                        LineMark(x: .value("Minutes", sample.timestamp / 60), y: .value("Value", value), series: .value("Section", point.series))
                            .foregroundStyle(heartRate ? Color.green : Color.indigo)
                            .interpolationMethod(.linear)
                        PointMark(x: .value("Minutes", sample.timestamp / 60), y: .value("Value", value))
                            .symbolSize(8)
                            .foregroundStyle(heartRate ? RunReplayPalette.heartRate(sample) : RunReplayPalette.pace(sample.pace, range: paceRange))
                        if heartRate, let target = sample.targetHeartRate {
                            LineMark(x: .value("Minutes", sample.timestamp / 60), y: .value("Value", Double(target)), series: .value("Section", point.series + 1_000_000))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .interpolationMethod(.stepEnd)
                        }
                    }
                    RuleMark(x: .value("Selected", selectedTime / 60))
                        .foregroundStyle(.primary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: 0...replay.duration / 60)
                .chartYScale(domain: .automatic(includesZero: false, reversed: !heartRate), range: .plotDimension(startPadding: 8, endPadding: 8), type: .linear)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                guard let frame = proxy.plotFrame else { return }
                                let x = value.location.x - geometry[frame].minX
                                if let minutes: Double = proxy.value(atX: x) {
                                    selectedTime = min(replay.duration, max(0, minutes * 60))
                                }
                            })
                    }
                }
                .frame(height: 140)
            }
        }
    }

    private struct GraphPoint: Identifiable {
        let sample: RunReplaySample
        let series: Int
        var id: Int { sample.id }
    }

    private func graphPoints(_ samples: [RunReplaySample], heartRate: Bool) -> [GraphPoint] {
        var result: [GraphPoint] = []
        var series = 0
        var previous: RunReplaySample?
        for sample in samples {
            let hasValue = heartRate ? sample.heartRate != nil : sample.pace != nil
            guard hasValue else { previous = nil; continue }
            if previous == nil || previous?.section != sample.section { series += 1 }
            result.append(GraphPoint(sample: sample, series: series))
            previous = sample
        }
        // Bound chart work for long runs, retaining the extrema and endpoints
        // of each bucket and both sides of measurement gaps.
        let bucketSize = max(1, result.count / 500)
        guard bucketSize > 1 else { return result }
        var reduced: [GraphPoint] = []
        for start in stride(from: 0, to: result.count, by: bucketSize) {
            let bucket = Array(result[start..<min(result.count, start + bucketSize)])
            let ordered = bucket.sorted {
                let a = heartRate ? Double($0.sample.heartRate ?? 0) : ($0.sample.pace ?? 0)
                let b = heartRate ? Double($1.sample.heartRate ?? 0) : ($1.sample.pace ?? 0)
                return a < b
            }
            var keep = Set([bucket.first!.id, bucket.last!.id, ordered.first!.id, ordered.last!.id])
            for pair in zip(bucket, bucket.dropFirst()) where pair.0.series != pair.1.series {
                keep.insert(pair.0.id); keep.insert(pair.1.id)
            }
            reduced.append(contentsOf: bucket.filter { keep.contains($0.id) })
        }
        return reduced
    }

    private func formatPace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm else { return "—" }
        return distanceUnit.formattedPace(secondsPerKm: secondsPerKm, includeUnit: false)
    }

    private func splits(_ replay: RunReplayAnalysis) -> some View {
        let unitSplits = replay.splits(in: distanceUnit)
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(distanceUnit.singular.capitalized) splits").font(.headline)
            Text("Compare full \(distanceUnit.label.lowercased()); the last partial split is labeled.").font(.caption).foregroundStyle(.secondary)
            let fastest = unitSplits.map(\.pace).min() ?? 1
            ForEach(unitSplits) { split in
                Button {
                    selectedTime = split.endTimestamp
                } label: {
                    HStack(spacing: 10) {
                        Text(split.isPartial ? distanceUnit.formattedDistance(meters: split.distanceMeters) : "\(distanceUnit.symbol.capitalized) \(split.id)")
                            .font(.caption).frame(width: 58, alignment: .leading)
                        GeometryReader { geometry in
                            Capsule().fill(.indigo.opacity(0.14))
                            Capsule().fill(.indigo.opacity(0.75)).frame(width: max(4, geometry.size.width * fastest / split.pace))
                        }.frame(height: 10)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(formatPace(split.pace)) /\(distanceUnit.symbol)").font(.caption.monospacedDigit().weight(.semibold))
                            if let hr = split.averageHeartRate { Text("\(hr) bpm").font(.caption2).foregroundStyle(.secondary) }
                        }.frame(width: 82, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Text("Longer bar = faster pace. Tap a split to inspect its finish.").font(.caption2).foregroundStyle(.secondary)
        }.padding().pastelTintedCard(.pastelMint)
    }
}
