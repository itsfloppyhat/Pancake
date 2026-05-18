import SwiftUI

struct UserProfileView: View {
    @StateObject private var viewModel = UserProfileViewModel()
    @StateObject private var onboarding = OnboardingManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    ProfileHeaderView(profile: viewModel.userProfile)
                    
                    // Quick Stats
                    QuickStatsView(profile: viewModel.userProfile)
                    
                    // Settings Sections
                    VStack(spacing: 16) {
                        SettingsSectionView(
                            title: "Setup Guide",
                            subtitle: onboarding.activationReady ? "Ready for your first run" : "Finish first-run setup",
                            icon: "checklist",
                            color: .pastelPeach
                        ) {
                            onboarding.resetOnboarding()
                        }

                        SettingsSectionView(
                            title: "Music Preferences",
                            subtitle: musicPreferencesSubtitle,
                            icon: "music.note.list",
                            color: .pastelLavender
                        ) {
                            viewModel.showMusicPreferences()
                        }

                        SettingsSectionView(
                            title: "Running Goals",
                            subtitle: String(format: "%.1f km/week", viewModel.userProfile.runningGoals.weeklyDistanceGoal),
                            icon: "target",
                            color: .pastelMint
                        ) {
                            viewModel.showRunningGoals()
                        }

                        SettingsSectionView(
                            title: "Personal Info",
                            subtitle: viewModel.userProfile.personalInfo.displayName.isEmpty ? "Tap to set up" : viewModel.userProfile.personalInfo.displayName,
                            icon: "person.circle",
                            color: .pastelPeriwinkle
                        ) {
                            viewModel.showPersonalInfo()
                        }

                        SettingsSectionView(
                            title: "AI Music Curation",
                            subtitle: viewModel.isAIConfigured ? "Apple Intelligence Ready" : "Check AI Settings",
                            icon: "brain.head.profile",
                            color: .pastelRose
                        ) {
                            viewModel.showAISettings()
                        }

                        SettingsSectionView(
                            title: "Song Check",
                            subtitle: "Preview a generated song without starting a run",
                            icon: "slider.horizontal.3",
                            color: .pastelPeach
                        ) {
                            viewModel.showPromptLab()
                        }
                        
                        HealthKitImportSectionView()
                    }
                    
                    // Music Authorization Status
                    MusicAuthorizationView(viewModel: viewModel)
                }
                .padding()
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $viewModel.showingMusicPreferences) {
                MusicPreferencesView()
            }
            .sheet(isPresented: $viewModel.showingRunningGoals) {
                RunningGoalsView()
            }
            .sheet(isPresented: $viewModel.showingPersonalInfo) {
                PersonalInfoView()
            }
            .sheet(isPresented: $viewModel.showingAISettings) {
                AISettingsView()
            }
            .sheet(isPresented: $viewModel.showingPromptLab) {
                PromptLabView()
            }
        }
    }

    private var musicPreferencesSubtitle: String {
        let preferences = viewModel.userProfile.musicPreferences
        let artistCount = preferences.allFavoriteArtists.count
        let songCount = preferences.allFavoriteSongs.count

        if let playlist = preferences.selectedPlaylist {
            return "Taste sample: \(playlist.name) • \(artistCount) artists, \(songCount) songs"
        }

        if artistCount == 0 && songCount == 0 {
            return "Tap to set up"
        }

        return "\(artistCount) artists, \(songCount) songs"
    }
}

// MARK: - Profile Header View
struct ProfileHeaderView: View {
    let profile: UserProfile
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Picture Placeholder
            Circle()
                .fill(LinearGradient.pastelProfile)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundColor(.white)
                )
            
            VStack(spacing: 4) {
                Text(profile.personalInfo.displayName.isEmpty ? "Runner" : profile.personalInfo.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(profile.runningGoals.experienceLevel.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .pastelTintedCard(.pastelLavender)
    }
}

// MARK: - Quick Stats View
struct QuickStatsView: View {
    let profile: UserProfile
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCardView(
                title: "Favorite Artists",
                value: "\(profile.musicPreferences.allFavoriteArtists.count)",
                icon: "music.mic"
            )
            
            StatCardView(
                title: "Favorite Songs",
                value: "\(profile.musicPreferences.allFavoriteSongs.count)",
                icon: "music.note"
            )
            
            StatCardView(
                title: "Weekly Goal",
                value: String(format: "%.1f km", profile.runningGoals.weeklyDistanceGoal),
                icon: "target"
            )
            
            StatCardView(
                title: "Experience",
                value: profile.runningGoals.experienceLevel.displayName,
                icon: "star.fill"
            )
        }
    }
}

