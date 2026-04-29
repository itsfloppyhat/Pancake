import Foundation
import Combine

// MARK: - Run Setup ViewModel
@MainActor
final class RunSetupViewModel: ObservableObject {
    @Published var showingWatchAlert: Bool = false
    @Published var watchAlertMessage: String = ""
    @Published var isStartingRun: Bool = false
    @Published var error: Error?
    
    // Dependencies
    @Published private var runPlanViewModel = RunPlanViewModel()
    private let watchConnectivity = WatchConnectivityManager.shared
    private let musicCoordinator = WorkoutMusicCoordinator.shared
    private let musicManager = MusicPlaybackManager.shared
    private let onboarding = OnboardingManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        watchConnectivity.$lastError
            .assign(to: &$error)
        
        // Forward changes from runPlanViewModel to trigger UI updates
        runPlanViewModel.$segments
            .sink { [weak self] _ in
                // This will trigger UI updates when segments change
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        onboarding.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Run Plan Access
    var segments: [RunSegment] {
        runPlanViewModel.segments
    }
    
    var totalTimeSeconds: Int {
        runPlanViewModel.totalTimeSeconds
    }
    
    var totalDistanceMeters: Int {
        runPlanViewModel.totalDistanceMeters
    }
    
    var hasSegments: Bool {
        runPlanViewModel.hasSegments
    }
    
    // MARK: - Watch Connectivity
    var isWatchPaired: Bool {
        watchConnectivity.isWatchPaired
    }
    
    var isWatchAppInstalled: Bool {
        watchConnectivity.isWatchAppInstalled
    }
    
    var canStartRun: Bool {
        hasSegments && isWatchPaired && isWatchAppInstalled && onboarding.requiredRunSetupComplete && !isStartingRun
    }
    
    // MARK: - Music Coordinator
    var isWorkoutActive: Bool {
        musicCoordinator.isWorkoutActive
    }
    
    // MARK: - Actions
    func addSegment(_ segment: RunSegment) {
        runPlanViewModel.addSegment(segment)
    }
    
    func removeSegments(at offsets: IndexSet) {
        runPlanViewModel.removeSegments(at: offsets)
    }
    
    func moveSegments(from source: IndexSet, to destination: Int) {
        runPlanViewModel.moveSegments(from: source, to: destination)
    }
    
    func clearAllSegments() {
        runPlanViewModel.clearAllSegments()
    }
    
    func addIntervalTemplate() {
        runPlanViewModel.addIntervalTemplate()
    }
    
    func addLongRunTemplate() {
        runPlanViewModel.addLongRunTemplate()
    }
    
    func startRunOnWatch() {
        guard hasSegments && !isStartingRun else { return }

        guard onboarding.requiredRunSetupComplete else {
            watchAlertMessage = onboarding.missingRunSetupMessage
            showingWatchAlert = true
            return
        }

        guard isWatchPaired && isWatchAppInstalled else {
            watchAlertMessage = "Pair an Apple Watch and install Pancake on it before starting a run."
            showingWatchAlert = true
            return
        }

        guard musicManager.hasAvailablePlaybackSource else {
            watchAlertMessage = MusicError.noPlayableMusicSource.localizedDescription
            showingWatchAlert = true
            return
        }

        isStartingRun = true

        // Store the pending segments so music can start when Watch confirms workout
        musicCoordinator.setPendingRunPlan(segments)

        // Send run plan to Watch — music will NOT start until Watch confirms workout started
        watchConnectivity.sendRunPlan(segments)

        // Handle response
        if let error = watchConnectivity.lastError {
            watchAlertMessage = "Error: \(error.localizedDescription)"
        } else {
            watchAlertMessage = "Run plan sent to Apple Watch! Open the Pancake app on your Watch and start the workout. Music will begin automatically when the workout starts."
        }

        showingWatchAlert = true
        isStartingRun = false
    }
    
    func dismissAlert() {
        showingWatchAlert = false
        watchAlertMessage = ""
    }
}
