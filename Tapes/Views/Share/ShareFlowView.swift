import SwiftUI

struct ShareFlowView: View {
    let tape: Tape
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator

    @State private var selectedMode: ShareMode = .viewing
    @State private var inviteEmail = ""
    @State private var pendingInvites: [String] = []
    @State private var isSendingInvites = false
    @State private var errorMessage: String?

    // Server state
    @State private var isLoading = true
    @State private var viewShareId: String?
    @State private var collabShareId: String?
    @State private var openAccess = false
    @State private var clipsOnServer = false
    @State private var collaborators: [TapesAPIClient.CollaboratorInfo] = []

    // Alerts
    @State private var personToRevoke: TapesAPIClient.CollaboratorInfo?

    enum ShareMode: String, CaseIterable {
        case viewing = "Viewing"
        case collaborating = "Collaborating"
    }

    private var shareBaseUrl: String { "https://tapes-api.hi-7d5.workers.dev/t/" }

    private var activeShareId: String? {
        selectedMode == .viewing ? viewShareId : collabShareId
    }

    private var activeShareUrl: String? {
        guard let id = activeShareId else { return nil }
        return shareBaseUrl + id
    }

    private var viewShareUrl: String? {
        guard let id = viewShareId else { return nil }
        return shareBaseUrl + id
    }

    private var viewCollaborators: [TapesAPIClient.CollaboratorInfo] {
        collaborators.filter { $0.role != "owner" && ($0.accessMode ?? "view") == "view" }
    }

    private var collabCollaborators: [TapesAPIClient.CollaboratorInfo] {
        collaborators.filter { $0.role != "owner" && ($0.accessMode ?? "view") == "collaborate" }
    }

    private var activeCollaborators: [TapesAPIClient.CollaboratorInfo] {
        selectedMode == .viewing ? viewCollaborators : collabCollaborators
    }

    private var sendInvitesLabel: String {
        if !isSendingInvites { return "Send invites" }
        return "Sending…"
    }

