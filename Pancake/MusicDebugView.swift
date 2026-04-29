import SwiftUI
import MediaPlayer

struct MusicDebugView: View {
    @StateObject private var viewModel = MusicDebugViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                // Music Authorization Status
                Section("Music Authorization") {
                    HStack {
                        Image(systemName: viewModel.isMusicAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(viewModel.isMusicAuthorized ? .pastelMint : .pastelCoral)
                        
                        VStack(alignment: .leading) {
                            Text("Apple Music Access")
                                .font(.headline)
                            Text("Status: \(viewModel.musicAuthorizationStatus)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !viewModel.isMusicAuthorized {
                            Button("Request Access") {
                                viewModel.requestMusicAuthorization()
                            }
                            .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
                        }
                    }
                }
                
                // Library Information
                Section("Music Library") {
                    HStack {
                        Image(systemName: "music.note.list")
                        Text("Total Songs in Library")
                        Spacer()
                        Text("\(viewModel.libraryCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Refresh Library Count") {
                        viewModel.loadLibraryCount()
                    }
                    .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                }
                
                // AI Status
                Section("Apple Intelligence") {
                    HStack {
                        Image(systemName: viewModel.isAIConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(viewModel.isAIConfigured ? .pastelMint : .pastelCoral)

                        VStack(alignment: .leading) {
                            Text("AI Status")
                                .font(.headline)
                            Text(viewModel.isAIConfigured ? "Available" : "Not Available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if viewModel.isAIConfigured {
                            Text("✅")
                        } else {
                            Text("❌")
                        }
                    }
                }
                
                // Interactive Music Generation Madlib
                Section("🎵 Music Generation Madlib") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Create a custom workout scenario and generate the perfect song!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Workout Phase Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Workout Phase")
                                .font(.headline)
                            
                            Picker("Workout Phase", selection: $viewModel.selectedWorkoutPhase) {
                                ForEach(WorkoutPhase.allCases) { phase in
                                    Text(phase.displayName).tag(phase)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Intensity Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Intensity Level")
                                .font(.headline)
                            
                            Picker("Intensity", selection: $viewModel.selectedIntensity) {
                                ForEach(Intensity.allCases) { intensity in
                                    Text(intensity.label).tag(intensity)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Heart Rate Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Heart Rate (BPM)")
                                .font(.headline)
                            
                            HStack {
                                Slider(
                                    value: $viewModel.currentHeartRate,
                                    in: 60...200,
                                    step: 5
                                ) {
                                    Text("Heart Rate")
                                }
                                
                                Text("\(Int(viewModel.currentHeartRate))")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.pastelPeriwinkle)
                                    .frame(width: 50)
                            }
                        }
                        
                        // Distance and Time Inputs
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Distance (km)")
                                    .font(.headline)
                                
                                HStack {
                                    Slider(
                                        value: $viewModel.currentDistance,
                                        in: 0...50,
                                        step: 0.5
                                    ) {
                                        Text("Distance")
                                    }
                                    
                                    Text("\(viewModel.currentDistance, specifier: "%.1f")")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.pastelPeriwinkle)
                                        .frame(width: 50)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Time (min)")
                                    .font(.headline)
                                
                                HStack {
                                    Slider(
                                        value: $viewModel.currentTime,
                                        in: 0...120,
                                        step: 1
                                    ) {
                                        Text("Time")
                                    }
                                    
                                    Text("\(Int(viewModel.currentTime))")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.pastelPeriwinkle)
                                        .frame(width: 50)
                                }
                            }
                        }
                        
                        // Library Selection Toggle
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Music Source")
                                .font(.headline)
                            
                            HStack {
                                Text("Prefer Library Songs")
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Toggle("", isOn: $viewModel.preferLibrarySelection)
                                    .labelsHidden()
                            }
                        }
                        
                        // Preset Scenarios
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Scenarios")
                                .font(.headline)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                Button("🏃‍♂️ Easy 5K") {
                                    viewModel.setEasy5KScenario()
                                }
                                .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                .font(.caption)
                                
                                Button("⚡ Interval Training") {
                                    viewModel.setIntervalScenario()
                                }
                                .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                .font(.caption)
                                
                                Button("🏁 Finish Strong") {
                                    viewModel.setFinishStrongScenario()
                                }
                                .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                .font(.caption)
                                
                                Button("🧘‍♀️ Recovery Run") {
                                    viewModel.setRecoveryScenario()
                                }
                                .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                .font(.caption)
                            }
                        }
                        
                        // Generate Button
                        Button(action: { Task { await viewModel.generateMadlibSuggestion() } }) {
                            HStack {
                                if viewModel.isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text("Generate Perfect Song")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelPrimary))
                        .disabled(viewModel.isTesting || !viewModel.isAIConfigured)
                        
                        // Template Preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Template Preview")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("🎭 Workout Phase: \(viewModel.selectedWorkoutPhase.displayName)")
                                    .font(.caption)
                                Text("⚡ Intensity: \(viewModel.selectedIntensity.label)")
                                    .font(.caption)
                                Text("💓 Heart Rate: \(Int(viewModel.currentHeartRate)) BPM")
                                    .font(.caption)
                                Text("📏 Distance: \(viewModel.currentDistance, specifier: "%.1f") km in \(Int(viewModel.currentTime)) min")
                                    .font(.caption)
                                Text("🎵 Source: \(viewModel.preferLibrarySelection ? "Library Songs" : "General Suggestions")")
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(Color.pastelLavender.opacity(0.08))
                            .cornerRadius(8)
                        }
                        
