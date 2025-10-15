import SwiftUI

struct ChatGPTSettingsView: View {
    @StateObject private var chatGPTService = ChatGPTService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var apiKey: String = ""
    @State private var showingAPIKeyAlert = false
    @State private var testResult: String = ""
    @State private var isTesting = false
    
    var body: some View {
        NavigationStack {
            Form {
                // API Key Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OpenAI API Key")
                            .font(.headline)
                        
                        Text("Enter your OpenAI API key to enable AI-powered music suggestions during workouts.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onAppear {
                                apiKey = chatGPTService.apiKey
                            }
                        
                        HStack {
                            Button("Save Key") {
                                chatGPTService.setAPIKey(apiKey)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKey.isEmpty)
                            
                            Spacer()
                            
                            Button("Test Connection") {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .disabled(apiKey.isEmpty || isTesting)
                        }
                        
                        if isTesting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Testing connection...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !testResult.isEmpty {
                            Text(testResult)
                                .font(.caption)
                                .foregroundColor(testResult.contains("Success") ? .green : .red)
                        }
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    Text("Your API key is stored securely on your device and never shared. Get your key from platform.openai.com")
                }
                
                // Music Selection Settings Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Music Selection")
                            .font(.headline)
                        
                        Text("Configure how often the AI selects songs from your music library vs. suggesting new songs.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Library Selection")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("\(Int(chatGPTService.librarySelectionProbability * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(
                                value: $chatGPTService.librarySelectionProbability,
                                in: 0...1,
                                step: 0.05
                            ) {
                                Text("Library Selection Probability")
                            } minimumValueLabel: {
                                Text("0%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("100%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("0% - Always suggest new songs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("100% - Always use your library")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Music Selection Settings")
                }
                
                // How to Get API Key Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to Get Your API Key")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            StepView(number: 1, text: "Visit platform.openai.com")
                            StepView(number: 2, text: "Sign up or log in to your account")
                            StepView(number: 3, text: "Go to API Keys section")
                            StepView(number: 4, text: "Create a new secret key")
                            StepView(number: 5, text: "Copy and paste it above")
                        }
                        
                        Button("Open OpenAI Website") {
                            if let url = URL(string: "https://platform.openai.com/api-keys") {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Setup Instructions")
                }
                
                // Features Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Features")
                            .font(.headline)
                        
                        FeatureRowView(
                            icon: "music.note",
                            title: "Smart Music Suggestions",
                            description: "AI suggests songs based on your heart rate, workout intensity, and music preferences"
                        )
                        
                        FeatureRowView(
                            icon: "heart.fill",
                            title: "Biometric-Responsive",
                            description: "Music adapts to your heart rate zones and effort level in real-time"
                        )
                        
                        FeatureRowView(
                            icon: "sparkles",
                            title: "Personalized Curation",
                            description: "Uses your favorite artists and genres to create perfect workout playlists"
                        )
                        
                        FeatureRowView(
                            icon: "timer",
                            title: "Perfect Timing",
                            description: "Suggests songs that match your segment duration and workout flow"
                        )
                    }
                } header: {
                    Text("What You'll Get")
                }
                
                // Pricing Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pricing")
                            .font(.headline)
                        
                        Text("OpenAI charges based on usage. Typical costs:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            PricingRowView(feature: "Music suggestion", cost: "~$0.001")
                            PricingRowView(feature: "Motivational message", cost: "~$0.0005")
                            PricingRowView(feature: "Per workout session", cost: "~$0.01-0.05")
                        }
                        
                        Text("Most users spend less than $1-2 per month on AI features.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Cost Information")
                }
            }
            .navigationTitle("ChatGPT Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = ""
        
        Task {
            do {
                // Test with a simple request
                let testContext = MusicContext(
                    currentHeartRate: 150,
                    targetHeartRate: 160,
                    currentIntensity: .medium,
                    timeRemainingInSegment: 120,
                    currentSongEndingIn: 30,
                    userPreferences: MusicPreferences(),
                    recentSongs: [],
                    currentDistance: 500.0, // 500m for testing
                    currentPace: 2.5, // 2.5 m/s for testing
                    isActive: true
                )
                
                let _ = try await chatGPTService.generateMusicSuggestion(
                    context: testContext,
                    userPreferences: MusicPreferences()
                )
                
                await MainActor.run {
                    testResult = "✅ Success! ChatGPT is working correctly."
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct StepView: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FeatureRowView: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PricingRowView: View {
    let feature: String
    let cost: String
    
    var body: some View {
        HStack {
            Text(feature)
                .font(.caption)
            Spacer()
            Text(cost)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
    }
}

#Preview {
    ChatGPTSettingsView()
}
