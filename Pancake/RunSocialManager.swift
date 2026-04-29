import AVFoundation
import Combine
import Foundation
import UserNotifications

@MainActor
final class RunSocialManager: ObservableObject {
    static let shared = RunSocialManager()

    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var activeFriends: [SocialRunner] = []
    @Published private(set) var recentComments: [SocialRunComment] = []
    @Published private(set) var isSharingCurrentRun = false
    @Published var settings: SocialRunSettings {
        didSet { saveSettings() }
    }
    @Published var lastError: Error?

    private let notificationCenter = UNUserNotificationCenter.current()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let settingsKey = "RunSocialManager.settings"

    private init() {
        settings = Self.loadSettings(key: settingsKey)
        activeFriends = Self.previewFriends()
        Task {
            await refreshNotificationAuthorization()
        }
    }

    var notificationsAuthorized: Bool {
        notificationAuthorizationStatus == .authorized || notificationAuthorizationStatus == .provisional
    }

    var isSocialReady: Bool {
        AuthManager.shared.isAuthenticated && notificationsAuthorized
    }

    func refreshNotificationAuthorization() async {
        let settings = await notificationCenter.notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
        self.settings.notificationsEnabled = notificationsAuthorized
    }

    func requestNotificationAuthorization() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshNotificationAuthorization()
            settings.notificationsEnabled = granted
        } catch {
            lastError = error
        }
    }

    func setAnnounceCommentsDuringRuns(_ enabled: Bool) {
        settings.announceCommentsDuringRuns = enabled
    }

    func setShareRunsWithFriends(_ enabled: Bool) {
        settings.shareRunsWithFriends = enabled
    }

    func startSharingRun() {
        guard settings.shareRunsWithFriends, AuthManager.shared.isAuthenticated else {
            isSharingCurrentRun = false
            return
        }

        isSharingCurrentRun = true
        // Real friend-run notifications require a backend/APNs registration.
    }

    func stopSharingRun() {
        isSharingCurrentRun = false
    }

    func sendComment(to runner: SocialRunner, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let comment = SocialRunComment(
            runnerID: runner.id,
            runnerName: runner.displayName,
            message: trimmed,
            direction: .outgoing
        )
        recentComments.insert(comment, at: 0)
        recentComments = Array(recentComments.prefix(20))
    }

    func receiveComment(from runner: SocialRunner, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let comment = SocialRunComment(
            runnerID: runner.id,
            runnerName: runner.displayName,
            message: trimmed,
            direction: .incoming
        )
        recentComments.insert(comment, at: 0)
        recentComments = Array(recentComments.prefix(20))

        if settings.announceCommentsDuringRuns {
            announce(comment)
        }
    }

    func previewFriendStartedRun() {
        guard let firstFriend = activeFriends.first else { return }
        scheduleLocalFriendRunNotification(for: firstFriend)
    }

    func previewIncomingComment() {
        guard let firstFriend = activeFriends.first else { return }
        receiveComment(from: firstFriend, message: "You are looking strong. Keep the rhythm.")
    }

    private func announce(_ comment: SocialRunComment) {
        guard !speechSynthesizer.isSpeaking else { return }

        let utterance = AVSpeechUtterance(string: "\(comment.runnerName) says: \(comment.message)")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    private func scheduleLocalFriendRunNotification(for friend: SocialRunner) {
        guard notificationsAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(friend.displayName) is out for a run"
        content.body = "Send a quick comment from Pancake."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "friend-run-\(friend.id.uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.lastError = error
            }
        }
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    private static func loadSettings(key: String) -> SocialRunSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(SocialRunSettings.self, from: data) else {
            return SocialRunSettings()
        }
        return settings
    }

    private static func previewFriends() -> [SocialRunner] {
        [
            SocialRunner(
                displayName: "Jamie",
                currentRunStartedAt: Date().addingTimeInterval(-960),
                lastKnownStatus: "Easy 5K"
            ),
            SocialRunner(
                displayName: "Riley",
                currentRunStartedAt: nil,
                lastKnownStatus: "Rest day"
            )
        ]
    }
}
