import Foundation
import Combine
import AVFoundation

// MARK: - Speech Delegate
final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 Speech started: \(utterance.speechString)")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("🎤 Speech finished: \(utterance.speechString)")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("🎤 Speech cancelled: \(utterance.speechString)")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        print("🎤 Speech speaking range: \(characterRange)")
    }
}

// MARK: - Workout Music Coordinator
@MainActor
final class WorkoutMusicCoordinator: ObservableObject {
    static let shared = WorkoutMusicCoordinator()
    
    @Published var isWorkoutActive = false
    @Published var currentWorkoutContext: WorkoutContext?
    @Published var lastMusicSuggestion: MusicSuggestion?
    
    private let musicManager = MusicPlaybackManager.shared
    private let chatGPTService = ChatGPTService.shared
    private let profileManager = UserProfileManager.shared
    private let watchConnectivity = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Speech synthesis
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()
    
    private init() {
        setupWatchConnectivity()
        setupMusicManager()
        setupSpeechSynthesizer()
    }
    
    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = speechDelegate
    }
    
    // MARK: - Setup
    
    private func setupWatchConnectivity() {
        // Listen for music-related messages from WatchConnectivityManager
        NotificationCenter.default.addObserver(
            forName: .requestMusicSuggestion,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.generateNextSong()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .playbackControl,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let action = message["action"] as? String {
                Task { @MainActor in
                    self?.handlePlaybackControl(action)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .workoutControl,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let action = message["action"] as? String {
                Task { @MainActor in
                    self?.handleWorkoutControl(action)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .workoutHeartRate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let heartRate = message["heartRate"] as? Int {
                Task { @MainActor in
                    self?.handleHeartRateUpdate(heartRate)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .segmentChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? [String: Any],
               let segmentIndex = message["currentSegmentIndex"] as? Int {
                Task { @MainActor in
                    self?.handleSegmentChange(segmentIndex: segmentIndex)
                }
            }
        }
    }
    
    private func setupMusicManager() {
        // Listen for music playback changes
        musicManager.$currentSong
            .sink { [weak self] song in
                self?.sendCurrentSongToWatch(song)
            }
            .store(in: &cancellables)
        
        musicManager.$isPlaying
            .sink { [weak self] isPlaying in
                self?.sendPlaybackStateToWatch(isPlaying)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Workout Management
    
    func startWorkoutMusic(segments: [RunSegment]) {
        print("🎵 WorkoutMusicCoordinator.startWorkoutMusic called with \(segments.count) segments")
        
        guard !isWorkoutActive else { 
            print("⚠️ Workout already active, ignoring start request")
            return 
        }
        
        isWorkoutActive = true
        print("✅ Workout marked as active")
        
        // Create initial workout context
        let context = WorkoutContext(
            segments: segments,
            currentSegmentIndex: 0,
            totalDistance: 0,
            totalTime: 0,
            heartRate: nil,
            targetHeartRate: nil
        )
        
        currentWorkoutContext = context
        print("📊 Workout context created")
        
        // Start music playback immediately
        print("🎵 Starting music manager...")
        musicManager.startWorkoutMusic(workoutContext: context)
        
        // Send workout start to watch (if available)
        sendWorkoutStartToWatch(segments: segments)
        
        // Generate starting song suggestion
        print("🤖 Starting ChatGPT song generation...")
        Task {
            await generateStartingSong()
        }
        
        // Generate and play motivational speech after 10 seconds
        print("🎤 Scheduling motivational speech in 10 seconds...")
        Task {
            await generateAndPlayMotivationalSpeech()
            print("✅ Initial motivational speech completed successfully")
        }
    }
    
    func stopWorkoutMusic() {
        guard isWorkoutActive else { return }
        
        isWorkoutActive = false
        currentWorkoutContext = nil
        
        // Stop music playback
        musicManager.stopWorkoutMusic()
        
        // Send workout stop to watch
        sendWorkoutStopToWatch()
    }
    
    func updateWorkoutContext(
        currentSegmentIndex: Int,
        totalDistance: Double,
        totalTime: TimeInterval,
        heartRate: Int?,
        targetHeartRate: Int?
    ) {
        guard let context = currentWorkoutContext else { return }
        
        let updatedContext = WorkoutContext(
            segments: context.segments,
            currentSegmentIndex: currentSegmentIndex,
            totalDistance: totalDistance,
            totalTime: totalTime,
            heartRate: heartRate,
            targetHeartRate: targetHeartRate
        )
        
        currentWorkoutContext = updatedContext
        musicManager.updateWorkoutContext(updatedContext)
        
        // Check for distance milestones (only for single segment workouts)
        checkForDistanceMilestone(previousDistance: context.totalDistance, newDistance: totalDistance)
        
        // Send updated context to watch
        sendWorkoutContextToWatch(updatedContext)
    }
    
    private func checkForDistanceMilestone(previousDistance: Double, newDistance: Double) {
        // Only trigger for single segment workouts
        guard let context = currentWorkoutContext, context.segments.count == 1 else { return }
        
        let previousKm = Int(previousDistance / 1000)
        let newKm = Int(newDistance / 1000)
        
        // Check if we've crossed a kilometer milestone
        if newKm > previousKm && newKm > 0 {
            print("🎤 Distance milestone reached: \(newKm)km")
            Task {
                await generateAndPlayWorkoutMotivation(
                    segmentChange: false,
                    distanceMilestone: true
                )
            }
        }
    }
    
    // MARK: - Music Suggestion Generation
    
    func generateStartingSong() async {
        guard let context = currentWorkoutContext else { return }
        
        do {
            let suggestion = try await chatGPTService.generateStartingSongSuggestion(
                workoutPlan: context.segments,
                userPreferences: profileManager.userProfile.musicPreferences,
                currentIntensity: context.currentSegment.intensity
            )
            
            lastMusicSuggestion = suggestion
            await playSuggestedSong(suggestion)
            
        } catch {
            print("Failed to generate starting song: \(error)")
        }
    }
    
    func generateNextSong() async {
        guard let context = currentWorkoutContext else { return }
        
        do {
            let suggestion = try await chatGPTService.generateIntervalChangeSuggestion(
                context: context.musicContext,
                userPreferences: profileManager.userProfile.musicPreferences,
                currentDistance: context.totalDistance,
                currentTime: context.totalTime,
                upcomingIntensity: context.upcomingSegment?.intensity
            )
            
            lastMusicSuggestion = suggestion
            await playSuggestedSong(suggestion)
            
        } catch {
            print("Failed to generate next song: \(error)")
        }
    }
    
    private func playSuggestedSong(_ suggestion: MusicSuggestion) async {
        // This will be handled by the MusicPlaybackManager
        // We just need to trigger the search and playback
        await musicManager.generateNextSongSuggestion()
    }
    
    private func generateAndPlayMotivationalSpeech() async {
        print("🎤 Starting motivational speech generation...")
        
        guard let context = currentWorkoutContext else { 
            print("❌ No workout context available for motivational speech")
            return 
        }
        
        print("🎤 Workout context found, generating speech for \(context.segments.count) segments")
        
        do {
            let speech = try await chatGPTService.generateMotivationalSpeech(workoutPlan: context.segments)
            print("🎤 Generated motivational speech: \(speech)")
            
            // Play the speech with faded music
            await playMotivationalSpeech(speech)
            
        } catch {
            print("❌ Failed to generate motivational speech: \(error)")
        }
    }
    
    private func playMotivationalSpeech(_ speech: String) async {
        // Wait 10 seconds before starting speech
        print("🎤 Waiting 10 seconds before starting motivational speech...")
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        
        print("🎤 10 seconds elapsed, starting speech playback...")
        
        await MainActor.run {
            // Fade out music for speech
            print("🎵 Fading out music for speech...")
            musicManager.fadeOutMusic()
        }
        
        // Wait a moment for fade to complete
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        await MainActor.run {
            // Use the retained AVSpeechSynthesizer for text-to-speech
            let utterance = AVSpeechUtterance(string: speech)
            utterance.rate = 0.5 // Slower rate for motivational speech
            utterance.volume = 0.8
            
            // Try to get a good voice
            if let voice = AVSpeechSynthesisVoice(language: "en-US") {
                utterance.voice = voice
                print("🎤 Using voice: \(voice.name)")
            } else {
                print("⚠️ Could not get en-US voice, using default")
            }
            
            print("🎤 Playing motivational speech: \(speech)")
            print("🎤 Speech rate: \(utterance.rate), volume: \(utterance.volume)")
            
            // Stop any current speech and start new one
            speechSynthesizer.stopSpeaking(at: .immediate)
            speechSynthesizer.speak(utterance)
        }
        
        // Wait for speech to complete (estimate based on speech length + buffer)
        let estimatedDuration = Double(speech.count) * 0.1 + 1.0 // 1 second buffer
        print("🎤 Waiting \(estimatedDuration) seconds for speech to complete...")
        try? await Task.sleep(nanoseconds: UInt64(estimatedDuration * 1_000_000_000))
        
        await MainActor.run {
            // Fade music back in after speech
            print("🎵 Fading music back in after speech...")
            musicManager.fadeInMusic()
        }
        
        print("🎤 Motivational speech completed")
    }
    
    private func generateAndPlayWorkoutMotivation(
        segmentChange: Bool,
        distanceMilestone: Bool
    ) async {
        guard let context = currentWorkoutContext else { return }
        
        do {
            let motivation = try await chatGPTService.generateWorkoutMotivation(
                segmentChange: segmentChange,
                distanceMilestone: distanceMilestone,
                currentIntensity: context.currentSegment.intensity,
                heartRate: context.musicContext.currentHeartRate,
                totalDistance: context.totalDistance
            )
            
            print("🎤 Generated workout motivation: \(motivation)")
            await playWorkoutMotivation(motivation)
            
        } catch {
            print("Failed to generate workout motivation: \(error)")
        }
    }
    
    private func playWorkoutMotivation(_ motivation: String) async {
        await MainActor.run {
            // Fade out music for motivation
            print("🎵 Fading out music for motivation...")
            musicManager.fadeOutMusic()
        }
        
        // Wait a moment for fade to complete
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            // Use the retained AVSpeechSynthesizer for text-to-speech
            let utterance = AVSpeechUtterance(string: motivation)
            utterance.rate = 0.6 // Slightly faster for shorter messages
            utterance.volume = 0.8
            
            // Try to get a good voice
            if let voice = AVSpeechSynthesisVoice(language: "en-US") {
                utterance.voice = voice
            }
            
            print("🎤 Playing workout motivation: \(motivation)")
            
            // Stop any current speech and start new one
            speechSynthesizer.stopSpeaking(at: .immediate)
            speechSynthesizer.speak(utterance)
        }
        
        // Wait for motivation to complete (shorter duration for shorter messages)
        let estimatedDuration = Double(motivation.count) * 0.08 + 1.0 // Shorter buffer
        print("🎤 Waiting \(estimatedDuration) seconds for motivation to complete...")
        try? await Task.sleep(nanoseconds: UInt64(estimatedDuration * 1_000_000_000))
        
        await MainActor.run {
            // Fade music back in after motivation
            print("🎵 Fading music back in after motivation...")
            musicManager.fadeInMusic()
        }
        
        print("🎤 Workout motivation completed")
    }
    
    // MARK: - Watch Communication
    
    private func sendWorkoutStartToWatch(segments: [RunSegment]) {
        // Use fallback method for workout start - critical message
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { 
            print("Watch not paired or app not installed - will work in standalone mode")
            return 
        }
        
        let message: [String: Any] = [
            "type": WatchMessageType.workoutStart.rawValue,
            "segments": segments.map { segment in
                [
                    "intensity": segment.intensity.rawValue,
                    "target": [
                        "type": segment.target.isTime ? "time" : "distance",
                        "value": segment.target.isTime ? segment.target.timeSeconds : segment.target.distanceMeters
                    ]
                ]
            }
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send workout start to watch: \(error)")
        }
    }
    
    private func sendWorkoutStopToWatch() {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.workoutStop.rawValue
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send workout stop to watch: \(error)")
        }
    }
    
    private func sendWorkoutContextToWatch(_ context: WorkoutContext) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.workoutUpdate.rawValue,
            "currentSegmentIndex": context.currentSegmentIndex,
            "totalDistance": context.totalDistance,
            "totalTime": context.totalTime,
            "heartRate": context.musicContext.currentHeartRate as Any,
            "targetHeartRate": context.musicContext.targetHeartRate as Any
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send workout context to watch: \(error)")
        }
    }
    
    private func sendCurrentSongToWatch(_ song: MusicSong?) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        do {
            let songData = song != nil ? try JSONEncoder().encode(song!) : nil
            let message: [String: Any] = [
                "type": WatchMessageType.currentSong.rawValue,
                "song": songData as Any
            ]
            
            watchConnectivity.sendMessageWithFallback(message) { error in
                print("Failed to send current song to watch: \(error)")
            }
        } catch {
            print("Failed to encode current song: \(error)")
        }
    }
    
    private func sendPlaybackStateToWatch(_ isPlaying: Bool) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.playbackControl.rawValue,
            "isPlaying": isPlaying
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send playback state to watch: \(error)")
        }
    }
    
    private func sendMusicSuggestionToWatch(_ suggestion: MusicSuggestion) {
        guard watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.musicSuggestion.rawValue,
            "suggestion": [
                "songTitle": suggestion.songTitle,
                "artist": suggestion.artist,
                "reason": suggestion.reason,
                "mood": suggestion.mood.rawValue,
                "confidence": suggestion.confidence
            ]
        ]
        
        watchConnectivity.sendMessageWithFallback(message) { error in
            print("Failed to send music suggestion to watch: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func handlePlaybackControl(_ action: String) {
        switch action {
        case "play":
            musicManager.play()
        case "pause":
            musicManager.pause()
        case "stop":
            musicManager.stop()
        case "next":
            musicManager.skipToNext()
        case "previous":
            musicManager.skipToPrevious()
        case "suggest":
            Task {
                await generateNextSong()
            }
        default:
            break
        }
    }
    
    private func handleWorkoutControl(_ action: String) {
        switch action {
        case "end":
            print("🏃 Ending workout from watch")
            stopWorkoutMusic()
        case "pause":
            print("🏃 Pausing workout from watch")
            // Could implement workout pause here if needed
        default:
            break
        }
    }
    
    private func handleHeartRateUpdate(_ heartRate: Int) {
        guard let context = currentWorkoutContext else { return }
        
        updateWorkoutContext(
            currentSegmentIndex: context.currentSegmentIndex,
            totalDistance: context.totalDistance,
            totalTime: context.totalTime,
            heartRate: heartRate,
            targetHeartRate: context.musicContext.targetHeartRate
        )
    }
    
    private func handleSegmentChange(segmentIndex: Int) {
        print("🏃 Handling segment change to index: \(segmentIndex)")
        
        guard let context = currentWorkoutContext else {
            print("⚠️ No workout context available for segment change")
            return
        }
        
        // Update the workout context with the new segment index
        let updatedContext = WorkoutContext(
            segments: context.segments,
            currentSegmentIndex: segmentIndex,
            totalDistance: context.totalDistance,
            totalTime: context.totalTime,
            heartRate: context.musicContext.currentHeartRate,
            targetHeartRate: context.musicContext.targetHeartRate
        )
        
        currentWorkoutContext = updatedContext
        musicManager.updateWorkoutContext(updatedContext)
        
        // Generate motivational message for new segment
        print("🎤 Generating motivation for new segment")
        Task {
            await generateAndPlayWorkoutMotivation(
                segmentChange: true,
                distanceMilestone: false
            )
        }
        
        // Generate a new song suggestion for the new segment
        print("🎵 Generating new song for segment \(segmentIndex + 1)/\(context.segments.count)")
        Task {
            await generateNextSong()
        }
    }
}

// MARK: - Extensions
extension Target {
    var isTime: Bool {
        if case .time = self { return true }
        return false
    }
    
    var isDistance: Bool {
        if case .distance = self { return true }
        return false
    }
    
    var timeSeconds: Int {
        if case .time(let seconds) = self { return seconds }
        return 0
    }
    
    var distanceMeters: Int {
        if case .distance(let meters) = self { return meters }
        return 0
    }
}
