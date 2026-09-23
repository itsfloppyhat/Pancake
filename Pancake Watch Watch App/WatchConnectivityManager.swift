import Foundation
import WatchConnectivity
import Combine

/// A cheer forwarded from the iPhone during a run.
struct ReceivedCheer: Identifiable, Equatable {
    let id: String
    let senderName: String
    let message: String
    let receivedAt: Date
}

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var receivedRunPlan: [RunSegment] = []
    @Published var hasReceivedRunPlan = false
    @Published var lastError: Error?
    
    // iPhone connectivity
    @Published var isReachable: Bool = false

    // Music state from iPhone
    @Published var currentSong: MusicSong?
    @Published var isPlaying: Bool = false
    @Published var playbackState: String = "stopped"
    @Published var isAdaptiveMixActive = false
    @Published var isAdaptiveMixCurating = false
    @Published var adaptiveMixQueuedSongCount = 0
    @Published var adaptiveMixPlayedSongCount = 0
    @Published var adaptiveMixStatus = "Adaptive Mix is off"
    @Published var adaptiveMixRevision = 0
    @Published var adaptiveMixTargetZone: String?
    @Published var adaptiveMixAlignmentScore: Int?
    @Published var adaptiveMixReplacedSongCount = 0
    @Published var adaptiveMixGuidanceText: String?
    @Published var adaptiveMixNextSongTitle: String?
    @Published var adaptiveMixNextSongArtist: String?
    @Published var lastCheer: ReceivedCheer?
    
    /// Plans older than this are treated as leftovers from a previous session.
    private static let runPlanExpiry: TimeInterval = 6 * 60 * 60
    private static let pendingPlanKey = "WatchConnectivityManager.pendingPlan"
    private static let latestPlanDateKey = "WatchConnectivityManager.latestPlanDate"
    private var pendingPlan: PendingWatchRunPlan?

    private var lastHandledRunPlanID: String? {
        get { UserDefaults.standard.string(forKey: "WatchConnectivityManager.lastHandledRunPlanID") }
        set { UserDefaults.standard.set(newValue, forKey: "WatchConnectivityManager.lastHandledRunPlanID") }
    }

    private override init() {
        super.init()
        restorePendingRunPlan()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendWorkoutStarted(runID: UUID, startedAt: Date, segments: [RunSegment], startAdaptiveMix: Bool = false) {
        guard WCSession.isSupported() else { return }
        
        var message: [String: Any] = [
            "type": WatchMessageType.workoutStarted.rawValue,
            "runID": runID.uuidString,
            "startedAt": startedAt.timeIntervalSince1970,
            "startAdaptiveMix": startAdaptiveMix
        ]
        message["segments"] = try? JSONEncoder().encode(segments)

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { _ in
                DispatchQueue.main.async { }
            }, errorHandler: { [weak self] error in
                WCSession.default.transferUserInfo(message)
                DispatchQueue.main.async {
                    self?.lastError = error
                }
            })
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }
    
    func sendWorkoutCompleted(
        runID: UUID,
        startedAt: Date,
        endedAt: Date,
        segments: [RunSegment],
        totalDistanceKm: Double,
        totalTimeSeconds: Int,
        interruptionReason: String? = nil
    ) {
        guard WCSession.isSupported() else { return }

        var message: [String: Any] = [
            "type": WatchMessageType.workoutCompleted.rawValue,
            "runID": runID.uuidString,
            "startedAt": startedAt.timeIntervalSince1970,
            "endedAt": endedAt.timeIntervalSince1970,
            "totalDistanceKm": totalDistanceKm,
            "totalTimeSeconds": totalTimeSeconds
        ]
        message["segments"] = try? JSONEncoder().encode(segments)
        message["interruptionReason"] = interruptionReason

        // Use sendMessage for immediate delivery, with transferUserInfo fallback
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { response in
                DispatchQueue.main.async { }
            }, errorHandler: { [weak self] error in
                // If sendMessage fails, use transferUserInfo so it arrives eventually
                WCSession.default.transferUserInfo(message)
                DispatchQueue.main.async {
                    self?.lastError = error
                }
            })
        } else {
            // Watch not reachable — use transferUserInfo for background delivery
            WCSession.default.transferUserInfo(message)
        }
    }
    
    func clearReceivedRunPlan() {
        if let pendingPlan {
            lastHandledRunPlanID = pendingPlan.id
        }
        pendingPlan = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingPlanKey)
        receivedRunPlan = []
        hasReceivedRunPlan = false
    }

    private func restorePendingRunPlan() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingPlanKey),
              let plan = try? JSONDecoder().decode(PendingWatchRunPlan.self, from: data),
              plan.isUsable(at: Date(), expiry: Self.runPlanExpiry) else {
            UserDefaults.standard.removeObject(forKey: Self.pendingPlanKey)
            return
        }
        pendingPlan = plan
        receivedRunPlan = plan.segments
        hasReceivedRunPlan = true
    }

    /// A context may already have been delivered before SwiftUI or the workout
    /// launch callback creates the manager, so explicitly inspect it on activation.
    func restoreLatestRunPlan() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let context = WCSession.default.receivedApplicationContext
        handleIncomingMessage(context)
    }

    /// The same plan arrives more than once by design: as a message, and again as the
    /// application context every time the watch app launches. Accept each plan once,
    /// and ignore a stale context so a dismissed plan doesn't come back tomorrow.
    private func shouldAcceptRunPlan(_ message: [String: Any]) -> Bool {
        if let planID = message["planID"] as? String {
            guard planID != lastHandledRunPlanID else { return false }
        }

        if let sentAt = message["sentAt"] as? TimeInterval {
            let age = Date().timeIntervalSince1970 - sentAt
            guard age < Self.runPlanExpiry else { return false }
            guard sentAt >= UserDefaults.standard.double(forKey: Self.latestPlanDateKey) else { return false }
        }

        return true
    }

    func sendMusicControl(_ action: String) {
        guard WCSession.isSupported() else { return }

        let message: [String: Any] = [
            "type": "musicControl",
            "action": action
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { [weak self] error in
                WCSession.default.transferUserInfo(message)
                DispatchQueue.main.async {
                    self?.lastError = error
                }
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    /// Interval controls are immediate intentions; never queue them for a later
    /// interval or a different workout when the phone is disconnected.
    func sendIntervalMusicControl(_ action: String, interval: IntervalChangePrompt, completion: @escaping (Error?) -> Void) {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            completion(NSError(domain: "Pancake.WatchMusic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open Pancake on iPhone to change music."]))
            return
        }
        let message: [String: Any] = [
            "type": "musicControl",
            "action": action,
            "runID": interval.runID.uuidString,
            "segmentIndex": interval.segmentIndex,
            "sentAt": Date().timeIntervalSince1970
        ]
        WCSession.default.sendMessage(message, replyHandler: { reply in
            let error: Error?
            if reply["status"] as? String == "success" {
                error = nil
            } else {
                error = NSError(domain: "Pancake.WatchMusic", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: reply["error"] as? String ?? "iPhone couldn't apply this music control. Please try again."
                ])
            }
            DispatchQueue.main.async { completion(error) }
        }, errorHandler: { error in
            DispatchQueue.main.async { completion(error) }
        })
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.lastError = error
            }
            self.isReachable = session.isReachable
            if activationState == .activated {
                self.restoreLatestRunPlan()
                WatchRunRouteTransfer.retryPending()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            WatchRunRouteTransfer.retryPending()
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        WatchRunRouteTransfer.finished(fileTransfer, error: error)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(userInfo)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(applicationContext)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(message)
            replyHandler(["status": "success"])
        }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        if let rawUnit = message[DistanceUnit.preferenceKey] as? String,
           let unit = DistanceUnit(rawValue: rawUnit) {
            UserDefaults.standard.set(unit.rawValue, forKey: DistanceUnit.preferenceKey)
        }
        guard let type = message["type"] as? String else {
            return
        }

        switch type {
        case "runRouteReceived":
            if let rawID = message["runID"] as? String, let runID = UUID(uuidString: rawID) {
                WatchRunRouteTransfer.acknowledge(runID: runID)
            }
        case WatchMessageType.runPlan.rawValue:
            guard let segmentsData = message["segments"] as? Data else { break }
            guard shouldAcceptRunPlan(message) else { break }

            do {
                let segments = try JSONDecoder().decode([RunSegment].self, from: segmentsData)
                guard !segments.isEmpty else { break }
                let plan = PendingWatchRunPlan(
                    id: message["planID"] as? String ?? UUID().uuidString,
                    sentAt: Date(timeIntervalSince1970: message["sentAt"] as? TimeInterval ?? Date().timeIntervalSince1970),
                    segments: segments
                )
                let data = try JSONEncoder().encode(plan)
                UserDefaults.standard.set(data, forKey: Self.pendingPlanKey)
                UserDefaults.standard.set(plan.sentAt.timeIntervalSince1970, forKey: Self.latestPlanDateKey)
                self.pendingPlan = plan
                self.receivedRunPlan = segments
                self.hasReceivedRunPlan = true
            } catch {
                self.lastError = error
            }
        case WatchMessageType.startRun.rawValue:
            break
        case WatchMessageType.currentSong.rawValue:
            if let hasSong = message["hasSong"] as? Bool, !hasSong {
                self.currentSong = nil
                return
            }
            if let songData = message["song"] as? Data {
                do {
                    let song = try JSONDecoder().decode(MusicSong.self, from: songData)
                    self.currentSong = song
                } catch {
                    print("Failed to decode current song: \(error)")
                }
            }
        case WatchMessageType.playbackControl.rawValue:
            if let isPlaying = message["isPlaying"] as? Bool {
                self.isPlaying = isPlaying
            }
            if let state = message["state"] as? String {
                self.playbackState = state
            }
        case WatchMessageType.adaptiveMixState.rawValue:
            self.isAdaptiveMixActive = message["isActive"] as? Bool ?? false
            self.isAdaptiveMixCurating = message["isCurating"] as? Bool ?? false
            self.adaptiveMixQueuedSongCount = message["queuedSongCount"] as? Int ?? 0
            self.adaptiveMixPlayedSongCount = message["playedSongCount"] as? Int ?? 0
            self.adaptiveMixStatus = message["status"] as? String ?? "Adaptive Mix is off"
            self.adaptiveMixRevision = message["revision"] as? Int ?? self.adaptiveMixRevision
            self.adaptiveMixTargetZone = message["targetZone"] as? String
            self.adaptiveMixAlignmentScore = message["alignmentScore"] as? Int
            self.adaptiveMixReplacedSongCount = message["replacedSongCount"] as? Int ?? 0
            self.adaptiveMixGuidanceText = message["guidanceText"] as? String
            self.adaptiveMixNextSongTitle = message["nextSongTitle"] as? String
            self.adaptiveMixNextSongArtist = message["nextSongArtist"] as? String
        case WatchMessageType.cheer.rawValue:
            if let sender = message["senderName"] as? String,
               let text = message["message"] as? String {
                self.lastCheer = ReceivedCheer(
                    id: message["id"] as? String ?? UUID().uuidString,
                    senderName: sender,
                    message: text,
                    receivedAt: Date()
                )
            }
        default:
            break
        }
    }
}
