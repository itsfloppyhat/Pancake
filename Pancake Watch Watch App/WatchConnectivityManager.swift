import Foundation
import WatchConnectivity
import Combine

// MARK: - Message Types (shared with iOS app)
enum WatchMessageType: String, CaseIterable {
    // Run Planning
    case runPlan = "runPlan"
    case startRun = "startRun"
    
    // Workout Management
    case workoutStart = "workoutStart"
    case workoutStop = "workoutStop"
    case workoutUpdate = "workoutUpdate"
    case workoutCompleted = "workoutCompleted"
    case workoutStarted = "workoutStarted"
    
    // Music Control
    case requestMusicSuggestion = "requestMusicSuggestion"
    case playbackControl = "playbackControl"
    case currentSong = "currentSong"
    case musicSuggestion = "musicSuggestion"
    
    // Health Data
    case workoutHeartRate = "workoutHeartRate"
}

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var receivedRunPlan: [RunSegment] = []
    @Published var hasReceivedRunPlan = false
    @Published var lastError: Error?
    
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
        
        WCSession.default.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                print("Workout started message sent: \(response)")
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error
            }
        })
    }
    
    func sendWorkoutCompleted() {
        guard WCSession.isSupported() else { return }
        
        let message = ["type": WatchMessageType.workoutCompleted.rawValue] as [String : Any]
        
        WCSession.default.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                print("Workout completed message sent: \(response)")
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error
            }
        })
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
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let type = message["type"] as? String {
                switch type {
                case WatchMessageType.runPlan.rawValue:
                    if let segmentsData = message["segments"] as? Data {
                        do {
                            let segments = try JSONDecoder().decode([RunSegment].self, from: segmentsData)
                            self.receivedRunPlan = segments
                            self.hasReceivedRunPlan = true
                            print("Received run plan with \(segments.count) segments")
                        } catch {
                            self.lastError = error
                        }
                    }
                case WatchMessageType.startRun.rawValue:
                    // Handle start run request from iPhone
                    print("Received start run request from iPhone")
                case WatchMessageType.currentSong.rawValue:
                    // Handle current song update from iPhone
                    if let songData = message["song"] as? Data {
                        do {
                            let song = try JSONDecoder().decode(MusicSong.self, from: songData)
                            self.currentSong = song
                            print("Received current song: \(song.title) by \(song.artist)")
                        } catch {
                            print("Failed to decode current song: \(error)")
                        }
                    }
                case WatchMessageType.playbackControl.rawValue:
                    // Handle playback state update from iPhone
                    if let isPlaying = message["isPlaying"] as? Bool {
                        self.isPlaying = isPlaying
                        print("Received playback state: \(isPlaying ? "playing" : "paused")")
                    }
                    if let state = message["state"] as? String {
                        self.playbackState = state
                        print("Received playback state: \(state)")
                    }
                default:
                    break
                }
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        DispatchQueue.main.async {
            if let type = message["type"] as? String {
                switch type {
                case WatchMessageType.runPlan.rawValue:
                    if let segmentsData = message["segments"] as? Data {
                        do {
                            let segments = try JSONDecoder().decode([RunSegment].self, from: segmentsData)
                            self.receivedRunPlan = segments
                            self.hasReceivedRunPlan = true
                            print("Received run plan with \(segments.count) segments")
                            replyHandler(["status": "success"])
                        } catch {
                            self.lastError = error
                            replyHandler(["status": "error", "message": error.localizedDescription])
                        }
                    } else {
                        replyHandler(["status": "error", "message": "Invalid segments data"])
                    }
                case WatchMessageType.startRun.rawValue:
                    // Handle start run request from iPhone
                    print("Received start run request from iPhone")
                    replyHandler(["status": "success"])
                case WatchMessageType.currentSong.rawValue:
                    // Handle current song update from iPhone
                    if let songData = message["song"] as? Data {
                        do {
                            let song = try JSONDecoder().decode(MusicSong.self, from: songData)
                            self.currentSong = song
                            print("Received current song: \(song.title) by \(song.artist)")
                            replyHandler(["status": "success"])
                        } catch {
                            print("Failed to decode current song: \(error)")
                            replyHandler(["status": "error", "message": error.localizedDescription])
                        }
                    } else {
                        replyHandler(["status": "error", "message": "Invalid song data"])
                    }
                case WatchMessageType.playbackControl.rawValue:
                    // Handle playback state update from iPhone
                    if let isPlaying = message["isPlaying"] as? Bool {
                        self.isPlaying = isPlaying
                        print("Received playback state: \(isPlaying ? "playing" : "paused")")
                    }
                    if let state = message["state"] as? String {
                        self.playbackState = state
                        print("Received playback state: \(state)")
                    }
                    replyHandler(["status": "success"])
                default:
                    replyHandler(["status": "error", "message": "Unknown message type"])
                }
            } else {
                replyHandler(["status": "error", "message": "No message type"])
            }
        }
    }
}
