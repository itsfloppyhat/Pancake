import CloudKit
import Combine
import Foundation
import UIKit
import UserNotifications

/// Friends ("Cheer Squad") on CloudKit — no accounts, no server.
///
/// Design:
/// - The runner owns a private custom zone shared with explicitly invited
///   iCloud participants. Forwarding a link does not grant access.
/// - `SquadInfo` and `RunStatus` live at fixed record names in that zone, so
///   both sides fetch them directly without needing queryable indexes.
/// - A shared-database subscription sends a content-free background push.
///   The supporter must successfully read the shared run status before the
///   app can display an alert. Revoking the share also revokes future alerts.
///   Background push delivery is best effort, not a real-time guarantee.
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
    @Published private(set) var ownShare: CKShare?
    @Published private(set) var sharingMigrationNotice: String?
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

    lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }
    private var publicDatabase: CKDatabase { container.publicCloudDatabase }

    private var ownZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: CheerSquadSchema.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var cheerPollTimer: Timer?
    private var currentRun: CheerRunBroadcast?
    private var runStartedAt: Date? { currentRun?.isRunning == true ? currentRun?.startedAt : nil }
    private var seenCheerRecordNames: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    private var runStatusTask: Task<Void, Never>?
    private var lastWrittenRun: CheerRunBroadcast?
    private var notifiedRunIDs: [String: String]
    private var isCheckingRunAlerts = false
    private var hasRegisteredSharedSubscription = false
    private var hasRemovedLegacySubscriptions = false
    private var currentAccountRecordName: String?
    private var legacySquadIDs: Set<String> = []

    private let settingsKey = "CheerSquadManager.settings"
    private let squadIDKey = "CheerSquadManager.squadID"
    private let currentRunKey = "CheerSquadManager.currentRun"
    private let notifiedRunsKey = "CheerSquadManager.notifiedRuns"
    private let privateInvitationsKey = "CheerSquadManager.needsPrivateInvitations"
    private static let sharedSubscriptionID = "cheer-shared-run-status-v2"
    private static let cheerPollInterval: TimeInterval = 20

    private static var isSimulatedRun: Bool {
        #if DEBUG
        let process = ProcessInfo.processInfo
        return process.arguments.contains("--pancake-simulated-run") ||
            process.environment["PANCAKE_SIMULATED_RUN"] == "1"
        #else
        return false
        #endif
    }

    private init() {
        settings = Self.loadSettings(key: settingsKey)
        notifiedRunIDs = UserDefaults.standard.dictionary(forKey: notifiedRunsKey) as? [String: String] ?? [:]
        if let data = UserDefaults.standard.data(forKey: currentRunKey) {
            currentRun = try? JSONDecoder().decode(CheerRunBroadcast.self, from: data)
        }
        if let legacyID = UserDefaults.standard.string(forKey: squadIDKey) {
            legacySquadIDs.insert(legacyID)
        }
        if UserDefaults.standard.bool(forKey: privateInvitationsKey) {
            sharingMigrationNotice = Self.privateInvitationsMessage
        }
    }

    private static let privateInvitationsMessage = "Your old anyone-with-link invitation has been retired. Invite your supporters again using Invite and manage supporters; only the iCloud accounts you choose can join."

    /// Retained in the private squad info for compatibility and legacy cleanup.
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
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        isBusy = true
        defer { isBusy = false }

        await refreshAccountStatus()
        guard availability == .available else {
            clearOwnShare()
            joinedSquads = []
            hasRegisteredSharedSubscription = false
            hasRemovedLegacySubscriptions = false
            return
        }

        await refreshOwnSquad()
        await refreshRunAlertAuthorization()
        _ = await refreshJoinedSquads()
        await registerRunAlertSubscription()
        reconcilePersistedRun()
        await removeLegacyPublicData()
    }

    private func refreshAccountStatus() async {
        // The unsigned simulator harness cannot initialize CKContainer. Keep
        // its synthetic runs local even when the simulator has an iCloud login.
        guard !Self.isSimulatedRun else {
            availability = .unavailable("Cheer Squad is unavailable during simulated runs.")
            return
        }
        do {
            switch try await container.accountStatus() {
            case .available:
                let accountName = try await container.userRecordID().recordName
                if currentAccountRecordName != accountName {
                    hasRegisteredSharedSubscription = false
                    hasRemovedLegacySubscriptions = false
                    lastWrittenRun = nil
                    currentAccountRecordName = accountName
                }
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
                // Saving .none removes legacy public participants. Do not
                // advertise an insecure share if this migration fails.
                applyOwnShare(try await ensurePrivateShare(share))
                let infoID = CKRecord.ID(recordName: CheerSquadSchema.squadInfoRecordName, zoneID: ownZoneID)
                if let info = try? await privateDatabase.record(for: infoID),
                   let legacyID = info[CheerSquadSchema.squadIDField] as? String {
                    legacySquadIDs.insert(legacyID)
                }
            }
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            clearOwnShare()
        } catch {
            clearOwnShare()
            recordError(error)
        }
    }

    private func applyOwnShare(_ share: CKShare) {
        isSharingEnabled = true
        ownShare = share
        squadMembers = share.participants.map { participant in
            SquadMember(
                id: participant.participantID.description,
                displayName: Self.displayName(for: participant),
                isOwner: participant.role == .owner,
                acceptanceStatus: participant.acceptanceStatus
            )
        }
    }

    private func clearOwnShare() {
        isSharingEnabled = false
        ownShare = nil
        squadMembers = []
        isBroadcastingRun = false
        stopCheerPolling()
    }

    private func ensurePrivateShare(_ share: CKShare) async throws -> CKShare {
        guard share.publicPermission != .none else { return share }
        share.publicPermission = .none
        guard let saved = try await privateDatabase.save(share) as? CKShare else {
            throw CKError(.internalError)
        }
        UserDefaults.standard.set(true, forKey: privateInvitationsKey)
        sharingMigrationNotice = Self.privateInvitationsMessage
        return saved
    }

    func sharingControllerDidSave() async {
        await refresh()
        if squadMembers.contains(where: { !$0.isOwner }) {
            UserDefaults.standard.set(false, forKey: privateInvitationsKey)
            sharingMigrationNotice = nil
        }
    }

    func sharingControllerDidStopSharing() async {
        clearOwnShare()
        lastWrittenRun = nil
        await refresh()
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

    @discardableResult
    private func refreshJoinedSquads() async -> Bool {
        do {
            let zones = try await sharedDatabase.allRecordZones()
            var squads: [JoinedSquad] = []

            for zone in zones where zone.zoneID.zoneName == CheerSquadSchema.zoneName {
                guard let squad = await loadJoinedSquad(from: zone.zoneID) else { continue }
                squads.append(squad)
            }

            joinedSquads = squads.sorted { $0.runnerName < $1.runnerName }
            return true
        } catch let error as CKError where error.code == .zoneNotFound {
            joinedSquads = []
            return true
        } catch {
            recordError(error)
            return false
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
            var runID: String?
            var alertsEnabled = false
            let statusID = CKRecord.ID(recordName: CheerSquadSchema.runStatusRecordName, zoneID: zoneID)
            if let status = try? await sharedDatabase.record(for: statusID) {
                isRunning = (status[CheerSquadSchema.statusField] as? String) == CheerSquadSchema.statusRunning
                startedAt = status[CheerSquadSchema.startedAtField] as? Date
                runID = status[CheerSquadSchema.runIDField] as? String
                alertsEnabled = (status[CheerSquadSchema.alertsEnabledField] as? NSNumber)?.boolValue ?? false
            }

            return JoinedSquad(
                id: "\(zoneID.ownerName)|\(zoneID.zoneName)",
                runnerName: runnerName,
                squadID: squadID,
                zoneID: zoneID,
                isRunningNow: isRunning,
                runStartedAt: startedAt,
                runID: runID,
                runAlertsEnabled: alertsEnabled
            )
        } catch {
            return nil
        }
    }

    // MARK: - Sharing (runner side)

    /// Creates the shared zone and invite link on first use.
    func enableSharing() async {
        await refreshAccountStatus()
        guard availability == .available else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let zone = CKRecordZone(zoneName: CheerSquadSchema.zoneName)
            _ = try await privateDatabase.save(zone)

            let infoID = CKRecord.ID(recordName: CheerSquadSchema.squadInfoRecordName, zoneID: ownZoneID)
            let info: CKRecord
            do {
                info = try await privateDatabase.record(for: infoID)
            } catch let error as CKError where error.code == .unknownItem {
                info = CKRecord(recordType: CheerSquadSchema.squadInfoRecordType, recordID: infoID)
            }
            // Preserve the existing ID so every old public record can be
            // removed even after an app reinstall generated a new local ID.
            let existingID = info[CheerSquadSchema.squadIDField] as? String
            if let existingID { legacySquadIDs.insert(existingID) }
            info[CheerSquadSchema.squadIDField] = existingID ?? squadID
            info[CheerSquadSchema.runnerNameField] = runnerDisplayName

            let share = try await ensurePrivateShare(existingOrNewZoneShare())
            share[CKShare.SystemFieldKey.title] = "\(runnerDisplayName)'s Cheer Squad" as CKRecordValue
            share.publicPermission = .none

            let results = try await privateDatabase.modifyRecords(saving: [info, share], deleting: [])
            for result in results.saveResults.values {
                if let savedShare = try result.get() as? CKShare {
                    applyOwnShare(savedShare)
                }
            }
            lastErrorMessage = nil
            reconcilePersistedRun()
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
            guard let fetchedShare = try await privateDatabase.record(for: shareRecordID) as? CKShare else { return }
            let share = try await ensurePrivateShare(fetchedShare)

            guard let participant = share.participants.first(where: {
                $0.participantID.description == member.id && $0.role != .owner
            }) else { return }

            share.removeParticipant(participant)
            if let saved = try await privateDatabase.save(share) as? CKShare {
                applyOwnShare(saved)
            }
            lastErrorMessage = nil
        } catch {
            recordError(error)
        }
    }

    // MARK: - Accepting invites (supporter side)

    func acceptShare(metadata: CKShare.Metadata) async {
        isBusy = true
        defer { isBusy = false }

        do {
            guard metadata.containerIdentifier == Self.containerIdentifier else { return }
            _ = try await container.accept(metadata)
            await refreshAccountStatus()
            _ = await refreshJoinedSquads()
            await refreshRunAlertAuthorization()
            await registerRunAlertSubscription()
            await removeLegacyPublicData()
            lastErrorMessage = nil
        } catch {
            recordError(error)
        }
    }

    /// Background pushes carry no runner information. A successful shared
    /// record read is required before showing a local run-start notification.
    func enableRunAlerts() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            runAlertsAuthorized = granted
            guard granted else { return }

            UIApplication.shared.registerForRemoteNotifications()
            await registerRunAlertSubscription()
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

    private func registerRunAlertSubscription() async {
        guard availability == .available, runAlertsAuthorized,
              !hasRegisteredSharedSubscription else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: Self.sharedSubscriptionID)
        subscription.recordType = CheerSquadSchema.runStatusRecordType
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            do {
                let existing = try await sharedDatabase.subscription(for: Self.sharedSubscriptionID)
                if let existing = existing as? CKDatabaseSubscription,
                   existing.recordType == CheerSquadSchema.runStatusRecordType,
                   existing.notificationInfo?.shouldSendContentAvailable == true {
                    hasRegisteredSharedSubscription = true
                    return
                }
            } catch let error as CKError where error.code == .unknownItem {
                // First run for this account; create the subscription below.
            }
            _ = try await sharedDatabase.save(subscription)
            hasRegisteredSharedSubscription = true
        } catch {
            recordError(error)
        }
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.containerIdentifier == Self.containerIdentifier,
              notification.subscriptionID == Self.sharedSubscriptionID,
              let databaseNotification = notification as? CKDatabaseNotification,
              databaseNotification.databaseScope == .shared else { return .noData }

        // Never turn cached joinedSquads or a public push payload into alerts.
        // A revoked membership must fail its fresh read before any alert exists.
        guard !isCheckingRunAlerts else { return .noData }
        isCheckingRunAlerts = true
        defer { isCheckingRunAlerts = false }
        await refreshAccountStatus()
        guard availability == .available else { return .failed }
        await refreshRunAlertAuthorization()
        guard runAlertsAuthorized else { return .noData }
        guard await refreshJoinedSquads() else { return .failed }

        var delivered = false
        for squad in joinedSquads {
            guard CheerRunAlertPolicy.shouldNotify(
                runID: squad.runID,
                startedAt: squad.runStartedAt,
                isRunning: squad.isRunningNow,
                alertsEnabled: squad.runAlertsEnabled,
                lastNotifiedRunID: notifiedRunIDs[squad.id]
            ), let runID = squad.runID else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(squad.runnerName) is out for a run"
            content.body = "Open Pancake to send a cheer they'll hear mid-run."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "cheer-run-\(squad.id)-\(runID)",
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                notifiedRunIDs[squad.id] = runID
                UserDefaults.standard.set(notifiedRunIDs, forKey: notifiedRunsKey)
                delivered = true
            } catch {
                recordError(error)
            }
        }
        return delivered ? .newData : .noData
    }

    // MARK: - Run broadcasting (runner side)

    /// Called by the workout coordinator when a run starts.
    func workoutDidStart(startedAt: Date = Date()) {
        #if DEBUG
        // Sandbox runs must never notify real squad members.
        if RunSandboxDriver.isSandboxRunActive || Self.isSimulatedRun { return }
        #endif

        if currentRun?.isRunning != true || currentRun?.startedAt != startedAt {
            currentRun = CheerRunBroadcast(
                id: UUID().uuidString,
                startedAt: startedAt,
                isRunning: true,
                alertsEnabled: settings.alertSquadOnRunStart
            )
        }
        persistCurrentRun()
        seenCheerRecordNames = []
        recentCheers = []
        enqueueRunStatus()
    }

    /// Called by the workout coordinator when the run ends.
    func workoutDidEnd() {
        guard !Self.isSimulatedRun else { return }
        stopCheerPolling()
        isBroadcastingRun = false
        guard var run = currentRun else { return }
        run.isRunning = false
        currentRun = run
        persistCurrentRun()
        enqueueRunStatus()
    }

    private func persistCurrentRun() {
        guard let currentRun, let data = try? JSONEncoder().encode(currentRun) else { return }
        UserDefaults.standard.set(data, forKey: currentRunKey)
    }

    private func reconcilePersistedRun() {
        guard let run = currentRun else { return }
        if run.isRunning {
            let snapshot = ActiveRunStateStore.shared.snapshot
            if snapshot == nil || snapshot.map({ RunEventRecoveryPolicy.isStale($0) }) == true {
                workoutDidEnd()
                return
            }
        }
        enqueueRunStatus()
    }

    /// Chain writes across actor suspension points. A delayed start can never
    /// overwrite an end or a newer run, and failed writes stay pending on disk.
    private func enqueueRunStatus() {
        guard let desiredRun = currentRun, desiredRun != lastWrittenRun else { return }
        let previous = runStatusTask
        runStatusTask = Task {
            await previous?.value
            guard currentRun == desiredRun, lastWrittenRun != desiredRun else { return }
            await refreshAccountStatus()
            guard availability == .available else { return }
            await refreshOwnSquad()
            guard isSharingEnabled, currentRun == desiredRun else { return }
            do {
                try await writeRunStatus(desiredRun)
                lastWrittenRun = desiredRun
                if currentRun == desiredRun, desiredRun.isRunning {
                    isBroadcastingRun = true
                    startCheerPolling()
                }
            } catch {
                recordError(error)
            }
        }
    }

    private func writeRunStatus(_ run: CheerRunBroadcast) async throws {
        let statusID = CKRecord.ID(recordName: CheerSquadSchema.runStatusRecordName, zoneID: ownZoneID)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: statusID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CheerSquadSchema.runStatusRecordType, recordID: statusID)
        }
        record[CheerSquadSchema.statusField] = run.isRunning ? CheerSquadSchema.statusRunning : CheerSquadSchema.statusEnded
        record[CheerSquadSchema.startedAtField] = run.startedAt
        record[CheerSquadSchema.runIDField] = run.id
        record[CheerSquadSchema.alertsEnabledField] = NSNumber(value: run.alertsEnabled)

        let results = try await privateDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        guard let result = results.saveResults[statusID] else { throw CKError(.internalError) }
        _ = try result.get()
    }

    // MARK: - Migration from public run announcements

    private func removeLegacyPublicData() async {
        // The info record can outlive its share and the app installation.
        let infoID = CKRecord.ID(recordName: CheerSquadSchema.squadInfoRecordName, zoneID: ownZoneID)
        if let info = try? await privateDatabase.record(for: infoID),
           let legacyID = info[CheerSquadSchema.squadIDField] as? String {
            legacySquadIDs.insert(legacyID)
        }
        if !hasRemovedLegacySubscriptions {
            do {
                let subscriptions = try await publicDatabase.allSubscriptions()
                for subscription in subscriptions where subscription.subscriptionID.hasPrefix("run-start-") {
                    _ = try await publicDatabase.deleteSubscription(withID: subscription.subscriptionID)
                }
                hasRemovedLegacySubscriptions = true
            } catch {
                // Retry next refresh. Current code never creates public alerts.
                print("Cheer Squad legacy subscription cleanup will retry.")
            }
        }

        for legacyID in legacySquadIDs {
            do {
                let query = CKQuery(
                    recordType: CheerSquadSchema.announcementRecordType,
                    predicate: NSPredicate(format: "%K == %@", CheerSquadSchema.announcementSquadIDField, legacyID)
                )
                var page = try await publicDatabase.records(matching: query, desiredKeys: [])
                var recordIDs: [CKRecord.ID] = []
                while true {
                    for (recordID, result) in page.matchResults {
                        _ = try result.get()
                        recordIDs.append(recordID)
                    }
                    guard let cursor = page.queryCursor else { break }
                    page = try await publicDatabase.records(continuingMatchFrom: cursor, desiredKeys: [])
                }
                // Finish pagination before deleting so changing the result set
                // does not invalidate traversal of the remaining old records.
                for recordID in recordIDs {
                    _ = try await publicDatabase.deleteRecord(withID: recordID)
                }
            } catch {
                // Old deployments may lack the record type/index. Keep the ID
                // and retry; never claim an unsuccessful cleanup was complete.
                print("Cheer Squad legacy announcement cleanup will retry.")
            }
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
