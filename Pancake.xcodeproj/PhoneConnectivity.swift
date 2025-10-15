import Foundation
import WatchConnectivity
import Combine

final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private let session = WCSession.default

    @Published private(set) var isSupported: Bool
    @Published private(set) var isPaired: Bool = false
    @Published private(set) var isWatchAppInstalled: Bool = false
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var lastError: Error?

    override private init() {
        self.isSupported = WCSession.isSupported()
        super.init()
        activate()
    }

    private func activate() {
        guard isSupported else {
            print("[PhoneConnectivity] WCSession is not supported")
            return
        }
        session.delegate = self
        session.activate()
        print("[PhoneConnectivity] WCSession activation started")
    }

    func canStartRun() -> Bool {
        return isSupported &&
            activationState == .activated &&
            isPaired &&
            isWatchAppInstalled
    }

    func sendStartRun(planID: String?, segmentIndex: Int?) {
        let cmdKey = "cmd"
        let startRunValue = "startRun"

        var message: [String: Any] = [cmdKey: startRunValue]

        if let planID = planID {
            message["planID"] = planID
        }
        if let segmentIndex = segmentIndex {
            message["segmentIndex"] = segmentIndex
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                DispatchQueue.main.async {
                    self?.lastError = error
                }
                print("[PhoneConnectivity] sendMessage error: \(error.localizedDescription)")
            }
            print("[PhoneConnectivity] sendMessage sent: \(message)")
        } else {
            session.transferUserInfo(message)
            print("[PhoneConnectivity] session not reachable, used transferUserInfo with: \(message)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.activationState = activationState
            self?.lastError = error
            self?.isPaired = session.isPaired
            self?.isWatchAppInstalled = session.isWatchAppInstalled
            self?.isReachable = session.isReachable
        }
        print("[PhoneConnectivity] activationDidCompleteWithState: \(activationState.rawValue), error: \(String(describing: error))")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[PhoneConnectivity] sessionDidBecomeInactive")
        // no-op
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[PhoneConnectivity] sessionDidDeactivate, re-activating session")
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
        }
        print("[PhoneConnectivity] sessionReachabilityDidChange: \(session.isReachable)")
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaired = session.isPaired
            self?.isWatchAppInstalled = session.isWatchAppInstalled
        }
        print("[PhoneConnectivity] sessionWatchStateDidChange: isPaired=\(session.isPaired), isWatchAppInstalled=\(session.isWatchAppInstalled)")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("[PhoneConnectivity] didReceiveMessage: \(message)")
    }
}
