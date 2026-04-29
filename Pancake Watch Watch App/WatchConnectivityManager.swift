import Foundation
import WatchConnectivity
import Combine

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
        default:
            break
        }
    }
}
