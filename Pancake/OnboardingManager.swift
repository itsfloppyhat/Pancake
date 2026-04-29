import Combine
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case account
    case runAccess
    case music
    case songCheck
    case watch

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .account: return "Account"
        case .runAccess: return "Run access"
        case .music: return "Music"
        case .songCheck: return "Song check"
        case .watch: return "Watch"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "figure.run.circle.fill"
        case .account: return "person.crop.circle.badge.checkmark"
        case .runAccess: return "heart.text.square.fill"
        case .music: return "music.note.list"
        case .songCheck: return "play.circle.fill"
        case .watch: return "applewatch"
        }
    }
}

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var hasCompletedOnboarding: Bool
    @Published var currentStep: OnboardingStep = .welcome
    @Published var isWorking = false
    @Published var lastError: Error?

    private let completionKey = "OnboardingManager.hasCompletedOnboarding"
    private let authManager = AuthManager.shared
    private let healthKitManager = HealthKitManager.shared
    private let locationManager = LocationManager.shared
    private let profileManager = UserProfileManager.shared
    private let musicKitService = MusicKitService.shared
    private let musicManager = MusicPlaybackManager.shared
    private let watchConnectivity = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: completionKey)
        bindDependencies()
    }

    var accountReady: Bool {
        authManager.isAuthenticated
    }

    var healthReady: Bool {
        healthKitManager.isAuthorized
    }

    var locationReady: Bool {
        locationManager.isAuthorized
    }

    var runAccessReady: Bool {
        healthReady && locationReady
    }

    var libraryReady: Bool {
        profileManager.isMusicAuthorized
    }

    var catalogReady: Bool {
        musicKitService.isAuthorized
    }

    var musicPlaybackReady: Bool {
        musicManager.hasAvailablePlaybackSource
    }

    var musicTasteReady: Bool {
        let preferences = profileManager.userProfile.musicPreferences
        return preferences.hasImportedPlaylistContent ||
            !preferences.allFavoriteSongs.isEmpty ||
            !preferences.allFavoriteArtists.isEmpty ||
            preferences.allFavoriteGenres.contains { $0.isSelected }
    }

    var watchReady: Bool {
        watchConnectivity.isWatchPaired && watchConnectivity.isWatchAppInstalled
    }

    var requiredRunSetupComplete: Bool {
        runAccessReady && musicPlaybackReady
    }

    var activationReady: Bool {
        requiredRunSetupComplete && musicTasteReady
    }

    var missingRunSetupMessage: String {
        if !runAccessReady {
            return "Finish Health and location setup before starting a run."
        }
        if !musicPlaybackReady {
            return MusicError.noPlayableMusicSource.localizedDescription
        }
        return "Setup is ready."
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: completionKey)
    }

    func resetOnboarding() {
        currentStep = .welcome
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: completionKey)
    }

    func moveNext() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        currentStep = next
    }

    func moveBack() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previous
    }

    func requestHealthAuthorization() {
        healthKitManager.requestAuthorization()
    }

    func requestLocationAuthorization() {
        locationManager.requestAuthorization()
    }

    func requestLibraryAuthorization() {
        profileManager.requestMusicAuthorization()
    }

    func requestCatalogAuthorization() async {
        isWorking = true
        await profileManager.requestCatalogAuthorization()
        isWorking = false
    }

    func autoPopulateMusicTaste() async {
        guard profileManager.isMusicAuthorized else { return }
        isWorking = true
        await profileManager.autoPopulateMusicPreferences()
        isWorking = false
    }

    func refresh() async {
        isWorking = true
        await healthKitManager.refreshAuthorizationState()
        profileManager.refreshMusicAuthorizationStates()
        isWorking = false
    }

    private func bindDependencies() {
        let publishers: [AnyPublisher<Void, Never>] = [
            authManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            healthKitManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            locationManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            profileManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            musicKitService.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            watchConnectivity.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(publishers)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
