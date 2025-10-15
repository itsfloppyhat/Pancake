import Foundation
import Combine

// MARK: - Notification Names
extension Notification.Name {
    static let requestMusicSuggestion = Notification.Name("requestMusicSuggestion")
    static let playbackControl = Notification.Name("playbackControl")
    static let workoutControl = Notification.Name("workoutControl")
    static let workoutHeartRate = Notification.Name("workoutHeartRate")
    static let segmentChanged = Notification.Name("segmentChanged")
}

// MARK: - Message Types
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

final class WatchConnectivityManager: ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var isWatchAppInstalled: Bool {
        didSet { wrapper.isWatchAppInstalled = isWatchAppInstalled }
    }
    @Published var isWatchReachable: Bool {
        didSet { wrapper.isWatchReachable = isWatchReachable }
    }
    @Published var isWatchPaired: Bool {
        didSet { wrapper.isWatchPaired = isWatchPaired }
    }
    @Published var lastError: Error? {
        didSet { wrapper.lastError = lastError }
    }
    
    private let wrapper = WatchConnectivityWrapper.shared
    
    private init() {
        // Initialize with wrapper values
        self.isWatchAppInstalled = wrapper.isWatchAppInstalled
        self.isWatchReachable = wrapper.isWatchReachable
        self.isWatchPaired = wrapper.isWatchPaired
        self.lastError = wrapper.lastError
        
        // Listen for changes from wrapper
        wrapper.$isWatchAppInstalled
            .assign(to: &$isWatchAppInstalled)
        wrapper.$isWatchReachable
            .assign(to: &$isWatchReachable)
        wrapper.$isWatchPaired
            .assign(to: &$isWatchPaired)
        wrapper.$lastError
            .assign(to: &$lastError)
    }
    
    func sendRunPlan(_ segments: [RunSegment]) {
        wrapper.sendRunPlan(segments)
    }
    
    func requestStartRun() {
        wrapper.requestStartRun()
    }
    
    func sendMessage(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        wrapper.sendMessage(message, errorHandler: errorHandler)
    }
    
    func sendMessageWithFallback(_ message: [String: Any], errorHandler: @escaping (Error) -> Void) {
        wrapper.sendMessageWithFallback(message, errorHandler: errorHandler)
    }
}

// MARK: - WatchConnectivity Errors
enum WatchConnectivityError: LocalizedError {
    case notSupported
    case watchNotPaired
    case watchAppNotInstalled
    case watchNotReachable
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Watch Connectivity is not supported on this device"
        case .watchNotPaired:
            return "Apple Watch is not paired with this iPhone"
        case .watchAppNotInstalled:
            return "Pancake app is not installed on your Apple Watch"
        case .watchNotReachable:
            return "Apple Watch is not reachable"
        case .encodingFailed:
            return "Failed to encode run plan data"
        }
    }
}