// MARK: - Settings Section View
struct SettingsSectionView: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .bubblyCard()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Music Authorization View
struct MusicAuthorizationView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            AuthorizationStatusRow(
                icon: "music.note",
                title: "Library Taste Import",
                subtitle: viewModel.isLibraryAuthorized ? "Ready to import playlists, artists, songs, and genres" : "Not enabled",
                isConnected: viewModel.isLibraryAuthorized,
                actionTitle: "Continue"
            ) {
                viewModel.requestMusicAuthorization()
            }

            AuthorizationStatusRow(
                icon: "play.circle",
                title: "Apple Music Playback",
                subtitle: viewModel.isCatalogAuthorized ? "Ready to play generated songs outside your library" : "Not enabled",
                isConnected: viewModel.isCatalogAuthorized,
                actionTitle: "Continue"
            ) {
                Task {
                    await viewModel.requestCatalogAuthorization()
                }
            }

            Text("Library access helps Pancake learn your taste. Apple Music playback lets it play generated songs even when they are not already saved in your library.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.pastelCoral)
                    .multilineTextAlignment(.center)
            }
        }
        .pastelTintedCard(.pastelPeriwinkle)
        .onAppear {
            viewModel.refreshAuthorizationState()
        }
    }
}

struct AuthorizationStatusRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isConnected: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isConnected ? .pastelMint : .pastelPeach)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.pastelMint)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
            }
        }
    }
}

// MARK: - Music Preferences View
struct MusicPreferencesView: View {
    @StateObject private var profileManager = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingArtistSearch = false
    @State private var showingSongSearch = false
    @State private var showingPlaylistPicker = false
    @State private var isAutoPopulating = false
    @State private var isImportingPlaylist = false
    @State private var playlistError: Error?
    
