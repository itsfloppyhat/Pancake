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
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        watchConnectivity.$lastError
            .assign(to: &$error)
        watchConnectivity.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        musicCoordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        // Forward changes from runPlanViewModel to trigger UI updates
        runPlanViewModel.$segments
            .sink { [weak self] _ in
                // This will trigger UI updates when segments change
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
        hasSegments && isWatchPaired && isWatchAppInstalled && !isStartingRun
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

        guard isWatchPaired && isWatchAppInstalled else {
            watchAlertMessage = "Pair a watch and install Pancake on it before starting a run."
            showingWatchAlert = true
            return
        }

        isStartingRun = true
        let plan = segments
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.showingWatchAlert = true
                self.isStartingRun = false
            }
            do {
                try await self.watchConnectivity.sendRunPlan(plan)
                self.musicCoordinator.setPendingRunPlan(plan)
            } catch {
                self.watchAlertMessage = "Couldn't send the run plan: \(error.localizedDescription)"
                return
            }

            do {
                try await HealthKitManager.shared.startWatchApp()
                self.watchAlertMessage = "Pancake has been opened on your watch. Your plan will appear there — tap Start Run when you're ready."
            } catch {
                self.watchAlertMessage = "Your plan is saved for the watch, but Pancake couldn't open automatically: \(error.localizedDescription). Open Pancake on your watch to start."
            }
        }
    }
    
    func dismissAlert() {
        showingWatchAlert = false
        watchAlertMessage = ""
    }
}
