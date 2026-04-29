import Foundation

struct SocialRunner: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var displayName: String
    var currentRunStartedAt: Date?
    var lastKnownStatus: String

    init(
        id: UUID = UUID(),
        displayName: String,
        currentRunStartedAt: Date? = nil,
        lastKnownStatus: String = "Not running"
    ) {
        self.id = id
        self.displayName = displayName
        self.currentRunStartedAt = currentRunStartedAt
        self.lastKnownStatus = lastKnownStatus
    }

    var isRunning: Bool {
        currentRunStartedAt != nil
    }
}

struct SocialRunComment: Identifiable, Codable, Equatable, Hashable {
    enum Direction: String, Codable {
        case incoming
        case outgoing
    }

    let id: UUID
    let runnerID: UUID
    let runnerName: String
    let message: String
    let sentAt: Date
    let direction: Direction

    init(
        id: UUID = UUID(),
        runnerID: UUID,
        runnerName: String,
        message: String,
        sentAt: Date = Date(),
        direction: Direction
    ) {
        self.id = id
        self.runnerID = runnerID
        self.runnerName = runnerName
        self.message = message
        self.sentAt = sentAt
        self.direction = direction
    }
}

struct SocialRunSettings: Codable, Equatable {
    var notificationsEnabled: Bool
    var announceCommentsDuringRuns: Bool
    var shareRunsWithFriends: Bool

    init(
        notificationsEnabled: Bool = false,
        announceCommentsDuringRuns: Bool = true,
        shareRunsWithFriends: Bool = false
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.announceCommentsDuringRuns = announceCommentsDuringRuns
        self.shareRunsWithFriends = shareRunsWithFriends
    }
}