    var body: some View {
        NavigationView {
            List {
                if profileManager.isMusicAuthorized {
                    Section("Playlist Taste Sample") {
                        if let playlist = profileManager.userProfile.musicPreferences.selectedPlaylist {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.headline)

                                Text("\(playlist.songCount) songs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if profileManager.userProfile.musicPreferences.hasImportedPlaylistContent {
                                Text(importedPlaylistSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Button(action: importSelectedPlaylist) {
                                HStack {
                                    if isImportingPlaylist {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundColor(.pastelLavender)
                                    }

                                    Text("Import Taste Sample")
                                }
                            }
                            .disabled(isImportingPlaylist)

                            Button("Choose Different Taste Sample") {
                                showingPlaylistPicker = true
                            }
                            .foregroundColor(.pastelPeriwinkle)

                            Button("Clear Imported Taste Sample", role: .destructive) {
                                profileManager.selectPlaylist(nil)
                            }
                        } else {
                            Button("Choose Playlist Taste Sample") {
                                showingPlaylistPicker = true
                            }
                            .foregroundColor(.pastelPeriwinkle)

                            Text("Select an Apple Music playlist to teach Pancake the runner's taste. The playlist is used for artists, songs, and genres, not as a playback queue.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Auto-Populate Section
                    Section {
                        Button(action: autoPopulatePreferences) {
                            HStack {
                                if isAutoPopulating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.pastelLavender)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-Populate from Entire Library")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text("Import your most played artists, songs, and genres from your full library")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                        .disabled(isAutoPopulating)
                    }
                }

                if let playlistError {
                    Section {
                        Text(playlistError.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.pastelCoral)
                    }
                }
                
                // Favorite Artists Section
                Section("Favorite Artists") {
                    if profileManager.userProfile.musicPreferences.favoriteArtists.isEmpty {
                        Text("No favorite artists yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(profileManager.userProfile.musicPreferences.favoriteArtists) { artist in
                            ArtistRowView(artist: artist)
                        }
                        .onDelete(perform: deleteArtists)
                    }
                    
                    Button("Add Artists") {
                        showingArtistSearch = true
                    }
                    .foregroundColor(.pastelLavender)
                }
                
                // Favorite Songs Section
                Section("Favorite Songs") {
                    if profileManager.userProfile.musicPreferences.favoriteSongs.isEmpty {
                        Text("No favorite songs yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(profileManager.userProfile.musicPreferences.favoriteSongs) { song in
                            SongRowView(song: song)
                        }
                        .onDelete(perform: deleteSongs)
                    }
                    
                    Button("Add Songs") {
                        showingSongSearch = true
                    }
                    .foregroundColor(.pastelLavender)
                }
                
                // Genres Section
                Section("Favorite Genres") {
                    ForEach(profileManager.userProfile.musicPreferences.favoriteGenres) { genre in
                        GenreRowView(genre: genre) {
                            profileManager.toggleGenre(genre)
                        }
                    }
                }
                
                // Mood Preferences Section
                Section("Mood Preferences by Zone") {
                    ForEach(Intensity.allCases) { intensity in
                        MoodPreferenceRowView(
                            intensity: intensity,
                            currentMood: profileManager.userProfile.musicPreferences.preferredMoodForIntensity[intensity] ?? .energetic
                        ) { mood in
                            profileManager.setMoodForIntensity(mood, intensity: intensity)
                        }
                    }
                }
            }
            .navigationTitle("Music Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingArtistSearch) {
                ArtistSearchView()
            }
            .sheet(isPresented: $showingSongSearch) {
                SongSearchView()
            }
            .sheet(isPresented: $showingPlaylistPicker) {
                PlaylistPickerView(
                    selectedPlaylistID: profileManager.userProfile.musicPreferences.selectedPlaylist?.id
                ) { playlist in
                    profileManager.selectPlaylist(playlist)
                    playlistError = nil
                }
            }
            .onAppear {
                profileManager.refreshMusicAuthorizationStates()
            }
        }
    }
    
    private func deleteArtists(offsets: IndexSet) {
        for index in offsets {
            let artist = profileManager.userProfile.musicPreferences.favoriteArtists[index]
            profileManager.removeFavoriteArtist(artist)
        }
    }
    
    private func deleteSongs(offsets: IndexSet) {
        for index in offsets {
            let song = profileManager.userProfile.musicPreferences.favoriteSongs[index]
            profileManager.removeFavoriteSong(song)
        }
    }
    
    private func autoPopulatePreferences() {
        isAutoPopulating = true
        
        Task {
            await profileManager.autoPopulateMusicPreferences()
            
            await MainActor.run {
                isAutoPopulating = false
            }
        }
    }

    private func importSelectedPlaylist() {
        isImportingPlaylist = true
        playlistError = nil

        Task {
            do {
                try await profileManager.importSelectedPlaylistPreferences()
            } catch {
                await MainActor.run {
                    playlistError = error
                }
            }

            await MainActor.run {
                isImportingPlaylist = false
            }
        }
    }

    private var importedPlaylistSummary: String {
        let preferences = profileManager.userProfile.musicPreferences
        return "Taste sample added: \(preferences.importedPlaylistSongs.count) songs, \(preferences.importedPlaylistArtists.count) artists, and \(preferences.importedPlaylistGenres.count) genres."
    }
}

// MARK: - Row Views
struct ArtistRowView: View {
    let artist: MusicArtist
    
    var body: some View {
        HStack {
            AsyncImage(url: artist.artwork) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if !artist.genres.isEmpty {
                    Text(artist.genres.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

struct SongRowView: View {
    let song: MusicSong
    
    var body: some View {
        HStack {
            AsyncImage(url: song.artwork) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(song.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(song.duration.formattedTime())
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct GenreRowView: View {
    let genre: MusicGenre
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Text(genre.name)
                .font(.subheadline)
            
            Spacer()
            
            Button(action: onToggle) {
                Image(systemName: genre.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(genre.isSelected ? .pastelLavender : .gray)
            }
        }
    }
}

struct MoodPreferenceRowView: View {
    let intensity: Intensity
    let currentMood: MusicMood
    let onMoodSelected: (MusicMood) -> Void
    
    var body: some View {
        HStack {
            Text(intensity.label)
                .font(.subheadline)
            
            Spacer()
            
            Menu {
                ForEach(MusicMood.allCases, id: \.self) { mood in
                    Button(action: { onMoodSelected(mood) }) {
                        HStack {
                            Text(mood.displayName)
                            if mood == currentMood {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: currentMood.icon)
                        .foregroundColor(Color(currentMood.color))
                    Text(currentMood.displayName)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Running Goals View
struct RunningGoalsView: View {
    @StateObject private var profileManager = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var goals: RunningGoals
    
    init() {
        _goals = State(initialValue: UserProfileManager.shared.userProfile.runningGoals)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Weekly Goals") {
                    HStack {
                        Text("Distance Goal")
                        Spacer()
                        TextField("km", value: $goals.weeklyDistanceGoal, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Number of Runs")
                        Spacer()
                        TextField("runs", value: $goals.weeklyRunGoal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Target Pace") {
                    HStack {
                        Text("Pace per Kilometer")
                        Spacer()
                        TextField("mm:ss", value: $goals.targetPace, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Preferences") {
                    Picker("Experience Level", selection: $goals.experienceLevel) {
                        ForEach(RunningGoals.ExperienceLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    
                    Picker("Preferred Run Time", selection: $goals.preferredRunTime) {
                        Text("Morning").tag("morning")
                        Text("Afternoon").tag("afternoon")
                        Text("Evening").tag("evening")
                    }
                }
            }
            .navigationTitle("Running Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        profileManager.updateRunningGoals(goals)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Personal Info View
struct PersonalInfoView: View {
    @StateObject private var profileManager = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var info: PersonalInfo
    
    init() {
        _info = State(initialValue: UserProfileManager.shared.userProfile.personalInfo)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Display Name", text: $info.displayName)
                    
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("years", value: $info.age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Physical Info") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", value: $info.weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", value: $info.height, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Heart Rate") {
                    HStack {
                        Text("Resting Heart Rate")
                        Spacer()
                        TextField("bpm", value: $info.restingHeartRate, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Max Heart Rate")
                        Spacer()
                        TextField("bpm", value: $info.maxHeartRate, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Personal Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        profileManager.updatePersonalInfo(info)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Artist Search View
struct ArtistSearchView: View {
    @StateObject private var profileManager = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [MusicArtist] = []
    @State private var isSearching = false
    @State private var searchError: Error?
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search for artists...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchArtists()
                        }
                    
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                
                // Search Results
                if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                    VStack(spacing: 16) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No artists found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Try searching for a different artist name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Search for Artists")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Enter an artist name to search your music library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults) { artist in
                        ArtistSearchRowView(artist: artist) {
                            profileManager.addFavoriteArtist(artist)
                        }
                    }
                }
                
                if let error = searchError {
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.pastelCoral)
                        .padding()
                }
            }
            .navigationTitle("Add Artists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func searchArtists() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSearching = true
        searchError = nil
        
        Task {
            do {
                let results = try await profileManager.searchArtists(query: searchText)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchError = error
                    self.isSearching = false
                }
            }
        }
    }
}

// MARK: - Song Search View
struct SongSearchView: View {
    @StateObject private var profileManager = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [MusicSong] = []
    @State private var isSearching = false
    @State private var searchError: Error?
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search for songs...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchSongs()
                        }
                    
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                
                // Search Results
                if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No songs found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Try searching for a different song title")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Search for Songs")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Enter a song title to search your music library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults) { song in
                        SongSearchRowView(song: song) {
                            profileManager.addFavoriteSong(song)
                        }
                    }
                }
                
                if let error = searchError {
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.pastelCoral)
                        .padding()
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func searchSongs() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSearching = true
        searchError = nil
        
        Task {
            do {
                let results = try await profileManager.searchSongs(query: searchText)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchError = error
                    self.isSearching = false
                }
            }
        }
    }
}

struct PlaylistPickerView: View {
    @StateObject private var profileManager = UserProfileManager.shared
    @Environment(\.dismiss) private var dismiss

    let selectedPlaylistID: String?
    let onSelect: (ImportedPlaylist) -> Void

    @State private var playlists: [ImportedPlaylist] = []
    @State private var isLoading = true
    @State private var loadError: Error?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading playlist taste samples...")
                } else if let loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.pastelCoral)

                        Text(loadError.localizedDescription)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        Text("No playlists found in your library")
                            .font(.headline)

                        Text("Add an Apple Music playlist to your library, then return here to use it as a taste sample.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List(playlists) { playlist in
                        Button {
                            onSelect(playlist)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .foregroundColor(.primary)

                                    Text("\(playlist.songCount) songs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if playlist.id == selectedPlaylistID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.pastelMint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Taste Sample")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadPlaylists()
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        loadError = nil

        do {
            playlists = try await profileManager.fetchPlaylists()
        } catch {
            loadError = error
        }

        isLoading = false
    }
}

// MARK: - Search Row Views
struct ArtistSearchRowView: View {
    let artist: MusicArtist
    let onAdd: () -> Void
    @State private var isAdded = false
    
    var body: some View {
        HStack {
            // Artist Info
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.headline)
                
                if !artist.genres.isEmpty {
                    Text(artist.genres.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Add Button
            Button(action: {
                onAdd()
                isAdded = true
            }) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isAdded ? .pastelMint : .pastelPeriwinkle)
                    .font(.title2)
            }
            .disabled(isAdded)
        }
        .padding(.vertical, 4)
    }
}

struct SongSearchRowView: View {
    let song: MusicSong
    let onAdd: () -> Void
    @State private var isAdded = false
    
    var body: some View {
        HStack {
            // Song Info
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let album = song.album {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Duration
            Text(song.duration.formattedTime())
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Add Button
            Button(action: {
                onAdd()
                isAdded = true
            }) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isAdded ? .pastelMint : .pastelPeriwinkle)
                    .font(.title2)
            }
            .disabled(isAdded)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HealthKit Import Section
struct HealthKitImportSectionView: View {
    @StateObject private var historyViewModel = HistoryViewModel()
    @State private var showingImportAlert = false
    @State private var showingClearAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "heart.text.square")
                    .foregroundColor(.pastelCoral)
                    .font(.title2)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running History")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(historyViewModel.isHealthKitAuthorized ? "Import running history" : "Authorize HealthKit access")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if historyViewModel.isImportingFromHealthKit {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        if historyViewModel.isHealthKitAuthorized {
                            showingImportAlert = true
                        } else {
                            historyViewModel.requestHealthKitAuthorization()
                        }
                    }) {
                        Text(historyViewModel.isHealthKitAuthorized ? "Import" : "Authorize")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(historyViewModel.isHealthKitAuthorized ? Color.pastelPeriwinkle : Color.pastelPeach)
                            )
                    }
                }
            }
            
            // Import result message
            if let result = historyViewModel.importResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Error message
            if let error = historyViewModel.error {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.pastelCoral)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Clear data button (only show if there are events)
            if historyViewModel.hasEvents {
                Button(action: {
                    showingClearAlert = true
                }) {
                    Text("Clear All Data")
                        .font(.caption)
                        .foregroundColor(.pastelCoral)
                }
            }
        }
        .pastelTintedCard(.pastelCoral)
        .alert("Import Running History", isPresented: $showingImportAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Import") {
                Task {
                    await historyViewModel.importFromHealthKit()
                }
            }
        } message: {
            Text("This will import all running workouts from HealthKit that are longer than 0.5km. Duplicate runs will be automatically filtered out.")
        }
        .alert("Clear All Data", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                historyViewModel.clearAllData()
            }
        } message: {
            Text("This will permanently delete all running history data. This action cannot be undone.")
        }
    }
}

#if DEBUG
struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        UserProfileView()
    }
}
#endif
