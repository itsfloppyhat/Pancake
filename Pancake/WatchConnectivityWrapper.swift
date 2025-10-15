import Foundation
import Combine

#if canImport(WatchConnectivity)
import WatchConnectivity

// MARK: - WatchConnectivity Wrapper for iOS Simulator Compatibility
final class WatchConnectivityWrapper: NSObject, ObservableObject {
    static let shared = WatchConnectivityWrapper()
    
    @Published var isWatchAppInstalled = false
    @Published var isWatchReachable = false
    @Published var isWatchPaired = false
    @Published var lastError: Error?
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendRunPlan(_ segments: [RunSegment]) {
        guard WCSession.isSupported() else {
            lastError = WatchConnectivityError.notSupported
            return
        }
        
        guard WCSession.default.isPaired else {
            lastError = WatchConnectivityError.watchNotPaired
            return
        }
        
        guard WCSession.default.isWatchAppInstalled else {
            lastError = WatchConnectivityError.watchAppNotInstalled
            return
        }
        
        do {
            let segmentsData = try JSONEncoder().encode(segments)
            let message = [
                "type": WatchMessageType.runPlan.rawValue,
                "segments": segmentsData
            ] as [String : Any]
            
            // Use fallback method for run plans - critical messages that need to be delivered
            sendMessageWithFallback(message) { error in
                DispatchQueue.main.async {
                    self.lastError = error
                }
            }
        } catch {
            lastError = error
        }
    }
    
