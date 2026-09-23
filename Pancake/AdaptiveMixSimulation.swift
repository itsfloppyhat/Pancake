#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Deterministic recording assessments for the synthetic playback loop only.
/// They exercise queue orchestration and filtering, not AI musical judgment.
@MainActor
enum AdaptiveMixSimulation {
    static var usesLocalTransitionDriver: Bool {
        ProcessInfo.processInfo.environment["PANCAKE_SIM_LOCAL_TRANSITION_TEST"] == "1"
    }
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--pancake-simulated-music") ||
            ProcessInfo.processInfo.environment["PANCAKE_SIMULATED_MUSIC"] == "1"
    }

    private static var batch = 0
    private static let launchID = UUID().uuidString.prefix(8)
    private static var assessments: [String: MusicEnergyAssessment] = [:]

    static func suggestions(for goal: AdaptiveMixGoalScore) -> [MusicSuggestion] {
        batch += 1
        let level: MusicEnergyLevel
        switch goal.targetIntensity {
        case .zone1: level = .calm
        case .zone2: level = .gentle
        case .zone3: level = goal.guidance == .easeDown ? .gentle : .steady
        case .zone4: level = .driving
        case .zone5: level = goal.guidance == .easeDown ? .driving : .explosive
        }
        return (0..<5).map { index in
            let ballad = index == 0 && goal.targetIntensity.zoneNumber >= 4
            let suggestion = MusicSuggestion(
                songTitle: "Simulator \(ballad ? "ballad" : level.rawValue) \(launchID)-\(batch)-\(index)",
                artist: "Pancake Test Fixture", reason: "Synthetic transition test",
                mood: MusicRecommendationPolicy.defaultMood(for: goal.targetIntensity), confidence: 1
            )
            assessments[suggestion.sessionSongKey] = MusicEnergyAssessment(
                level: ballad ? .calm : level, hasImmediateBeat: !ballad,
                isBallad: ballad, confidence: 1
            )
            return suggestion
        }
    }

    static func review(_ candidates: [MusicSuggestion]) -> [String: MusicEnergyAssessment] {
        var result: [String: MusicEnergyAssessment] = [:]
        for candidate in candidates {
            result[candidate.sessionSongKey] = assessments[candidate.sessionSongKey]
        }
        return result
    }

    /// Uses the existing virtual watch when simulator WatchConnectivity is
    /// unavailable. Time advances tenfold; the production coordinator, player,
    /// suitability gate, and skip handlers remain in use.
    static func runLocalTransitionTest() async {
        _ = WorkoutMusicCoordinator.shared
        let driver = RunSandboxDriver.shared
        driver.speedMetersPerSecond = 0
        driver.heartRate = 70
        driver.start(plan: [
            RunSegment(intensity: .zone1, target: .time(seconds: 60)),
            RunSegment(intensity: .zone5, target: .time(seconds: 60))
        ])
        while !WorkoutMusicCoordinator.shared.isWorkoutActive { try? await Task.sleep(for: .milliseconds(25)) }
        await WorkoutMusicCoordinator.shared.startAdaptiveMixUserRequested()
        if ProcessInfo.processInfo.environment["PANCAKE_SIM_PAUSED_TRANSITION_TEST"] == "1" {
            while driver.totalTime < 40 { try? await Task.sleep(for: .milliseconds(25)) }
            NotificationCenter.default.post(name: .playbackControl, object: ["action": "pause"])
            while driver.totalTime < 65 { try? await Task.sleep(for: .milliseconds(25)) }
            let stayedPaused = !MusicPlaybackManager.shared.isPlaying &&
                MusicPlaybackManager.shared.currentSong?.title.contains("calm") == true
            PancakeSimulatorLog("PANCAKE_SIM:PAUSE_PRESERVED=\(stayedPaused)")
            NotificationCenter.default.post(name: .playbackControl, object: ["action": "play"])
        }
        for time in [80.0, 85.0] {
            while driver.totalTime < time { try? await Task.sleep(for: .milliseconds(25)) }
            NotificationCenter.default.post(name: .playbackControl, object: ["action": "next"])
            PancakeSimulatorLog("PANCAKE_SIM: Local requested next song at \(time)")
        }
        while driver.totalTime < 120 { try? await Task.sleep(for: .milliseconds(25)) }
        driver.stop()
        PancakeSimulatorLog("PANCAKE_SIM:LOCAL_TRANSITION_COMPLETE")
    }
}
#endif
