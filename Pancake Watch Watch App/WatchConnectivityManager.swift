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
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendWorkoutStarted() {
        guard WCSession.isSupported() else { return }
        
        let message = ["type": WatchMessageType.workoutStarted.rawValue] as [String : Any]

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
    
    func sendWorkoutCompleted(totalDistanceKm: Double = 0, totalTimeSeconds: Int = 0) {
        guard WCSession.isSupported() else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.workoutCompleted.rawValue,
            "totalDistanceKm": totalDistanceKm,
            "totalTimeSeconds": totalTimeSeconds
        ]

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
        receivedRunPlan = []
        hasReceivedRunPlan = false
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
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.lastError = error
            }
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
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
        guard let type = message["type"] as? String else {
            return
        }

        switch type {
        case WatchMessageType.runPlan.rawValue:
            if let segmentsData = message["segments"] as? Data {
                do {
                    let segments = try JSONDecoder().decode([RunSegment].self, from: segmentsData)
                    self.receivedRunPlan = segments
                    self.hasReceivedRunPlan = true
                } catch {
                    self.lastError = error
                }
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
