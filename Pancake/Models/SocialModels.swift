import Foundation
import CloudKit

// MARK: - Cheer Squad Settings

struct CheerSquadSettings: Codable, Equatable {
    var alertSquadOnRunStart = true
    var announceCheersDuringRuns = true
}

// MARK: - Squad Models

/// A person who accepted this runner's invite and can send cheers.
struct SquadMember: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isOwner: Bool
    let acceptanceStatus: CKShare.ParticipantAcceptanceStatus
}

/// A squad this user joined as a supporter (someone else's run feed).
struct JoinedSquad: Identifiable, Equatable {
    let id: String
    let runnerName: String
    let squadID: String
    let zoneID: CKRecordZone.ID
    var isRunningNow: Bool
    var runStartedAt: Date?
}

/// A cheer message received during (or after) a run.
struct RunCheer: Identifiable, Equatable {
    let id: String
    let senderName: String
    let message: String
    let sentAt: Date
}

// MARK: - CloudKit Schema

/// Record and zone names for the Cheer Squad CloudKit schema.
/// `SquadInfo` and `RunStatus` use fixed record names so both sides can fetch
/// them directly without queryable indexes; cheers are queried by `sentAt`.
enum CheerSquadSchema {
    static let zoneName = "CheerSquad"

    static let squadInfoRecordType = "SquadInfo"
    static let squadInfoRecordName = "squad-info"
    static let squadIDField = "squadID"
    static let runnerNameField = "runnerName"

    static let runStatusRecordType = "RunStatus"
    static let runStatusRecordName = "run-status"
    static let statusField = "status"
    static let startedAtField = "startedAt"
    static let statusRunning = "running"
    static let statusEnded = "ended"

    static let cheerRecordType = "RunCheer"
    static let messageField = "message"
    static let senderNameField = "senderName"
    static let sentAtField = "sentAt"

    /// Public-database record announcing a run start. Contains only an opaque
    /// squad UUID and a display name; deleted when the run ends.
    static let announcementRecordType = "RunAnnouncement"
    static let announcementSquadIDField = "squadID"
    static let announcementRunnerNameField = "runnerName"
}

// MARK: - Cheer Content Policy

/// Preset cheers plus a lightweight filter applied to free-text cheers on both
/// send and receive. App Review treats cheers as user-generated content, so
/// filtering, blocking, and reporting must all exist.
enum CheerContentPolicy {
    static let maximumLength = 120

    static let presetCheers = [
        "You've got this!",
        "Looking strong!",
        "Keep the rhythm!",
        "Almost there — push through!",
        "Great pace, keep it up!",
        "Run happy!"
    ]

    private static let blockedTerms: [String] = [
        "fuck", "shit", "bitch", "asshole", "cunt", "dick", "bastard",
        "nigger", "faggot", "retard", "whore", "slut", "kys", "kill yourself"
    ]

    /// Returns a cleaned message, or nil when the message is empty or blocked.
    static func sanitized(_ raw: String) -> String? {
        var message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }

        if message.count > maximumLength {
            message = String(message.prefix(maximumLength))
        }

        let comparison = message.lowercased()
        for term in blockedTerms where comparison.contains(term) {
            return nil
        }

        return message
    }
}
