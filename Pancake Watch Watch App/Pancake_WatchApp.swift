//
//  Pancake Watch Watch App
//
//  Created by Matthew Lucas on 8/7/25.
//

import HealthKit
import SwiftUI
import WatchKit

@main
struct Pancake_Watch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(PancakeWatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Receives the workout configuration sent by `HKHealthStore.startWatchApp(with:)`
/// when the runner taps "Send run plan" on iPhone. The plan itself still arrives over
/// WatchConnectivity — this only tells the UI that the phone opened us on purpose.
final class PancakeWatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated {
            IntervalNotificationManager.shared.register()
            _ = WatchConnectivityManager.shared
        }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        MainActor.assumeIsolated {
            WatchWorkoutLaunchCoordinator.shared.handleLaunchFromPhone()
        }
    }
}
