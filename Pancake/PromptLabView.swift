import SwiftUI

struct PromptLabView: View {
    @StateObject private var viewModel = PromptLabViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            promptContainer
            .navigationTitle("Song Check")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear Error") {
                        viewModel.clearError()
                    }
                    .disabled(viewModel.error == nil)
                }
#else
                ToolbarItem(placement: .automatic) {
                    Button("Clear Error") {
                        viewModel.clearError()
                    }
                    .disabled(viewModel.error == nil)
                }
#endif
            }
            .onAppear {
                viewModel.refreshAuthorizationState()
            }
            .onDisappear {
                viewModel.endSongCheck()
            }
        }
    }

    @ViewBuilder
    private var promptContainer: some View {
#if os(macOS)
        List {
            promptSections
        }
        .listStyle(.inset)
#else
        Form {
            promptSections
        }
#endif
    }

    @ViewBuilder
    private var promptSections: some View {
        Section {
            Text("Preview an Adaptive Mix against simulated running metrics without starting a workout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LabeledContent("Saved taste profile") {
                Text(viewModel.currentTasteSummary)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Song Check")
        }

        adaptiveMixPreviewSection

        Section("Taste Inputs") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Favorite Artists")
                TextEditor(text: $viewModel.favoriteArtistsInput)
                    .frame(minHeight: 54)
                Text("Use commas or new lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Favorite Songs")
                TextEditor(text: $viewModel.favoriteSongsInput)
                    .frame(minHeight: 72)
                Text("Format each entry as `Song - Artist` or `Song by Artist`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Favorite Genres")
                TextEditor(text: $viewModel.favoriteGenresInput)
                    .frame(minHeight: 54)
                Text("Use commas or new lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Save Taste Profile") {
                    viewModel.saveTasteInputs()
                }

                Spacer()

                Button("Reset") {
                    viewModel.resetTasteInputsFromProfile()
                }
            }
        }

        Section("Music Access") {
            PromptLabAccessRow(
                icon: "music.note.list",
                title: "Library Taste Import",
                subtitle: viewModel.isLibraryAuthorized ? "Library access is ready." : "Optional. Import taste or play songs saved in your library.",
                isConnected: viewModel.isLibraryAuthorized,
                buttonTitle: "Continue"
            ) {
                viewModel.requestLibraryAuthorization()
            }

            PromptLabAccessRow(
                icon: "play.circle",
                title: "Apple Music Playback",
                subtitle: viewModel.isCatalogAuthorized ? "Catalog playback is ready." : "Optional. Play suggestions from the Apple Music catalog.",
                isConnected: viewModel.isCatalogAuthorized,
                buttonTitle: "Continue"
            ) {
                Task {
                    await viewModel.requestCatalogAuthorization()
                }
            }

        }

        Section("During-Run Metrics") {
            Picker("Workout Phase", selection: $viewModel.selectedWorkoutPhase) {
                ForEach(WorkoutPhase.allCases) { phase in
                    Text(phase.displayName).tag(phase)
                }
            }

            Picker("Target Zone", selection: $viewModel.selectedIntensity) {
                ForEach(Intensity.allCases) { intensity in
                    Text(intensity.label).tag(intensity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current Heart Rate")
                    Spacer()
                    Text("\(Int(viewModel.currentHeartRate)) BPM")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $viewModel.currentHeartRate, in: 80...195, step: 1)

                Text("Target for \(viewModel.selectedIntensity.label): \(viewModel.currentTargetHeartRate) BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Heart-Rate Trend", selection: $viewModel.heartRateTrend) {
                ForEach([HeartRateTrend.rising, .steady, .falling, .unknown], id: \.self) { trend in
                    Text(trend.promptDescription.replacingOccurrences(of: "Heart rate trend is ", with: "").replacingOccurrences(of: ".", with: "").capitalized)
                        .tag(trend)
                }
            }

            Toggle("Stable heart-rate signal", isOn: $viewModel.hasStableHeartRateSignal)
            Toggle("Runner is actively moving", isOn: $viewModel.isRunnerActive)

            PromptLabSliderRow(
                title: "Distance",
                valueText: String(format: "%.1f km", viewModel.currentDistance),
                value: $viewModel.currentDistance,
                range: 0...30,
                step: 0.1
            )

            PromptLabSliderRow(
                title: "Elapsed Time",
                valueText: "\(Int(viewModel.currentTimeMinutes)) min",
                value: $viewModel.currentTimeMinutes,
                range: 1...180,
                step: 1
            )

            PromptLabSliderRow(
                title: "Time Remaining In Segment",
                valueText: "\(Int(viewModel.timeRemainingInSegmentMinutes)) min",
                value: $viewModel.timeRemainingInSegmentMinutes,
                range: 1...20,
                step: 1
            )

            PromptLabSliderRow(
                title: "Current Song Ends In",
                valueText: "\(Int(viewModel.currentSongEndingInSeconds)) sec",
                value: $viewModel.currentSongEndingInSeconds,
                range: 5...60,
                step: 1
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Songs To Include In Prompt")
                TextEditor(text: $viewModel.recentSongsInput)
                    .frame(minHeight: 72)
                Text("Use commas or new lines. Format each entry as `Song - Artist` or `Song by Artist`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Quick Scenarios") {
            HStack {
                Button("Zone 2 5K") {
                    viewModel.setEasy5KScenario()
                }

                Spacer()

                Button("Zone 3 Tempo") {
                    viewModel.setTempoScenario()
                }
            }

            HStack {
                Button("Zone 4 Interval") {
                    viewModel.setIntervalScenario()
                }

                Spacer()

                Button("Zone 1 Recovery") {
                    viewModel.setRecoveryScenario()
                }
            }

            HStack {
                Button("Zone 5 Sprint") {
                    viewModel.setZone5Scenario()
                }

                Spacer()
            }
        }

#if DEBUG
        Section(viewModel.promptPreview.promptTitle) {
            ForEach(viewModel.promptPreview.sections) { section in
                PromptPreviewCard(section: section)
            }

            DisclosureGroup("Full Prompt") {
                Text(viewModel.promptPreview.fullPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
#endif

    }

    @ViewBuilder
    private var adaptiveMixPreviewSection: some View {
        Section("Adaptive Mix Preview") {
            Button {
                Task {
                    await viewModel.startAdaptiveMixPreview()
                }
            } label: {
                Label(
                    viewModel.isAdaptiveMixPreviewActive ? "Refresh Upcoming Songs" : "Generate And Play Mix",
                    systemImage: viewModel.isAdaptiveMixPreviewActive ? "arrow.clockwise" : "play.circle.fill"
                )
            }
            .disabled(viewModel.isGenerating || !viewModel.isCatalogAuthorized)

            if viewModel.isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Curating verified Apple Music songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isAdaptiveMixPreviewActive {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Next refresh", systemImage: "timer")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text("\(viewModel.adaptiveMixPreviewSecondsUntilRefresh)s")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: viewModel.adaptiveMixPreviewProgress)
                        .tint(.pastelMint)

                    Text(viewModel.adaptiveMixPreviewDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let currentSong = viewModel.currentSong {
                    SongCheckNowPlayingRow(
                        song: currentSong,
                        playbackState: viewModel.playbackStateDescription
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Upcoming Playlist")
                        .font(.subheadline.weight(.semibold))

                    ForEach(Array(viewModel.adaptiveMixPreviewQueue.enumerated()), id: \.element.id) { index, song in
                        SongCheckQueueRow(position: index + 1, song: song)
                    }
                }
                .padding(.vertical, 4)

                HStack(spacing: 12) {
                    Button {
                        if viewModel.isPlaying {
                            viewModel.pausePlayback()
                        } else {
                            viewModel.resumePlayback()
                        }
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .help(viewModel.isPlaying ? "Pause" : "Resume")
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Resume")

                    Button {
                        Task {
                            await viewModel.skipAdaptiveMixPreviewToNext()
                        }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .help("Next Song")
                    .accessibilityLabel("Next Song")

                    Spacer()

                    Button(role: .destructive) {
                        viewModel.stopPlayback()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .help("Stop")
                    .accessibilityLabel("Stop")
                }
            }

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.pastelCoral)
            }
        }
    }
}

private struct PromptLabAccessRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isConnected: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isConnected ? .pastelMint : .pastelPeach)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.pastelMint)
            } else {
                Button(buttonTitle, action: action)
            }
        }
    }
}

private struct PromptLabSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct PromptPreviewCard: View {
    let section: MusicPromptSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)

            Text(section.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private struct SongCheckNowPlayingRow: View {
    let song: MusicSong
    let playbackState: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.pastelMint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(song.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(playbackState.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SongCheckQueueRow: View {
    let position: Int
    let song: MusicSong

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.pastelPeriwinkle)
                .frame(width: 22, height: 22)
                .background(Color.pastelPeriwinkle.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.pastelMint)
                .accessibilityLabel("Verified Apple Music song")
        }
    }
}

private struct GeneratedSuggestionCard: View {
    let suggestion: MusicSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.songTitle)
                .font(.headline)

            Text(suggestion.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(suggestion.mood.displayName)
                Spacer()
                Text("\(Int(suggestion.confidence * 100))% confidence")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct PromptLabView_Previews: PreviewProvider {
    static var previews: some View {
        PromptLabView()
    }
}
#endif
