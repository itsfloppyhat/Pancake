//
//  PancakeApp.swift
//  Pancake
//
//  Created by Matthew Lucas on 8/7/25.
//

import CloudKit
import SwiftUI
import UIKit

@main
struct PancakeApp: App {
    @UIApplicationDelegateAdaptor(PancakeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .task {
                    await DebugSimulatorRunOrchestrator.startIfRequested()
                }
                #endif
        }
    }
}

/// Routes scene connections through a scene delegate so CloudKit share
/// invitations (Cheer Squad links) can be accepted.
final class PancakeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = PancakeSceneDelegate.self
        }
        return configuration
    }
}

final class PancakeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            acceptShare(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        acceptShare(cloudKitShareMetadata)
    }

    private func acceptShare(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            await CheerSquadManager.shared.acceptShare(metadata: metadata)
        }
    }
}

#if DEBUG
func PancakeSimulatorLog(_ message: String) {
    print(message)

    guard let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("pancake-sim.log") else {
        return
    }

    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    let data = Data(line.utf8)

    if FileManager.default.fileExists(atPath: logURL.path),
       let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: logURL, options: .atomic)
    }
}

@MainActor
private enum DebugSimulatorRunOrchestrator {
    private static let runArgument = "--pancake-simulated-run"
    private static let runEnvironmentKey = "PANCAKE_SIMULATED_RUN"
    private static var didStart = false

    static func startIfRequested() async {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains(runArgument) ||
                processInfo.environment[runEnvironmentKey] == "1" else {
            return
        }

        guard !didStart else { return }
        didStart = true

        OnboardingManager.shared.completeOnboarding()
        seedSimulatorTasteIfNeeded()

        PancakeSimulatorLog("PANCAKE_SIM: iPhone waiting for paired watch simulator")
        let watchReady = await waitForWatchReadiness()
        if !watchReady {
            PancakeSimulatorLog("PANCAKE_SIM: iPhone timed out waiting for watch pairing; sending plan anyway")
        }

        let segments = simulatedRunSegments()
        WorkoutMusicCoordinator.shared.setPendingRunPlan(segments)
        WatchConnectivityManager.shared.sendRunPlan(segments)
        PancakeSimulatorLog("PANCAKE_SIM: iPhone sent run plan segments=\(segments.count) totalSeconds=\(segments.reduce(0) { $0 + $1.target.timeSeconds })")
    }

    private static func waitForWatchReadiness() async -> Bool {
        for _ in 0..<80 {
            let connectivity = WatchConnectivityManager.shared
            if connectivity.isWatchPaired && connectivity.isWatchAppInstalled {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return false
    }

    private static func simulatedRunSegments() -> [RunSegment] {
        [
            RunSegment(intensity: .zone2, target: .time(seconds: 20)),
            RunSegment(intensity: .zone3, target: .time(seconds: 20)),
            RunSegment(intensity: .zone4, target: .time(seconds: 25)),
            RunSegment(intensity: .zone2, target: .time(seconds: 20)),
            RunSegment(intensity: .zone5, target: .time(seconds: 15)),
            RunSegment(intensity: .zone1, target: .time(seconds: 15))
        ]
    }

    private static func seedSimulatorTasteIfNeeded() {
        let profileManager = UserProfileManager.shared
        let currentPreferences = profileManager.userProfile.musicPreferences
        guard currentPreferences.allFavoriteSongs.isEmpty,
              currentPreferences.allFavoriteArtists.isEmpty,
              currentPreferences.allFavoriteGenres.allSatisfy({ !$0.isSelected }) else {
            PancakeSimulatorLog("PANCAKE_SIM: iPhone using stored music taste")
            return
        }

        let preferences = MusicPreferences(
            favoriteArtists: [
                MusicArtist(id: "the-killers", name: "The Killers"),
                MusicArtist(id: "taylor-swift", name: "Taylor Swift"),
                MusicArtist(id: "tame-impala", name: "Tame Impala")
            ],
            favoriteSongs: [
                MusicSong(id: "sim-favorite-1", title: "Mr. Brightside", artist: "The Killers", duration: 222),
                MusicSong(id: "sim-favorite-2", title: "Cruel Summer", artist: "Taylor Swift", duration: 178),
                MusicSong(id: "sim-favorite-3", title: "The Less I Know The Better", artist: "Tame Impala", duration: 216)
            ],
            favoriteGenres: [
                MusicGenre(id: "indie-rock", name: "Indie Rock", isSelected: true),
                MusicGenre(id: "pop", name: "Pop", isSelected: true),
                MusicGenre(id: "electronic", name: "Electronic", isSelected: true)
            ],
            selectedPlaylist: ImportedPlaylist(id: "sim-tempo-loop", name: "Simulator Tempo Loop", songCount: 8),
            importedPlaylistArtists: [
                MusicArtist(id: "dua-lipa", name: "Dua Lipa"),
                MusicArtist(id: "lcd-soundsystem", name: "LCD Soundsystem")
            ],
            importedPlaylistSongs: [
                MusicSong(id: "sim-playlist-1", title: "Levitating", artist: "Dua Lipa", duration: 203),
                MusicSong(id: "sim-playlist-2", title: "All My Friends", artist: "LCD Soundsystem", duration: 462),
                MusicSong(id: "sim-playlist-3", title: "Dog Days Are Over", artist: "Florence + The Machine", duration: 252)
            ],
            importedPlaylistGenres: [
                MusicGenre(id: "dance-pop", name: "Dance Pop", isSelected: true)
            ]
        )

        profileManager.updateMusicPreferences(preferences)
        PancakeSimulatorLog("PANCAKE_SIM: iPhone seeded simulator music taste because no stored Apple Music taste was available")
    }
}
#else
func PancakeSimulatorLog(_ message: String) {}
#endif
