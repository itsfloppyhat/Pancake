import Foundation
import Combine

// MARK: - User Profile ViewModel
@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var showingMusicPreferences: Bool = false
    @Published var showingRunningGoals: Bool = false
    @Published var showingPersonalInfo: Bool = false
    @Published var showingChatGPTSettings: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // Dependencies
    private let profileManager = UserProfileManager.shared
    private let chatGPTService = ChatGPTService.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        profileManager.$lastError
            .assign(to: &$error)
        
        chatGPTService.$lastError
            .assign(to: &$error)
    }
    
    // MARK: - Profile Access
    var userProfile: UserProfile {
        profileManager.userProfile
    }
    
    var isMusicAuthorized: Bool {
        profileManager.isMusicAuthorized
    }
    
    var musicAuthorizationStatus: String {
        profileManager.musicAuthorizationStatus.description
    }
    
    var isChatGPTConfigured: Bool {
        chatGPTService.isConfigured
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
    
    func showChatGPTSettings() {
        showingChatGPTSettings = true
    }
    
    func dismissAllSheets() {
        showingMusicPreferences = false
        showingRunningGoals = false
        showingPersonalInfo = false
        showingChatGPTSettings = false
    }
    
    func requestMusicAuthorization() {
        profileManager.requestMusicAuthorization()
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
