import Foundation
import Combine

// MARK: - User Profile ViewModel
@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var showingMusicPreferences: Bool = false
    @Published var showingRunningGoals: Bool = false
    @Published var showingPersonalInfo: Bool = false
    @Published var showingAISettings: Bool = false
    @Published var showingPromptLab: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // Dependencies
    private let profileManager = UserProfileManager.shared
    private let aiService = MusicAIService.shared
    private let musicKitService = MusicKitService.shared

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    private func setupBindings() {
        profileManager.$lastError
            .assign(to: &$error)

        aiService.$lastError
            .assign(to: &$error)

        profileManager.$userProfile
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        profileManager.$isMusicAuthorized
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicKitService.$isAuthorized
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        musicKitService.$authorizationStatus
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        aiService.$availabilityStatus
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Profile Access
    var userProfile: UserProfile {
        profileManager.userProfile
    }

    var isLibraryAuthorized: Bool {
        profileManager.isMusicAuthorized
    }

    var isMusicAuthorized: Bool {
        isLibraryAuthorized
    }

    var isCatalogAuthorized: Bool {
        musicKitService.isAuthorized
    }

    var musicAuthorizationStatus: String {
        profileManager.musicAuthorizationStatus.description
    }

    var catalogAuthorizationStatus: String {
        String(describing: musicKitService.authorizationStatus)
    }

    var isAIConfigured: Bool {
        aiService.isConfigured
    }

    // MARK: - Actions
    func showMusicPreferences() {
        showingMusicPreferences = true
    }

    func showRunningGoals() {
        showingRunningGoals = true
    }

    func showPersonalInfo() {
        showingPersonalInfo = true
    }

    func showAISettings() {
        showingAISettings = true
    }

    func showPromptLab() {
        showingPromptLab = true
    }

    func dismissAllSheets() {
        showingMusicPreferences = false
        showingRunningGoals = false
        showingPersonalInfo = false
        showingAISettings = false
        showingPromptLab = false
    }
    
    func requestMusicAuthorization() {
        profileManager.requestMusicAuthorization()
    }

    func requestCatalogAuthorization() async {
        await profileManager.requestCatalogAuthorization()
    }

    func refreshAuthorizationState() {
        profileManager.refreshMusicAuthorizationStates()
    }
    
    func autoPopulateMusicPreferences() async {
        isLoading = true
        await profileManager.autoPopulateMusicPreferences()
        isLoading = false
    }
    
    func clearError() {
        error = nil
    }
    
    // MARK: - Profile Updates
    func updateProfile(_ profile: UserProfile) {
        profileManager.updateProfile(profile)
    }
    
    func updateMusicPreferences(_ preferences: MusicPreferences) {
        profileManager.updateMusicPreferences(preferences)
    }
    
    func updateRunningGoals(_ goals: RunningGoals) {
        profileManager.updateRunningGoals(goals)
    }
    
    func updatePersonalInfo(_ info: PersonalInfo) {
        profileManager.updatePersonalInfo(info)
    }
}
