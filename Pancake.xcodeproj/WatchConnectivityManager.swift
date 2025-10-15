import Foundation
import WatchConnectivity
import Combine

final class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    private let session = WCSession.default
    
    @Published var lastCommand: String?
    @Published var lastPayload: [String: Any]?
    
    override private init() {
        super.init()
        activate()
    }
    
    private func activate() {
        guard WCSession.isSupported() else {
            print("WCSession is not supported on this device")
            return
        }
        session.delegate = self
        session.activate()
        print("WCSession activated")
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WCSession activationDidCompleteWith state: \(activationState.rawValue), error: \(String(describing: error))")
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession reachabilityDidChange: \(session.isReachable)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("WCSession didReceiveMessage: \(message)")
        guard let cmd = message["cmd"] as? String, cmd == "startRun" else {
            print("Unknown or missing command in message")
            return
        }
        DispatchQueue.main.async {
            self.lastCommand = cmd
            self.lastPayload = message
        }
        let planID = message["planID"] as? String
        let segmentIndex = message["segmentIndex"] as? Int
        startRunOnWatch(planID: planID, segmentIndex: segmentIndex)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("WCSession didReceiveUserInfo: \(userInfo)")
        guard let cmd = userInfo["cmd"] as? String, cmd == "startRun" else {
            print("Unknown or missing command in userInfo")
            return
        }
        DispatchQueue.main.async {
            self.lastCommand = cmd
            self.lastPayload = userInfo
        }
        let planID = userInfo["planID"] as? String
        let segmentIndex = userInfo["segmentIndex"] as? Int
        startRunOnWatch(planID: planID, segmentIndex: segmentIndex)
    }
    
    // MARK: - Public
    
    public func startRunOnWatch(planID: String?, segmentIndex: Int?) {
        print("Starting run on watch with planID: \(planID ?? "nil"), segmentIndex: \(segmentIndex?.description ?? "nil")")
        // Developer can hook their run logic here
    }
}