                        // Generated Suggestion Display
                        if let suggestion = viewModel.testSuggestion {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()
                                
                                Text("🎵 Generated Song:")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.songTitle)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    Text("by \(suggestion.artist)")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                    
                                    Text(suggestion.reason)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .italic()
                                    
                                    HStack {
                                        Text("Mood:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text(suggestion.mood.displayName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.pastelPeriwinkle)
                                        
                                        Spacer()
                                        
                                        Text("Confidence: \(Int(suggestion.confidence * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color.pastelLavender.opacity(0.08))
                                .cornerRadius(12)
                                
                                // Play Buttons
                                HStack(spacing: 12) {
                                    Button(action: { Task { await viewModel.playTestSuggestion() } }) {
                                        HStack {
                                            Image(systemName: "play.circle.fill")
                                            Text("Play from Library")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                    .disabled(!viewModel.isMusicAuthorized)
                                    
                                    Button(action: { Task { await viewModel.playAppleMusicSuggestion() } }) {
                                        HStack {
                                            Image(systemName: "music.note")
                                            Text("Play from Apple Music")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                    .disabled(!viewModel.isMusicAuthorized)
                                }
                                
                                // Search Results Button
                                Button(action: { Task { await viewModel.debugSearchResults() } }) {
                                    HStack {
                                        Image(systemName: "magnifyingglass.circle")
                                        Text("Show Search Results")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                                .disabled(!viewModel.isMusicAuthorized)
                            }
                        }
                    }
                }
                
                // Quick Test Buttons
                Section("Quick Tests") {
                    Button(action: { Task { await viewModel.testSimplePlayback() } }) {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Test Simple Playback")
                        }
                    }
                    .disabled(!viewModel.isMusicAuthorized)
                    
                    Button(action: { Task { await viewModel.debugLibraryContents() } }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Debug Library Contents")
                        }
                    }
                    .disabled(!viewModel.isMusicAuthorized)
                    
                    Button(action: { Task { await viewModel.testFallbackLogic() } }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Test Fallback Logic")
                        }
                    }
                    .disabled(!viewModel.isMusicAuthorized)
                }
                
                // Current Playback Status
                Section("Current Playback") {
                    HStack {
                        Image(systemName: viewModel.isPlaying ? "play.circle.fill" : "pause.circle.fill")
                            .foregroundColor(viewModel.isPlaying ? .pastelMint : .pastelPeach)
                        
                        VStack(alignment: .leading) {
                            Text("Playback Status")
                                .font(.headline)
                            Text(viewModel.isPlaying ? "Playing" : "Paused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let song = viewModel.currentSong {
                            VStack(alignment: .trailing) {
                                Text(song.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    if let error = viewModel.error {
                        Text("Error: \(error.localizedDescription)")
                            .font(.caption)
                            .foregroundColor(.pastelCoral)
                    }
                }
                
                // Debug Actions
                Section("Debug Actions") {
                    Button("Check Console Logs") {
                        // No-op: debug prints removed
                    }
                    .buttonStyle(.bordered)
                    .tint(.pastelLavender)
                }
            }
            .navigationTitle("Music Debug")
            .onAppear {
                viewModel.loadLibraryCount()
            }
        }
    }
}

extension MPMediaLibraryAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }
}

#if DEBUG
struct MusicDebugView_Previews: PreviewProvider {
    static var previews: some View {
        MusicDebugView()
    }
}
#endif
