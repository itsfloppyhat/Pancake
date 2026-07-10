import CloudKit
import Combine
import Foundation
import UIKit
import UserNotifications

/// Friends ("Cheer Squad") on CloudKit — no accounts, no server.
///
/// Design:
/// - The runner owns a private custom zone shared zone-wide via one `CKShare`
///   invite link. Supporters who open the link join as participants.
/// - `SquadInfo` and `RunStatus` live at fixed record names in that zone, so
///   both sides fetch them directly without needing queryable indexes.
/// - On run start the runner also writes an ephemeral `RunAnnouncement` to the
///   public database (opaque squad UUID + display name only, deleted at run
///   end). Supporters hold a `CKQuerySubscription` on it, so the "gone for a
///   run" alert is a reliable system-displayed push with no background modes.
/// - Cheers are records supporters write into the shared zone; the runner
///   polls for them while the workout is active (the app is already alive for
///   music), so no silent-push plumbing is needed.
///
/// Every CloudKit call fails soft: until the iCloud container exists in the
/// developer portal, the feature reports itself unavailable and the rest of
/// the app is unaffected.
@MainActor
final class CheerSquadManager: ObservableObject {
    static let shared = CheerSquadManager()

    enum Availability: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case unavailable(String)

        var explanation: String? {
            switch self {
            case .unknown, .available:
                return nil
            case .noAccount:
                return "Sign in to iCloud in Settings to use Cheer Squad."
            case .restricted:
                return "iCloud access is restricted on this device."
            case .unavailable(let message):
                return message
            }
        }
    }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var isSharingEnabled = false
    @Published private(set) var shareURL: URL?
    @Published private(set) var squadMembers: [SquadMember] = []
    @Published private(set) var joinedSquads: [JoinedSquad] = []
    @Published private(set) var recentCheers: [RunCheer] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isBroadcastingRun = false
    @Published private(set) var runAlertsAuthorized = false
    @Published var settings: CheerSquadSettings {
        didSet { saveSettings() }
    }
    @Published var lastErrorMessage: String?

    static let containerIdentifier = "iCloud.com.Matthew-Lucas.Hello-World.Pancake"

    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }
    private var publicDatabase: CKDatabase { container.publicCloudDatabase }

    private var ownZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: CheerSquadSchema.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var cheerPollTimer: Timer?
    private var runStartedAt: Date?
    private var seenCheerRecordNames: Set<String> = []
    private var activeAnnouncementRecordID: CKRecord.ID?

    private let settingsKey = "CheerSquadManager.settings"
    private let squadIDKey = "CheerSquadManager.squadID"
    private static let cheerPollInterval: TimeInterval = 20

    private init() {
        settings = Self.loadSettings(key: settingsKey)
    }

    /// Opaque identifier used only for public run announcements.
    private var squadID: String {
        if let stored = UserDefaults.standard.string(forKey: squadIDKey) {
            return stored
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: squadIDKey)
        return fresh
    }

    private var runnerDisplayName: String {
        let name = UserProfileManager.shared.userProfile.personalInfo.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your friend" : name
    }

    // MARK: - Refresh

    func refresh() async {
        isBusy = true
        defer { isBusy = false }

        await refreshAccountStatus()
        guard availability == .available else { return }

        await refreshOwnSquad()
        await refreshJoinedSquads()
        await refreshRunAlertAuthorization()
    }

    private func refreshAccountStatus() async {
        do {
            switch try await container.accountStatus() {
            case .available:
                availability = .available
            case .noAccount:
                availability = .noAccount
            case .restricted, .temporarilyUnavailable:
                availability = .restricted
            case .couldNotDetermine:
                availability = .unavailable("iCloud status could not be determined. Try again later.")
            @unknown default:
                availability = .unavailable("iCloud is unavailable.")
            }
        } catch {
            availability = .unavailable(friendlyMessage(for: error))
        }
    }

    private func refreshOwnSquad() async {
        do {
            let shareRecordID = CKRecord.ID(
                recordName: CKRecordNameZoneWideShare,
                zoneID: ownZoneID
            )
            let record = try await privateDatabase.record(for: shareRecordID)

            if let share = record as? CKShare {
                applyOwnShare(share)
            }
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            isSharingEnabled = false
            shareURL = nil
            squadMembers = []
        } catch {
            recordError(error)
        }
    }

    private func applyOwnShare(_ share: CKShare) {
        isSharingEnabled = true
        shareURL = share.url
        squadMembers = share.participants.map { participant in
            SquadMember(
                id: participant.participantID.description,
                displayName: Self.displayName(for: participant),
                isOwner: participant.role == .owner,
                acceptanceStatus: participant.acceptanceStatus
            )
        }
    }

    private static func displayName(for participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty {
                return formatted
            }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress {
            return email
        }
        return participant.role == .owner ? "You" : "Squad member"
    }

    private func refreshJoinedSquads() async {
        do {
            let zones = try await sharedDatabase.allRecordZones()
            var squads: [JoinedSquad] = []

            for zone in zones where zone.zoneID.zoneName == CheerSquadSchema.zoneName {
                guard let squad = await loadJoinedSquad(from: zone.zoneID) else { continue }
                squads.append(squad)
            }

            joinedSquads = squads.sorted { $0.runnerName < $1.runnerName }
        } catch let error as CKError where error.code == .zoneNotFound {
            joinedSquads = []
        } catch {
            recordError(error)
        }
    }

    private func loadJoinedSquad(from zoneID: CKRecordZone.ID) async -> JoinedSquad? {
        do {
            let infoID = CKRecord.ID(recordName: CheerSquadSchema.squadInfoRecordName, zoneID: zoneID)
            let info = try await sharedDatabase.record(for: infoID)

            guard let squadID = info[CheerSquadSchema.squadIDField] as? String else { return nil }
            let runnerName = info[CheerSquadSchema.runnerNameField] as? String ?? "A runner"

            var isRunning = false
            var startedAt: Date?
            let statusID = CKRecord.ID(recordName: CheerSquadSchema.runStatusRecordName, zoneID: zoneID)
            if let status = try? await sharedDatabase.record(for: statusID) {
                isRunning = (status[CheerSquadSchema.statusField] as? String) == CheerSquadSchema.statusRunning
                startedAt = status[CheerSquadSchema.startedAtField] as? Date
            }

            return JoinedSquad(
                id: "\(zoneID.ownerName)|\(zoneID.zoneName)",
                runnerName: runnerName,
                squadID: squadID,
                zoneID: zoneID,
                isRunningNow: isRunning,
                runStartedAt: startedAt
            )
        } catch {
            return nil
        }
    }

    // MARK: - Sharing (runner side)

    /// Creates the shared zone and invite link on first use.
    func enableSharing() async {
        guard availability == .available else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let zone = CKRecordZone(zoneName: CheerSquadSchema.zoneName)
            _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])

            let infoID = CKRecord.ID(recordName: CheerSquadSchema.squadInfoRecordName, zoneID: ownZoneID)
            let info: CKRecord
            if let existing = try? await privateDatabase.record(for: infoID) {
                info = existing
            } else {
                info = CKRecord(recordType: CheerSquadSchema.squadInfoRecordType, recordID: infoID)
            }
            info[CheerSquadSchema.squadIDField] = squadID
            info[CheerSquadSchema.runnerNameField] = runnerDisplayName

            let share = try await existingOrNewZoneShare()
            share[CKShare.SystemFieldKey.title] = "\(runnerDisplayName)'s Cheer Squad" as CKRecordValue
            share.publicPermission = .readWrite

            let results = try await privateDatabase.modifyRecords(saving: [info, share], deleting: [])
            for (_, result) in results.saveResults {
                if case .success(let saved) = result, let savedShare = saved as? CKShare {
                    applyOwnShare(savedShare)
                }
            }
            lastErrorMessage = nil
        } catch {
            recordError(error)
        }
    }

    private func existingOrNewZoneShare() async throws -> CKShare {
        let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
        do {
            if let share = try await privateDatabase.record(for: shareRecordID) as? CKShare {
                return share
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No share yet — create one below.
        }
        return CKShare(recordZoneID: ownZoneID)
    }

    /// Blocking a member removes them from the share so they can no longer
    /// see run status or send cheers.
    func blockMember(_ member: SquadMember) async {
        guard availability == .available else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
            guard let share = try await privateDatabase.record(for: shareRecordID) as? CKShare else { return }

            guard let participant = share.participants.first(where: {
                $0.participantID.description == member.id && $0.role != .owner
            }) else { return }

            share.removeParticipant(participant)
            let results = try await privateDatabase.modifyRecords(saving: [share], deleting: [])
            for (_, result) in results.saveResults {
                if case .success(let saved) = result, let savedShare = saved as? CKShare {
                    applyOwnShare(savedShare)
                }
            }
        } catch {
            recordError(error)
        }
    }

    // MARK: - Accepting invites (supporter side)

    func acceptShare(metadata: CKShare.Metadata) async {
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await container.accept(metadata)
            await refreshJoinedSquads()
            await registerRunAlertSubscriptions()
            lastErrorMessage = nil
        } catch {
            recordError(error)
        }
    }

    /// Asks for notification permission and subscribes to run-start
    /// announcements for every joined squad. The push is displayed by the
    /// system, so no background modes are involved.
    func enableRunAlerts() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            runAlertsAuthorized = granted
            guard granted else { return }

            UIApplication.shared.registerForRemoteNotifications()
            await registerRunAlertSubscriptions()
        } catch {
            recordError(error)
        }
    }

    private func refreshRunAlertAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        runAlertsAuthorized = status == .authorized || status == .provisional
        if runAlertsAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func registerRunAlertSubscriptions() async {
        for squad in joinedSquads {
            let subscriptionID = "run-start-\(squad.squadID)"
            let predicate = NSPredicate(format: "%K == %@", CheerSquadSchema.announcementSquadIDField, squad.squadID)
            let subscription = CKQuerySubscription(
                recordType: CheerSquadSchema.announcementRecordType,
                predicate: predicate,
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation]
            )

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.title = "\(squad.runnerName) is out for a run"
            notificationInfo.alertBody = "Open Pancake to send a cheer they'll hear mid-run."
            notificationInfo.soundName = "default"
            subscription.notificationInfo = notificationInfo

            do {
                _ = try await publicDatabase.save(subscription)
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // Subscription already exists — fine.
            } catch {
                recordError(error)
            }
        }
    }

    // MARK: - Run broadcasting (runner side)

    /// Called by the workout coordinator when a run starts.
    func workoutDidStart() {
        #if DEBUG
        // Sandbox runs must never notify real squad members.
        if RunSandboxDriver.isSandboxRunActive { return }
        #endif

        runStartedAt = Date()
        seenCheerRecordNames = []
        recentCheers = []

        guard availability == .available, isSharingEnabled else { return }

        isBroadcastingRun = true
        startCheerPolling()

        Task {
            await writeRunStatus(CheerSquadSchema.statusRunning)
            if settings.alertSquadOnRunStart {
                await publishRunAnnouncement()
            }
        }
    }

    /// Called by the workout coordinator when the run ends.
    func workoutDidEnd() {
        stopCheerPolling()
        runStartedAt = nil

        guard isBroadcastingRun else { return }
        isBroadcastingRun = false

        Task {
            await writeRunStatus(CheerSquadSchema.statusEnded)
            await removeRunAnnouncement()
        }
    }

    private func writeRunStatus(_ status: String) async {
        do {
            let statusID = CKRecord.ID(recordName: CheerSquadSchema.runStatusRecordName, zoneID: ownZoneID)
            let record: CKRecord
            if let existing = try? await privateDatabase.record(for: statusID) {
                record = existing
            } else {
                record = CKRecord(recordType: CheerSquadSchema.runStatusRecordType, recordID: statusID)
            }
            record[CheerSquadSchema.statusField] = status
            record[CheerSquadSchema.startedAtField] = runStartedAt ?? Date()

            _ = try await privateDatabase.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys
            )
        } catch {
            recordError(error)
        }
    }

    private func publishRunAnnouncement() async {
        do {
            let record = CKRecord(recordType: CheerSquadSchema.announcementRecordType)
            record[CheerSquadSchema.announcementSquadIDField] = squadID
            record[CheerSquadSchema.announcementRunnerNameField] = runnerDisplayName

            let saved = try await publicDatabase.save(record)
            activeAnnouncementRecordID = saved.recordID
        } catch {
            recordError(error)
        }
    }

    private func removeRunAnnouncement() async {
        guard let recordID = activeAnnouncementRecordID else { return }
        activeAnnouncementRecordID = nil

        do {
            _ = try await publicDatabase.deleteRecord(withID: recordID)
        } catch {
            // Announcement cleanup is best effort; records are opaque.
        }
    }

    // MARK: - Cheer polling (runner side)

    private func startCheerPolling() {
        stopCheerPolling()
        cheerPollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.cheerPollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pollForCheers()
            }
        }
    }

    private func stopCheerPolling() {
        cheerPollTimer?.invalidate()
        cheerPollTimer = nil
    }

    private func pollForCheers() async {
        guard isBroadcastingRun, let runStartedAt else { return }

        do {
            let predicate = NSPredicate(format: "%K > %@", CheerSquadSchema.sentAtField, runStartedAt as NSDate)
            let query = CKQuery(recordType: CheerSquadSchema.cheerRecordType, predicate: predicate)
            let results = try await privateDatabase.records(
                matching: query,
                inZoneWith: ownZoneID,
                desiredKeys: nil,
                resultsLimit: 25
            )

            for (recordID, result) in results.matchResults {
                guard case .success(let record) = result,
                      seenCheerRecordNames.insert(recordID.recordName).inserted else {
                    continue
                }
                handleIncomingCheer(record)
            }
        } catch {
            // Poll errors are transient (offline mid-run); try again next tick.
        }
    }

    private func handleIncomingCheer(_ record: CKRecord) {
        guard let rawMessage = record[CheerSquadSchema.messageField] as? String,
              let message = CheerContentPolicy.sanitized(rawMessage) else {
            return
        }

        let senderName = record[CheerSquadSchema.senderNameField] as? String ?? "A supporter"
        let cheer = RunCheer(
            id: record.recordID.recordName,
            senderName: senderName,
            message: message,
            sentAt: record[CheerSquadSchema.sentAtField] as? Date ?? Date()
        )

        recentCheers.insert(cheer, at: 0)
        recentCheers = Array(recentCheers.prefix(20))

        if settings.announceCheersDuringRuns {
            CheerAnnouncer.shared.announceCheer(from: cheer.senderName, message: cheer.message)
        }

        sendCheerToWatch(cheer)
    }

    private func sendCheerToWatch(_ cheer: RunCheer) {
        let connectivity = WatchConnectivityManager.shared
        guard connectivity.isWatchPaired && connectivity.isWatchAppInstalled else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.cheer.rawValue,
            "id": cheer.id,
            "senderName": cheer.senderName,
            "message": cheer.message
        ]
        connectivity.sendMessageWithFallback(message) { error in
            print("Failed to send cheer to watch: \(error)")
        }
    }

    // MARK: - Sending cheers (supporter side)

    func sendCheer(to squad: JoinedSquad, message rawMessage: String) async -> Bool {
        guard availability == .available else { return false }
        guard let message = CheerContentPolicy.sanitized(rawMessage) else {
            lastErrorMessage = "That cheer can't be sent. Keep it short and friendly."
            return false
        }

        do {
            let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: squad.zoneID)
            let record = CKRecord(recordType: CheerSquadSchema.cheerRecordType, recordID: recordID)
            record[CheerSquadSchema.messageField] = message
            record[CheerSquadSchema.senderNameField] = runnerDisplayName
            record[CheerSquadSchema.sentAtField] = Date()

            _ = try await sharedDatabase.save(record)
            lastErrorMessage = nil
            return true
        } catch {
            recordError(error)
            return false
        }
    }

    // MARK: - Errors

    private func recordError(_ error: Error) {
        lastErrorMessage = friendlyMessage(for: error)
        print("CheerSquadManager error: \(error)")
    }

    private func friendlyMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        switch ckError.code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to use Cheer Squad."
        case .networkUnavailable, .networkFailure:
            return "No network connection. Try again when you're back online."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .badContainer, .missingEntitlement, .permissionFailure:
            return "Cheer Squad isn't available in this build yet."
        default:
            return ckError.localizedDescription
        }
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    private static func loadSettings(key: String) -> CheerSquadSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(CheerSquadSettings.self, from: data) else {
            return CheerSquadSettings()
        }
        return settings
    }
}
