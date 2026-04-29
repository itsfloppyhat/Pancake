import SwiftUI

struct AISettingsView: View {
    @StateObject private var aiService = MusicAIService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // AI Status Section
                Section {
                    AIStatusView(status: aiService.availabilityStatus)
                        .onAppear {
                            aiService.checkAvailability()
                        }
                } header: {
                    Text("AI Status")
                } footer: {
                    Text("AI music features use on-device Apple Intelligence - no internet required and no additional costs.")
                }

                // Music Selection Settings Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Music Selection")
                            .font(.headline)

                        Text("Control how strongly Pancake prefers your saved library versus fresh generated picks during a run.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Library Selection")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Spacer()

                                Text("\(Int(aiService.librarySelectionProbability * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.pastelPeriwinkle)
                            }

                            Slider(
                                value: $aiService.librarySelectionProbability,
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
                            .onChange(of: aiService.librarySelectionProbability) { _, newValue in
                                aiService.setLibrarySelectionProbability(newValue)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("0% - Lean into fresh suggestions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("100% - Stay close to your library")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Music Selection Settings")
                }

                // Features Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Features")
                            .font(.headline)

                        FeatureRowView(
                            icon: "apple.logo",
                            title: "On-Device AI",
                            description: "All AI processing happens on your device - private, fast, and free"
                        )

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
                            title: "Taste-Aware Suggestions",
                            description: "Uses your saved favorites and imported playlist taste samples to shape each next-song suggestion"
                        )

                        FeatureRowView(
                            icon: "wifi.slash",
                            title: "Works Offline",
                            description: "No internet connection needed - AI runs entirely on your device"
                        )
                    }
                } header: {
                    Text("What You'll Get")
                }

                // Requirements Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Requirements")
                            .font(.headline)

                        RequirementRowView(
                            icon: "iphone",
                            title: "Compatible Device",
                            description: "iPhone 15 Pro or later, iPad with M-series chip"
                        )

                        RequirementRowView(
                            icon: "gearshape",
                            title: "Apple Intelligence",
                            description: "Must be enabled in Settings > Apple Intelligence & Siri"
                        )

                        RequirementRowView(
                            icon: "arrow.down.circle",
                            title: "Model Download",
                            description: "AI model downloads automatically when first enabled"
                        )
                    }
                } header: {
                    Text("System Requirements")
                }
            }
            .navigationTitle("AI Settings")
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
}

// MARK: - AI Status View

struct AIStatusView: View {
    let status: AIAvailabilityStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundColor(statusColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.headline)

                if case .unavailable(let reason) = status {
                    Text(reason.userMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("AI-powered music suggestions are ready to use")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch status {
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .available:
            return .pastelMint
        case .unavailable:
            return .pastelPeach
        }
    }

    private var statusTitle: String {
        switch status {
        case .available:
            return "Apple Intelligence Available"
        case .unavailable:
            return "Apple Intelligence Unavailable"
        }
    }
}

// MARK: - Feature Row View

struct FeatureRowView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.pastelLavender)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Requirement Row View

struct RequirementRowView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView()
    }
}
#endif