    private var sendInvitesButtonActive: Bool {
        isSendingInvites || !pendingInvites.isEmpty
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Tokens.Colors.primaryBackground)
                } else {
                    ScrollView {
                        VStack(spacing: Tokens.Spacing.l) {
                            modeSection

                            if selectedMode == .viewing {
                                viewingContent
                            } else {
                                collaboratingContent
                            }
                        }
                        .padding(.horizontal, Tokens.Spacing.l)
                        .padding(.top, Tokens.Spacing.l)
                        .padding(.bottom, Tokens.Spacing.xxl)
                    }
                }
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Share \(tape.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.primaryText)
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage {
                    Text(msg)
                }
            }
            .alert("Revoke Access", isPresented: .init(
                get: { personToRevoke != nil },
                set: { if !$0 { personToRevoke = nil } }
            )) {
                Button("Cancel", role: .cancel) { personToRevoke = nil }
                Button("Revoke", role: .destructive) {
                    if let person = personToRevoke {
                        personToRevoke = nil
                        Task { await revokePerson(person) }
                    }
                }
            } message: {
                if let person = personToRevoke {
                    Text("Remove \(person.displayName)'s access to this tape?")
                }
            }
            .task { await loadShareState() }
        }
    }

    // MARK: - Mode Selection

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(ShareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(modeDescription)
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .padding(.horizontal, Tokens.Spacing.xs)
        }
    }

    private var modeDescription: String {
        switch selectedMode {
        case .viewing:
            return "Recipients can play, AirPlay, and edit the tape on their device."
        case .collaborating:
            return "Recipients can add their own clips and contribute to the tape."
        }
    }

    // MARK: - Viewing Content

    @ViewBuilder
    private var viewingContent: some View {
        shareLinkSection(url: viewShareUrl)

        if !openAccess {
            inviteComposeSection

            if !viewCollaborators.isEmpty {
                peopleSectionView(
                    title: "Viewing",
                    people: viewCollaborators,
                    statusLabel: { $0.status == "invited" ? "Pending" : "Viewing" }
                )
            }
        }
    }

    // MARK: - Collaborating Content

    @ViewBuilder
    private var collaboratingContent: some View {
        if let url = activeShareUrl {
            collabLinkCard(url: url)
        }

        inviteComposeSection

        if !collabCollaborators.isEmpty {
            peopleSectionView(
                title: "Collaborating",
                people: collabCollaborators,
                statusLabel: { $0.status == "invited" ? "Pending" : "Joined" }
            )
        }
    }

    // MARK: - Share Link Section (Viewing — unified card)

    private func shareLinkSection(url: String?) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Share link")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tokens.Colors.primaryText)

            VStack(spacing: 0) {
                // Toggle row
                Toggle(isOn: $openAccess) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Everyone with the link can view")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Tokens.Colors.primaryText)
                        Text("Anyone who opens this link will be able to view and rebuild this tape")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Colors.secondaryText)
                    }
                }
                .tint(Tokens.Colors.systemBlue)
                .padding(Tokens.Spacing.m)
                .onChange(of: openAccess) { _, newValue in
                    Task { await syncOpenAccess(newValue) }
                }

                if let url {
                    Divider()
                        .padding(.horizontal, Tokens.Spacing.m)

                    // URL row
                    HStack(spacing: Tokens.Spacing.s) {
                        Image(systemName: "link")
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.Colors.secondaryText)

                        Text(url)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Tokens.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = url
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16))
                                .foregroundStyle(Tokens.Colors.systemBlue)
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.vertical, Tokens.Spacing.s)

                    // Share Link button
                    Button {
                        shareLink(url)
                    } label: {
                        HStack(spacing: Tokens.Spacing.s) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Link")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Tokens.Colors.systemBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.bottom, Tokens.Spacing.m)
                    .padding(.top, Tokens.Spacing.s)
                } else if openAccess {
                    Button {
                        startBackgroundShare(invites: [])
                    } label: {
                        HStack(spacing: Tokens.Spacing.s) {
                            Image(systemName: "link.badge.plus")
                            Text("Generate Link")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Tokens.Colors.systemBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(uploadCoordinator.isUploading)
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.bottom, Tokens.Spacing.m)
                    .padding(.top, Tokens.Spacing.xs)
                }
            }
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - Collab Link Card

    private func collabLinkCard(url: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Share link")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tokens.Colors.primaryText)

            VStack(spacing: Tokens.Spacing.m) {
                HStack(spacing: Tokens.Spacing.s) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.Colors.secondaryText)

                    Text(url)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Tokens.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = url
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 16))
                            .foregroundStyle(Tokens.Colors.systemBlue)
                    }
                }

                Button {
                    shareLink(url)
                } label: {
                    HStack(spacing: Tokens.Spacing.s) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Link")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Tokens.Colors.systemBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - Invite Compose Section

    private var inviteComposeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Invite people")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tokens.Colors.primaryText)

            VStack(spacing: Tokens.Spacing.m) {
                // Email input row — inner inset field
                HStack(spacing: Tokens.Spacing.s) {
                    Image(systemName: "envelope")
                        .font(.system(size: 16))
                        .foregroundStyle(Tokens.Colors.secondaryText)

                    TextField("Email Address", text: $inviteEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .font(.system(size: 16))
                        .foregroundStyle(Tokens.Colors.primaryText)
                        .onSubmit { addPendingInvite() }

                    Button {
                        addPendingInvite()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(inviteEmail.isEmpty ? Tokens.Colors.tertiaryText : Tokens.Colors.systemBlue)
                    }
                    .disabled(inviteEmail.isEmpty)
                }
                .padding(Tokens.Spacing.m)
                .background(Tokens.Colors.primaryBackground.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))

                // Pending batch rows
                ForEach(pendingInvites, id: \.self) { email in
                    HStack(spacing: Tokens.Spacing.s) {
                        Text(email)
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.Colors.primaryText)

                        Spacer()

                        Button {
                            pendingInvites.removeAll { $0 == email }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Tokens.Colors.tertiaryText)
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.xs)
                }

                // Send Invites button
                Button {
                    Task { await sendInvites() }
                } label: {
                    HStack(spacing: Tokens.Spacing.s) {
                        if isSendingInvites {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(sendInvitesLabel)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(sendInvitesButtonActive ? Tokens.Colors.systemBlue : Tokens.Colors.primaryBackground.opacity(0.6))
                    .foregroundStyle(sendInvitesButtonActive ? .white : Tokens.Colors.tertiaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(pendingInvites.isEmpty || isSendingInvites)
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - People Section (confirmed invitees with status badges)

    private func peopleSectionView(
        title: String,
        people: [TapesAPIClient.CollaboratorInfo],
        statusLabel: @escaping (TapesAPIClient.CollaboratorInfo) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Tokens.Colors.primaryText)

            VStack(spacing: 0) {
                ForEach(people) { person in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Tokens.Colors.primaryText)

                            if person.name != nil {
                                Text(person.email)
                                    .font(Tokens.Typography.caption)
                                    .foregroundStyle(Tokens.Colors.tertiaryText)
                            }
                        }

                        Spacer()

                        let label = statusLabel(person)
                        let color: Color = label == "Pending" ? .orange : .green

                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.15))
                            .clipShape(Capsule())

                        Button {
                            personToRevoke = person
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.vertical, Tokens.Spacing.s)

                    if person.id != people.last?.id {
                        Divider()
                            .padding(.leading, Tokens.Spacing.m)
                    }
                }
            }
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - Load State from Server

    private func loadShareState() async {
        guard let api = authManager.apiClient else {
            isLoading = false
            return
        }

        let tapeId = tape.id.uuidString.lowercased()

        do {
            let tapeInfo = try await api.getTape(tapeId: tapeId)
            let collabs = try await api.listCollaborators(tapeId: tapeId)

            await MainActor.run {
                viewShareId = tapeInfo.shareId
                collabShareId = tapeInfo.shareIdCollab
                openAccess = tapeInfo.openAccess ?? false
                clipsOnServer = tapeInfo.clipCount > 0
                collaborators = collabs
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }

    // MARK: - Toggle Open Access

    private func syncOpenAccess(_ value: Bool) async {
        guard let api = authManager.apiClient else { return }
        let tapeId = tape.id.uuidString.lowercased()

        guard viewShareId != nil || collabShareId != nil else { return }

        do {
            _ = try await api.updateOpenAccess(tapeId: tapeId, openAccess: value)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to update setting: \(error.localizedDescription)"
                openAccess = !value
            }
        }
    }

    // MARK: - Invite Helpers

    private func addPendingInvite() {
        let trimmed = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else { return }
        guard !pendingInvites.contains(trimmed) else {
            inviteEmail = ""
            return
        }

        pendingInvites.append(trimmed)
        inviteEmail = ""
    }

    private func sendInvites() async {
        guard let api = authManager.apiClient else {
            errorMessage = "Not connected. Please sign in from the Account tab."
            return
        }

        let tapeId = tape.id.uuidString.lowercased()
        let accessMode = selectedMode == .viewing ? "view" : "collaborate"

        // If clips need uploading, delegate to the background coordinator
        if activeShareId == nil {
            startBackgroundShare(invites: pendingInvites)
            return
        }

        // Clips already on server — send invites inline
        isSendingInvites = true
        defer { isSendingInvites = false }

        var failedEmails: [String] = []

        for email in pendingInvites {
            do {
                try await api.inviteCollaborator(tapeId: tapeId, email: email, accessMode: accessMode)
            } catch {
                failedEmails.append(email)
            }
        }

        if let collabs = try? await api.listCollaborators(tapeId: tapeId) {
            collaborators = collabs
        }

        pendingInvites = failedEmails
        if !failedEmails.isEmpty {
            errorMessage = "Failed to invite: \(failedEmails.joined(separator: ", "))"
        }
    }

    // MARK: - Background Share (delegates to coordinator)

    private func startBackgroundShare(invites: [String]) {
        guard let api = authManager.apiClient else {
            errorMessage = "Not connected. Please sign in from the Account tab."
            return
        }

        guard authManager.hasServerSession else {
            errorMessage = "Your session hasn't been set up. Please sign out and sign in again from the Account tab."
            return
        }

        let mode: ShareUploadCoordinator.ShareMode = selectedMode == .viewing ? .viewing : .collaborating

        uploadCoordinator.startShare(
            tape: tape,
            mode: mode,
            inviteEmails: invites,
            api: api
        )
    }

    // MARK: - Revoke Person

    private func revokePerson(_ person: TapesAPIClient.CollaboratorInfo) async {
        guard let api = authManager.apiClient else { return }
        let tapeId = tape.id.uuidString.lowercased()
        let identifier = person.userId ?? person.email

        do {
            try await api.revokeCollaborator(tapeId: tapeId, identifier: identifier)
            await MainActor.run {
                collaborators.removeAll { $0.id == person.id }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to revoke access: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Share Link via UIActivityViewController

    private func shareLink(_ url: String) {
        let items: [Any] = [url]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }

        var topController = root
        while let presented = topController.presentedViewController {
            topController = presented
        }

        if let popover = ac.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topController.present(ac, animated: true)
    }

}

#Preview {
    ShareFlowView(tape: Tape.sampleTapes[1])
        .environmentObject(AuthManager())
        .environmentObject(ShareUploadCoordinator())
}
