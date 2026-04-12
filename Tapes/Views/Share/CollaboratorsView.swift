import SwiftUI
import os

struct CollaboratorsView: View {
    let tapeId: String
    let isOwner: Bool

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var collaborators: [TapesAPIClient.CollaboratorInfo] = []
    @State private var isLoading = true
    @State private var inviteEmail = ""
    @State private var inviteRole: String = "collaborator"
    @State private var isInviting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var confirmRevoke: TapesAPIClient.CollaboratorInfo?

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Collaborators")

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    if isOwner {
                        inviteSection
                    }

                    if isLoading {
                        loadingView
                    } else if collaborators.isEmpty {
                        emptyView
                    } else {
                        collaboratorList
                    }
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.top, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.xxl)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Collaborators")
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
            .alert("Remove Collaborator", isPresented: .init(
                get: { confirmRevoke != nil },
                set: { if !$0 { confirmRevoke = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    if let collab = confirmRevoke {
                        Task { await revokeCollaborator(collab) }
                    }
                }
                Button("Cancel", role: .cancel) { confirmRevoke = nil }
            } message: {
                if let collab = confirmRevoke {
                    Text("Remove \(collab.name ?? collab.email) from this tape? They will lose access to all clips.")
                }
            }
            .task {
                await loadCollaborators()
            }
        }
    }

    // MARK: - Invite Section

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Invite")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, Tokens.Spacing.xs)

            HStack(spacing: Tokens.Spacing.s) {
                TextField("Email address", text: $inviteEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .font(.system(size: 16))
                    .foregroundStyle(Tokens.Colors.primaryText)

                Button {
                    Task { await sendInvite() }
                } label: {
                    if isInviting {
                        ProgressView()
                            .tint(Tokens.Colors.systemBlue)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(canInvite ? Tokens.Colors.systemBlue : Tokens.Colors.tertiaryText)
                    }
                }
                .disabled(!canInvite || isInviting)
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))

            Picker("Role", selection: $inviteRole) {
                Text("Collaborator").tag("collaborator")
                Text("Co-Admin").tag("co-admin")
            }
            .pickerStyle(.segmented)

            if let success = successMessage {
                HStack(spacing: Tokens.Spacing.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.primaryText)
                }
                .transition(.opacity)
            }

            if let error = errorMessage {
                HStack(spacing: Tokens.Spacing.s) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Tokens.Colors.systemRed)
                    Text(error)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.systemRed)
                }
                .transition(.opacity)
            }
        }
    }

    private var canInvite: Bool {
        let trimmed = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("@") && trimmed.contains(".")
    }

    // MARK: - Collaborator List

    private var collaboratorList: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Members (\(collaborators.count))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, Tokens.Spacing.xs)

            ForEach(collaborators, id: \.email) { collab in
                collaboratorRow(collab)
            }
        }
    }

    private func collaboratorRow(_ collab: TapesAPIClient.CollaboratorInfo) -> some View {
        HStack(spacing: Tokens.Spacing.m) {
            Image(systemName: collab.role == "owner" ? "crown.fill" : "person.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(roleColor(collab.role))

            VStack(alignment: .leading, spacing: 2) {
                Text(collab.name ?? collab.email)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: Tokens.Spacing.xs) {
                    Text(roleName(collab.role))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(roleColor(collab.role))

                    if collab.status == "invited" {
                        Text("· Pending")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Colors.tertiaryText)
                    }
                }
            }

            Spacer()

            if isOwner && collab.role != "owner" {
                Menu {
                    if collab.role == "collaborator" {
                        Button {
                            Task { await updateRole(collab, to: "co-admin") }
                        } label: {
                            Label("Promote to Co-Admin", systemImage: "arrow.up.circle")
                        }
                    } else if collab.role == "co-admin" {
                        Button {
                            Task { await updateRole(collab, to: "collaborator") }
                        } label: {
                            Label("Demote to Collaborator", systemImage: "arrow.down.circle")
                        }
                    }

                    Button(role: .destructive) {
                        confirmRevoke = collab
                    } label: {
                        Label("Remove", systemImage: "person.crop.circle.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
            }
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack {
            Spacer().frame(height: 80)
            ProgressView()
                .tint(Tokens.Colors.secondaryText)
            Text("Loading collaborators...")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .padding(.top, Tokens.Spacing.m)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer().frame(height: 80)

            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text("No collaborators yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
    }

    // MARK: - Helpers

    private func roleName(_ role: String) -> String {
        switch role {
        case "owner": return "Owner"
        case "co-admin": return "Co-Admin"
        default: return "Collaborator"
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "owner": return .orange
        case "co-admin": return Tokens.Colors.systemBlue
        default: return Tokens.Colors.secondaryText
        }
    }

    // MARK: - Actions

    private func loadCollaborators() async {
        guard let api = authManager.apiClient else { return }

        do {
            let list = try await api.listCollaborators(tapeId: tapeId)
            await MainActor.run {
                collaborators = list
                isLoading = false
            }
        } catch {
            log.error("Failed to load collaborators: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to load collaborators."
            }
        }
    }

    private func sendInvite() async {
        guard let api = authManager.apiClient else { return }
        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        isInviting = true
        errorMessage = nil
        successMessage = nil

        do {
            try await api.inviteCollaborator(tapeId: tapeId, email: email, role: inviteRole)
            await MainActor.run {
                successMessage = "Invitation sent to \(email)"
                inviteEmail = ""
            }
            await loadCollaborators()
        } catch {
            log.error("Failed to invite: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run { isInviting = false }
    }

    private func updateRole(_ collab: TapesAPIClient.CollaboratorInfo, to newRole: String) async {
        guard let api = authManager.apiClient, let userId = collab.userId else { return }

        do {
            try await api.updateRole(tapeId: tapeId, userId: userId, role: newRole)
            await loadCollaborators()
        } catch {
            log.error("Failed to update role: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revokeCollaborator(_ collab: TapesAPIClient.CollaboratorInfo) async {
        guard let api = authManager.apiClient, let userId = collab.userId else { return }

        do {
            try await api.revokeCollaborator(tapeId: tapeId, userId: userId)
            await loadCollaborators()
        } catch {
            log.error("Failed to revoke: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    CollaboratorsView(tapeId: "test-tape-id", isOwner: true)
        .environmentObject(AuthManager())
}
