import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboarding = OnboardingManager.shared
    @StateObject private var profileManager = UserProfileManager.shared
    @State private var showingMusicPreferences = false
    @State private var showingSongCheck = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    OnboardingHeaderView(onboarding: onboarding)

                    VStack(spacing: 12) {
                        ForEach(OnboardingStep.allCases) { step in
                            OnboardingStepCard(
                                step: step,
                                isSelected: onboarding.currentStep == step,
                                isComplete: isComplete(step),
                                statusText: statusText(for: step)
                            ) {
                                onboarding.currentStep = step
                            } content: {
                                content(for: step)
                            }
                        }
                    }

                    Button {
                        onboarding.completeOnboarding()
                    } label: {
                        Label(
                            onboarding.activationReady ? "Start using Pancake" : "Explore Pancake",
                            systemImage: "arrow.right.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelStart))
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(Color.pastelGroupedBackground.ignoresSafeArea())
            .navigationTitle("Setup Guide")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onboarding.completeOnboarding()
                    }
                }
            }
            .sheet(isPresented: $showingMusicPreferences) {
                MusicPreferencesView()
            }
            .sheet(isPresented: $showingSongCheck) {
                PromptLabView()
            }
            .task {
                await onboarding.refresh()
            }
        }
    }

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Pancake uses your run plan, live effort, and music taste to pick songs while you run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Set up Pancake") {
                    onboarding.moveNext()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelLavender))
            }

        case .runAccess:
            VStack(spacing: 12) {
                OnboardingPermissionRow(
                    title: "Health history import",
                    subtitle: "Optional. Read completed runs from Health into your iPhone history.",
                    icon: "heart.fill",
                    isComplete: onboarding.healthReady
                ) {
                    onboarding.requestHealthAuthorization()
                }

                Button("Continue") {
                    onboarding.moveNext()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))
            }

        case .music:
            VStack(spacing: 12) {
                OnboardingPermissionRow(
                    title: "Apple Music playback",
                    subtitle: "Optional. Play requested suggestions or start an Adaptive Mix during a run.",
                    icon: "play.circle.fill",
                    isComplete: onboarding.catalogReady
                ) {
                    Task {
                        await onboarding.requestCatalogAuthorization()
                    }
                }

                OnboardingPermissionRow(
                    title: "Library taste import",
                    subtitle: "Optional. Learn artists, songs, genres, and playlists you already like.",
                    icon: "music.note.list",
                    isComplete: onboarding.libraryReady
                ) {
                    onboarding.requestLibraryAuthorization()
                }

                HStack(spacing: 10) {
                    Button("Import taste") {
                        Task {
                            await onboarding.autoPopulateMusicTaste()
                        }
                    }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelLavender))
                    .disabled(!profileManager.isMusicAuthorized || onboarding.isWorking)

                    Button("Choose playlist") {
                        showingMusicPreferences = true
                    }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeach))
                }

                Button("Continue") {
                    onboarding.moveNext()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
            }

        case .songCheck:
            VStack(alignment: .leading, spacing: 12) {
                Text("If you plan to use Adaptive Mix, verify catalog playback before your first run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Open Song Check") {
                    showingSongCheck = true
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeach))

                Button("Continue") {
                    onboarding.moveNext()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
            }

        case .watch:
            VStack(alignment: .leading, spacing: 12) {
                OnboardingStatusLine(
                    icon: onboarding.watchReady ? "checkmark.circle.fill" : "applewatch.slash",
                    text: onboarding.watchReady ? "Watch companion is ready" : "Install Pancake on your watch before your first run.",
                    color: onboarding.watchReady ? .pastelMint : .pastelPeach
                )

                Text("Start the workout from the watch companion. Music stays off until you request a suggestion or tap Start Adaptive Mix.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(onboarding.activationReady ? "Finish setup" : "Finish for now") {
                    onboarding.completeOnboarding()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))
            }
        }
    }

    private func isComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome: return true
        case .runAccess: return onboarding.healthReady
        case .music: return onboarding.musicPlaybackReady && onboarding.musicTasteReady
        case .songCheck: return onboarding.musicPlaybackReady
        case .watch: return onboarding.watchReady
        }
    }

    private func statusText(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:
            return "Start here"
        case .runAccess:
            return onboarding.healthReady ? "Import ready" : "Optional"
        case .music:
            if onboarding.musicPlaybackReady && onboarding.musicTasteReady { return "Ready" }
            if onboarding.musicPlaybackReady { return "Taste recommended" }
            return "Optional"
        case .songCheck:
            return onboarding.musicPlaybackReady ? "Available" : "After music setup"
        case .watch:
            return onboarding.watchReady ? "Ready" : "Before first run"
        }
    }
}

private struct OnboardingHeaderView: View {
    @ObservedObject var onboarding: OnboardingManager

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: onboarding.currentStep.icon)
                .font(.system(size: 46))
                .foregroundStyle(Color.pastelLavender)

            VStack(spacing: 6) {
                Text("Get ready to run")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Step \(onboarding.currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(onboarding.currentStep.rawValue + 1), total: Double(OnboardingStep.allCases.count))
                .tint(.pastelLavender)
        }
        .pastelTintedCard(.pastelLavender)
    }
}

private struct OnboardingStepCard<Content: View>: View {
    let step: OnboardingStep
    let isSelected: Bool
    let isComplete: Bool
    let statusText: String
    let select: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : step.icon)
                        .foregroundColor(isComplete ? .pastelMint : .pastelLavender)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                content
            }
        }
        .bubblyCard()
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isComplete ? .pastelMint : .pastelLavender)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.pastelMint)
            } else {
                Button("Continue", action: action)
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
            }
        }
    }
}

private struct OnboardingStatusLine: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline)
        }
    }
}

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
#endif
