import SwiftUI

struct SocialRunView: View {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var socialManager = RunSocialManager.shared
    @State private var draftMessages: [UUID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SocialHeaderView(
                    isSignedIn: authManager.isAuthenticated,
                    notificationsAuthorized: socialManager.notificationsAuthorized,
                    isSharingRun: socialManager.isSharingCurrentRun
                )

                SocialSetupCard(authManager: authManager, socialManager: socialManager)

                ActiveFriendsCard(
                    friends: socialManager.activeFriends,
                    draftMessages: $draftMessages
                ) { runner, message in
                    socialManager.sendComment(to: runner, message: message)
                    draftMessages[runner.id] = ""
                }

                RecentCommentsCard(comments: socialManager.recentComments)

#if DEBUG
                SocialPreviewCard(socialManager: socialManager)
#endif
            }
            .padding()
        }
        .background(Color.pastelGroupedBackground.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await socialManager.refreshNotificationAuthorization()
        }
    }
}

private struct SocialHeaderView: View {
    let isSignedIn: Bool
    let notificationsAuthorized: Bool
    let isSharingRun: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.pastelRose)

            Text("Run with friends")
                .font(.title2)
                .fontWeight(.bold)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .pastelTintedCard(.pastelRose)
    }

    private var statusText: String {
        if isSharingRun {
            return "Your current run is shareable with friends."
        }
        if isSignedIn && notificationsAuthorized {
            return "Friend run alerts and spoken comments are ready."
        }
        return "Sign in and enable notifications to use live friend activity."
    }
}

private struct SocialSetupCard: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var socialManager: RunSocialManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup")
                .font(.headline)

            if authManager.isAuthenticated {
                SocialStatusRow(icon: "person.crop.circle.badge.checkmark", title: "Account", subtitle: authManager.displayName, isComplete: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    SignInWithAppleButtonView(authManager: authManager)
                        .frame(height: 50)
                }
            }

            HStack {
                SocialStatusRow(
                    icon: "bell.badge.fill",
                    title: "Notifications",
                    subtitle: socialManager.notificationsAuthorized ? "Enabled" : "Required for friend run alerts",
                    isComplete: socialManager.notificationsAuthorized
                )

                if !socialManager.notificationsAuthorized {
                    Button("Enable") {
                        Task {
                            await socialManager.requestNotificationAuthorization()
                        }
                    }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
                }
            }

            Toggle("Speak incoming comments", isOn: Binding(
                get: { socialManager.settings.announceCommentsDuringRuns },
                set: { socialManager.setAnnounceCommentsDuringRuns($0) }
            ))

            Toggle("Share my active runs", isOn: Binding(
                get: { socialManager.settings.shareRunsWithFriends },
                set: { socialManager.setShareRunsWithFriends($0) }
            ))
            .disabled(!authManager.isAuthenticated)

            Text("Live friend delivery needs the Pancake social backend. This client is ready for notification permission, run sharing, comments, and spoken comment playback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .bubblyCard()
    }
}

private struct ActiveFriendsCard: View {
    let friends: [SocialRunner]
    @Binding var draftMessages: [UUID: String]
    let sendComment: (SocialRunner, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Friend Activity")
                .font(.headline)

            ForEach(friends) { friend in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: friend.isRunning ? "figure.run" : "moon.zzz.fill")
                            .foregroundColor(friend.isRunning ? .pastelMint : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text(friendStatus(friend))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if friend.isRunning {
                        HStack {
                            TextField("Send encouragement", text: Binding(
                                get: { draftMessages[friend.id] ?? "" },
                                set: { draftMessages[friend.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button {
                                sendComment(friend, draftMessages[friend.id] ?? "")
                            } label: {
                                Image(systemName: "paperplane.fill")
                            }
                            .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelRose))
                        }
                    }
                }
                .pastelTintedCard(friend.isRunning ? .pastelMint : .pastelLavender)
            }
        }
        .bubblyCard()
    }

    private func friendStatus(_ friend: SocialRunner) -> String {
        guard let startedAt = friend.currentRunStartedAt else {
            return friend.lastKnownStatus
        }

        let minutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        return "\(friend.lastKnownStatus) • \(minutes)m in"
    }
}

private struct RecentCommentsCard: View {
    let comments: [SocialRunComment]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Comments")
                .font(.headline)

            if comments.isEmpty {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: comment.direction == .incoming ? "speaker.wave.2.fill" : "paperplane.fill")
                            .foregroundColor(comment.direction == .incoming ? .pastelMint : .pastelRose)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(comment.runnerName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(comment.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
        .bubblyCard()
    }
}

private struct SocialStatusRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(isComplete ? .pastelMint : .pastelPeach)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#if DEBUG
private struct SocialPreviewCard: View {
    @ObservedObject var socialManager: RunSocialManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)

            HStack {
                Button("Friend run alert") {
                    socialManager.previewFriendStartedRun()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))

                Button("Speak comment") {
                    socialManager.previewIncomingComment()
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))
            }
        }
        .bubblyCard()
    }
}

struct SocialRunView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SocialRunView()
        }
    }
}
#endif
