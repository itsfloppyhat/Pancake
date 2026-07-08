import CloudKit
import SwiftUI

struct CheerSquadView: View {
    @StateObject private var manager = CheerSquadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var memberToBlock: SquadMember?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard

                    if let explanation = manager.availability.explanation {
                        CheerSquadNoticeCard(message: explanation)
                    }

                    if let errorMessage = manager.lastErrorMessage {
                        CheerSquadNoticeCard(message: errorMessage)
                    }

                    mySquadCard
                    joinedSquadsCard

                    if !manager.recentCheers.isEmpty {
                        recentCheersCard
                    }

                    reportCard
                }
                .padding()
            }
            .background(Color.pastelGroupedBackground.ignoresSafeArea())
            .navigationTitle("Cheer Squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await manager.refresh()
            }
            .refreshable {
                await manager.refresh()
            }
            .alert(
                "Remove from squad?",
                isPresented: Binding(
                    get: { memberToBlock != nil },
                    set: { if !$0 { memberToBlock = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { memberToBlock = nil }
                Button("Remove", role: .destructive) {
                    if let member = memberToBlock {
                        Task { await manager.blockMember(member) }
                    }
                    memberToBlock = nil
                }
            } message: {
                Text("They will no longer see when you run or be able to send cheers.")
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.pastelPeach)

            Text("Friends who cheer you on")
                .font(.headline)

            Text("Invite supporters with a private iCloud link. When you start a run they get a notification, and their cheers are read aloud over your music.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .pastelTintedCard(.pastelPeach)
    }

    private var mySquadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("My squad")
                .font(.headline)

            if manager.isSharingEnabled {
                if let shareURL = manager.shareURL {
                    ShareLink(item: shareURL) {
                        Label("Invite supporters", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelStart))
                }

                let supporters = manager.squadMembers.filter { !$0.isOwner }
                if supporters.isEmpty {
                    Text("No supporters yet. Share your invite link to build your squad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(supporters) { member in
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(Color.pastelPeriwinkle)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.displayName)
                                    .font(.subheadline)
                                Text(member.acceptanceStatus == .accepted ? "Joined" : "Invited")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Remove") {
                                memberToBlock = member
                            }
                            .font(.caption)
                            .foregroundStyle(Color.pastelCoral)
                        }
                    }
                }

                Toggle("Alert my squad when I start a run", isOn: alertToggleBinding)
                    .font(.subheadline)

                Toggle("Read cheers aloud during runs", isOn: announceToggleBinding)
                    .font(.subheadline)

                Button("Preview a spoken cheer") {
                    CheerAnnouncer.shared.announceCheer(
                        from: "Your squad",
                        message: CheerContentPolicy.presetCheers.randomElement() ?? "You've got this!"
                    )
                }
                .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelLavender))
            } else {
                Text("Set up your squad to share a private invite link. Only people you invite can see when you run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await manager.enableSharing() }
                } label: {
                    if manager.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Set up my squad", systemImage: "person.3.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelStart))
                .disabled(manager.availability != .available || manager.isBusy)
            }
        }
        .bubblyCard()
    }

    private var joinedSquadsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Squads I cheer for")
                .font(.headline)

            if manager.joinedSquads.isEmpty {
                Text("When a friend sends you their invite link, their squad appears here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !manager.runAlertsAuthorized {
                    Button("Enable run alerts") {
                        Task { await manager.enableRunAlerts() }
                    }
                    .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))
                }

                ForEach(manager.joinedSquads) { squad in
                    NavigationLink {
                        SendCheerView(squad: squad)
                    } label: {
                        HStack {
                            Circle()
                                .fill(squad.isRunningNow ? Color.pastelMint : Color.gray.opacity(0.35))
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(squad.runnerName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(squad.isRunningNow ? "Running now — send a cheer!" : "Not running")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .bubblyCard()
    }

    private var recentCheersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cheers from your last run")
                .font(.headline)

            ForEach(manager.recentCheers) { cheer in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cheer.senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cheer.message)
                        .font(.subheadline)
                }
            }
        }
        .bubblyCard()
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keeping cheers friendly")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Cheers are filtered before they play. Remove anyone from your squad at any time, and report abusive messages to support.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Report a problem") {
                if let url = URL(string: "mailto:mattlucascodes@gmail.com?subject=Pancake%20Cheer%20Report") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelPeriwinkle))
        }
        .bubblyCard()
    }

    private var alertToggleBinding: Binding<Bool> {
        Binding(
            get: { manager.settings.alertSquadOnRunStart },
            set: { manager.settings.alertSquadOnRunStart = $0 }
        )
    }

    private var announceToggleBinding: Binding<Bool> {
        Binding(
            get: { manager.settings.announceCheersDuringRuns },
            set: { manager.settings.announceCheersDuringRuns = $0 }
        )
    }
}

// MARK: - Send Cheer View

struct SendCheerView: View {
    let squad: JoinedSquad

    @StateObject private var manager = CheerSquadManager.shared
    @State private var customMessage = ""
    @State private var sendConfirmation: String?
    @State private var isSending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(squad.runnerName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(squad.isRunningNow
                         ? "Running now. Cheers arrive on their phone and play over their music."
                         : "Not running right now. You can still leave a cheer for their next run.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick cheers")
                        .font(.headline)

                    ForEach(CheerContentPolicy.presetCheers, id: \.self) { preset in
                        Button {
                            send(preset)
                        } label: {
                            Text(preset)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(BubblySmallButtonStyle(backgroundColor: .pastelMint))
                        .disabled(isSending)
                    }
                }
                .bubblyCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your own words")
                        .font(.headline)

                    TextField("Write a short cheer", text: $customMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...3)

                    Button {
                        send(customMessage)
                    } label: {
                        if isSending {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Send cheer", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(BubblyGradientButtonStyle(gradient: .pastelStart))
                    .disabled(customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .bubblyCard()

                if let confirmation = sendConfirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.pastelMint)
                }

                if let errorMessage = manager.lastErrorMessage {
                    CheerSquadNoticeCard(message: errorMessage)
                }
            }
            .padding()
        }
        .background(Color.pastelGroupedBackground.ignoresSafeArea())
        .navigationTitle("Send a cheer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send(_ message: String) {
        guard !isSending else { return }
        isSending = true
        sendConfirmation = nil

        Task {
            let didSend = await manager.sendCheer(to: squad, message: message)
            isSending = false
            if didSend {
                sendConfirmation = "Cheer sent"
                customMessage = ""
            }
        }
    }
}

// MARK: - Notice Card

private struct CheerSquadNoticeCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Color.pastelCoral)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pastelTintedCard(.pastelCoral)
    }
}

#if DEBUG
struct CheerSquadView_Previews: PreviewProvider {
    static var previews: some View {
        CheerSquadView()
    }
}
#endif