    func requestStartRun() {
        guard WCSession.isSupported() else {
            lastError = WatchConnectivityError.notSupported
            return
        }
        
        guard WCSession.default.isPaired else {
            lastError = WatchConnectivityError.watchNotPaired
            return
        }
        
        guard WCSession.default.isWatchAppInstalled else {
            lastError = WatchConnectivityError.watchAppNotInstalled
            return
        }
        
        let message = ["type": WatchMessageType.startRun.rawValue] as [String : Any]
        
        WCSession.default.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                print("Start run request sent: \(response)")
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error
            }
        })
    }
    
    func sendMessage(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        print("📤 Attempting to send message: \(message["type"] ?? "unknown")")
        
        guard WCSession.isSupported() else {
            print("❌ WatchConnectivity not supported")
            errorHandler(WatchConnectivityError.notSupported)
            return
        }
        
        guard WCSession.default.isPaired else {
            print("❌ Watch not paired")
            errorHandler(WatchConnectivityError.watchNotPaired)
            return
        }
        
        guard WCSession.default.isWatchAppInstalled else {
            print("❌ Watch app not installed")
            errorHandler(WatchConnectivityError.watchAppNotInstalled)
            return
        }
        
        guard WCSession.default.isReachable else {
            print("❌ Watch not reachable")
            errorHandler(WatchConnectivityError.watchNotReachable)
            return
        }
        
        print("✅ Sending message to Watch")
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: errorHandler)
    }
    
    func sendMessageWithFallback(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        print("📤 Attempting to send message with fallback: \(message["type"] ?? "unknown")")
        
        guard WCSession.isSupported() else {
            print("❌ WatchConnectivity not supported")
            errorHandler(WatchConnectivityError.notSupported)
            return
        }
        
        guard WCSession.default.isPaired else {
            print("❌ Watch not paired")
            errorHandler(WatchConnectivityError.watchNotPaired)
            return
        }
        
        guard WCSession.default.isWatchAppInstalled else {
            print("❌ Watch app not installed")
            errorHandler(WatchConnectivityError.watchAppNotInstalled)
            return
        }
        
        if WCSession.default.isReachable {
            // Try immediate message first
            print("✅ Watch reachable, sending immediate message")
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: errorHandler)
        } else {
            // Fallback to transferUserInfo for unreachable watch
            print("⚠️ Watch not reachable, using transferUserInfo fallback")
            WCSession.default.transferUserInfo(message)
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityWrapper: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ WatchConnectivity activation failed: \(error.localizedDescription)")
                self.lastError = error
            } else {
                print("✅ WatchConnectivity activated successfully")
                print("📱 Watch Status - Paired: \(session.isPaired), App Installed: \(session.isWatchAppInstalled), Reachable: \(session.isReachable)")
                self.isWatchPaired = session.isPaired
                self.isWatchAppInstalled = session.isWatchAppInstalled
                self.isWatchReachable = session.isReachable
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            print("⚠️ WatchConnectivity session became inactive")
            self.isWatchReachable = false
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            print("⚠️ WatchConnectivity session deactivated")
            self.isWatchReachable = false
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            print("📡 Watch reachability changed: \(session.isReachable)")
            self.isWatchReachable = session.isReachable
        }
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            print("📱 Watch state changed - Paired: \(session.isPaired), App Installed: \(session.isWatchAppInstalled), Reachable: \(session.isReachable)")
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            print("📨 Received message from Watch: \(message)")
            if let type = message["type"] as? String {
                switch type {
                case WatchMessageType.workoutCompleted.rawValue:
                    // Handle workout completion from watch
                    print("✅ Workout completed on watch")
                case WatchMessageType.workoutStarted.rawValue:
                    // Handle workout start confirmation from watch
                    print("✅ Workout started on watch")
                case WatchMessageType.requestMusicSuggestion.rawValue:
                    // Forward to WorkoutMusicCoordinator
                    print("🎵 Forwarding music suggestion request to WorkoutMusicCoordinator")
                    NotificationCenter.default.post(name: .requestMusicSuggestion, object: message)
                case WatchMessageType.playbackControl.rawValue:
                    // Forward to WorkoutMusicCoordinator
                    print("🎵 Forwarding playback control to WorkoutMusicCoordinator")
                    NotificationCenter.default.post(name: .playbackControl, object: message)
                case "musicControl":
                    // Handle music control from watch
                    print("🎵 Forwarding music control to WorkoutMusicCoordinator")
                    NotificationCenter.default.post(name: .playbackControl, object: message)
                case "workoutControl":
                    // Handle workout control from watch
                    print("🏃 Forwarding workout control to WorkoutMusicCoordinator")
                    NotificationCenter.default.post(name: .workoutControl, object: message)
                case WatchMessageType.workoutHeartRate.rawValue:
                    // Forward to WorkoutMusicCoordinator
                    print("❤️ Forwarding heart rate update to WorkoutMusicCoordinator")
                    NotificationCenter.default.post(name: .workoutHeartRate, object: message)
                case "segment_changed":
                    // Handle segment change from watch
                    print("🏃 Forwarding segment change to WorkoutMusicCoordinator")
                    NotificationCenter.default.post(name: .segmentChanged, object: message)
                default:
                    print("❓ Unknown message type received: \(type)")
                    break
                }
            } else {
                print("❌ Received message without type field")
            }
        }
    }
}

#else
// MARK: - Simulator Fallback
final class WatchConnectivityWrapper: ObservableObject {
    static let shared = WatchConnectivityWrapper()
    
    @Published var isWatchAppInstalled = false
    @Published var isWatchReachable = false
    @Published var isWatchPaired = false
    @Published var lastError: Error?
    
    private init() {
        print("⚠️ Running on iOS Simulator - WatchConnectivity not available")
    }
    
    func sendRunPlan(_ segments: [RunSegment]) {
        print("⚠️ WatchConnectivity not available on simulator")
        lastError = WatchConnectivityError.notSupported
    }
    
    func requestStartRun() {
        print("⚠️ WatchConnectivity not available on simulator")
        lastError = WatchConnectivityError.notSupported
    }
    
    func sendMessage(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        print("⚠️ WatchConnectivity not available on simulator")
        errorHandler(WatchConnectivityError.notSupported)
    }
    
    func sendMessageWithFallback(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        print("⚠️ WatchConnectivity not available on simulator")
        errorHandler(WatchConnectivityError.notSupported)
    }
}
#endif

