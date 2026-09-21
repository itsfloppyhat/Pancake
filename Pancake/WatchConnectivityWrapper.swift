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
    
    /// Store the plan durably before asking HealthKit to wake the Watch app.
    /// Activation is asynchronous at launch, so never silently drop the first send.
    @MainActor
    func sendRunPlan(_ segments: [RunSegment]) async throws {
        guard WCSession.isSupported() else { throw WatchConnectivityError.notSupported }
        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
            for _ in 0..<50 {
                if session.activationState == .activated { break }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        guard session.activationState == .activated else { throw WatchConnectivityError.sessionNotReady }
        guard session.isPaired else { throw WatchConnectivityError.watchNotPaired }
        guard session.isWatchAppInstalled else { throw WatchConnectivityError.watchAppNotInstalled }

        let message: [String: Any] = [
            "type": WatchMessageType.runPlan.rawValue,
            "segments": try JSONEncoder().encode(segments),
            "planID": UUID().uuidString,
            "sentAt": Date().timeIntervalSince1970
        ]
        try session.updateApplicationContext(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                // Reachability can change between the check and actual delivery.
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
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

        WCSession.default.sendMessage(message, replyHandler: { _ in
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error
            }
        })
    }
    
    func sendMessage(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        guard WCSession.isSupported() else {
            errorHandler(WatchConnectivityError.notSupported)
            return
        }

        guard WCSession.default.isPaired else {
            errorHandler(WatchConnectivityError.watchNotPaired)
            return
        }

        guard WCSession.default.isWatchAppInstalled else {
            errorHandler(WatchConnectivityError.watchAppNotInstalled)
            return
        }

        guard WCSession.default.isReachable else {
            errorHandler(WatchConnectivityError.watchNotReachable)
            return
        }

        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: errorHandler)
    }
    
    func sendMessageWithFallback(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        guard WCSession.isSupported() else {
            errorHandler(WatchConnectivityError.notSupported)
            return
        }

        guard WCSession.default.isPaired else {
            errorHandler(WatchConnectivityError.watchNotPaired)
            return
        }

        guard WCSession.default.isWatchAppInstalled else {
            errorHandler(WatchConnectivityError.watchAppNotInstalled)
            return
        }

        if WCSession.default.isReachable {
            // Try immediate message first
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: errorHandler)
        } else {
            // Fallback to transferUserInfo for unreachable watch
            WCSession.default.transferUserInfo(message)
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityWrapper: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("WatchConnectivity activation failed: \(error.localizedDescription)")
                self.lastError = error
            } else {
                self.isWatchPaired = session.isPaired
                self.isWatchAppInstalled = session.isWatchAppInstalled
                self.isWatchReachable = session.isReachable
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        DispatchQueue.main.async {
            self.isWatchReachable = false
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.handleWatchMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        let type = message["type"] as? String
        if message["runID"] != nil,
           type == "musicControl" || type == WatchMessageType.playbackControl.rawValue {
            Task { @MainActor in
                if let error = WorkoutMusicCoordinator.shared.handleIntervalMusicControl(message) {
                    replyHandler(["status": "rejected", "error": error])
                } else {
                    replyHandler(["status": "success"])
                }
            }
            return
        }
        DispatchQueue.main.async {
            self.handleWatchMessage(message)
            replyHandler(["status": "success"])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        DispatchQueue.main.async {
            self.handleWatchMessage(userInfo)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.handleWatchMessage(applicationContext)
        }
    }

    private func handleWatchMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else {
            return
        }

        switch type {
        case WatchMessageType.workoutCompleted.rawValue:
            NotificationCenter.default.post(name: .workoutControl, object: message)
        case WatchMessageType.workoutStarted.rawValue:
            NotificationCenter.default.post(name: .workoutControl, object: message)
        case WatchMessageType.workoutStart.rawValue:
            NotificationCenter.default.post(name: .workoutControl, object: message)
        case WatchMessageType.playbackControl.rawValue:
            NotificationCenter.default.post(name: .playbackControl, object: message)
        case "musicControl":
            NotificationCenter.default.post(name: .playbackControl, object: message)
        case "workoutControl":
            NotificationCenter.default.post(name: .workoutControl, object: message)
        case WatchMessageType.workoutUpdate.rawValue, "workout_update":
            NotificationCenter.default.post(name: .workoutUpdate, object: message)
        default:
            break
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
    
    private init() {}

    @MainActor
    func sendRunPlan(_ segments: [RunSegment]) async throws {
        throw WatchConnectivityError.notSupported
    }

    func requestStartRun() {
        lastError = WatchConnectivityError.notSupported
    }

    func sendMessage(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        errorHandler(WatchConnectivityError.notSupported)
    }

    func sendMessageWithFallback(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        errorHandler(WatchConnectivityError.notSupported)
    }
}
#endif
