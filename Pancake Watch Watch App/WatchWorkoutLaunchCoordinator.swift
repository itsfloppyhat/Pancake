import Foundation
import Combine

/// Tracks whether this launch came from the iPhone's "Send run plan" button, so the
/// watch can say the plan is on its way instead of showing the idle waiting screen.
@MainActor
final class WatchWorkoutLaunchCoordinator: ObservableObject {
    static let shared = WatchWorkoutLaunchCoordinator()

    @Published private(set) var wasLaunchedFromPhone = false

    private init() {}

    func handleLaunchFromPhone() {
        WatchConnectivityManager.shared.restoreLatestRunPlan()
        wasLaunchedFromPhone = !WatchConnectivityManager.shared.hasReceivedRunPlan
    }

    func clearLaunchFromPhone() {
        wasLaunchedFromPhone = false
    }
}
