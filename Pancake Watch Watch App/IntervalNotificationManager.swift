import Foundation
import Combine
import UserNotifications
import WatchKit

/// Interval changes invite a music choice; they never change playback themselves.
@MainActor
final class IntervalNotificationManager: NSObject, ObservableObject {
    static let shared = IntervalNotificationManager()

    @Published var currentInterval: IntervalChangePrompt?
    @Published private(set) var musicControlError: String?
    @Published private(set) var isSendingControl = false

    private let center = UNUserNotificationCenter.current()
    private static let categoryID = "Pancake.intervalChanged"
    private static let nextActionID = "Pancake.interval.next"
    private static let playActionID = "Pancake.interval.play"
    private static let pauseActionID = "Pancake.interval.pause"
    private var notificationID: String?
    private var notificationRunID: UUID?
    private var pendingControlID: UUID?
    private var dismissTask: Task<Void, Never>?

    private override init() {
        super.init()
        register()
    }

    func register() {
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Self.nextActionID, title: "Next Song", options: [.foreground]),
            UNNotificationAction(identifier: Self.playActionID, title: "Play Music", options: [.foreground]),
            UNNotificationAction(identifier: Self.pauseActionID, title: "Pause Music", options: [.foreground])
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: [], options: [])
        ])
    }

    func requestAuthorizationForRun() {
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor in
                do {
                    _ = try await self?.center.requestAuthorization(options: [.alert, .sound])
                } catch {
                    print("Interval notification permission failed: \(error)")
                }
            }
        }
    }

    func present(_ interval: IntervalChangePrompt) {
        guard isCurrent(interval) else { return }
        clearInterval()
        currentInterval = interval
        scheduleDismissal(for: interval)

        // SwiftUI presents the controls immediately while the app is visible.
        // Away from the app, the system alert exposes the same explicit choices.
        guard WKApplication.shared().applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(interval.intensity.label) starts now"
        content.body = "\(interval.targetDescription). Keep your music or choose Next Song."
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        content.userInfo = [
            "runID": interval.runID.uuidString,
            "segmentIndex": interval.segmentIndex
        ]
        let identifier = "Pancake.interval.\(interval.id)"
        notificationID = identifier
        notificationRunID = interval.runID
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error { print("Could not deliver interval notification: \(error)") }
        }
    }

    func clearInterval(for runID: UUID? = nil) {
        if let runID,
           currentInterval?.runID != runID,
           notificationRunID != runID { return }
        currentInterval = nil
        dismissTask?.cancel()
        dismissTask = nil
        musicControlError = nil
        isSendingControl = false
        pendingControlID = nil
        removeNotification()
    }

    func sendMusicControl(_ action: String, for interval: IntervalChangePrompt) {
        guard isCurrent(interval), !isSendingControl else { return }
        musicControlError = nil
        isSendingControl = true
        let controlID = UUID()
        pendingControlID = controlID
        WatchConnectivityManager.shared.sendIntervalMusicControl(action, interval: interval) { [weak self] error in
            Task { @MainActor in
                guard let self, self.pendingControlID == controlID else { return }
                self.pendingControlID = nil
                self.isSendingControl = false
                guard self.isCurrent(interval) else {
                    self.clearInterval(for: interval.runID)
                    return
                }
                if let error {
                    self.musicControlError = error.localizedDescription
                    self.currentInterval = interval
                } else {
                    self.clearInterval(for: interval.runID)
                }
            }
        }
    }

    func nextSong(for interval: IntervalChangePrompt) {
        sendMusicControl(WatchConnectivityManager.shared.isAdaptiveMixActive ? "next" : "suggest", for: interval)
    }

    private func scheduleDismissal(for interval: IntervalChangePrompt) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(WorkoutAlertTiming.displayDuration))
            } catch { return }
            guard let self, self.currentInterval?.id == interval.id else { return }
            self.clearInterval(for: interval.runID)
        }
    }

    private func isCurrent(_ interval: IntervalChangePrompt) -> Bool {
        let workout = WorkoutSessionManager.shared
        return interval.isCurrent(runID: workout.activeRunID, segmentIndex: workout.currentSegmentIndex, isRunning: workout.isRunning)
    }

    private func removeNotification() {
        if let notificationID {
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        }
        notificationID = nil
        notificationRunID = nil
    }

    private func handleResponse(_ response: UNNotificationResponse) {
        guard response.notification.request.content.categoryIdentifier == Self.categoryID else { return }
        let info = response.notification.request.content.userInfo
        let workout = WorkoutSessionManager.shared
        guard let rawID = info["runID"] as? String,
              let runID = UUID(uuidString: rawID),
              let index = info["segmentIndex"] as? Int,
              let segment = workout.currentSegment else { return }
        let interval = IntervalChangePrompt(runID: runID, segmentIndex: index, intensity: segment.intensity, target: segment.target)
        guard isCurrent(interval) else {
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
            return
        }
        currentInterval = interval
        scheduleDismissal(for: interval)
        switch response.actionIdentifier {
        case Self.nextActionID: nextSong(for: interval)
        case Self.playActionID: sendMusicControl("play", for: interval)
        case Self.pauseActionID: sendMusicControl("pause", for: interval)
        case UNNotificationDismissActionIdentifier: clearInterval(for: runID)
        default: break // Opening the notification shows the choices without changing music.
        }
    }
}

extension IntervalNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The foreground sheet already contains the interval and music controls.
        completionHandler([])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            handleResponse(response)
            completionHandler()
        }
    }
}
