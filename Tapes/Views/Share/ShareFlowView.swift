import SwiftUI

struct ShareFlowView: View {
    let tape: Tape
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var authManager: AuthManager

    @State private var mode: ShareMode = .viewOnly
    @State private var expiresIn7Days = true
    @State private var inviteEmail = ""
    @State private var invitedEmails: [String] = []
    @State private var isSharing = false
    @State private var shareResult: ShareResult?
    @State private var errorMessage: String?

    enum ShareMode: String, CaseIterable {
        case viewOnly = "View Only"
        case collaborative = "Collaborative"
    }

    struct ShareResult {
        let shareUrl: String
        let deepLink: String
        let shareId: String
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    if let result = shareResult {
                        shareSuccessView(result)
                    } else {
                        modeSection
                        if mode == .viewOnly {
                            expirySection
                        }
                        inviteSection
                        shareButton
                    }
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.top, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.xxl)
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
            .alert("Sharing Failed", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage {
                    Text(msg)
                }
            }
        }
    }

    // MARK: - Mode Selection

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Share Mode")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, Tokens.Spacing.xs)

            Picker("Mode", selection: $mode) {
                ForEach(ShareMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
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
        switch mode {
        case .viewOnly:
            return "Recipients can play back and AirPlay the tape. They cannot contribute clips or re-share."
        case .collaborative:
            return "Recipients can add their own clips, trim, and adjust audio. You control who can invite others."
        }
    }

    // MARK: - Expiry

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Expiry")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, Tokens.Spacing.xs)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-expire after 7 days")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Tokens.Colors.primaryText)
                    Text("Tape is removed from recipients after expiry")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }

                Spacer()

                Toggle("", isOn: $expiresIn7Days)
                    .labelsHidden()
                    .tint(Tokens.Colors.systemBlue)
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Invite People")
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
                    addInvite()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(inviteEmail.isEmpty ? Tokens.Colors.tertiaryText : Tokens.Colors.systemBlue)
                }
                .disabled(inviteEmail.isEmpty)
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))

            if !invitedEmails.isEmpty {
                VStack(spacing: Tokens.Spacing.s) {
                    ForEach(invitedEmails, id: \.self) { email in
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Tokens.Colors.secondaryText)

                            Text(email)
                                .font(.system(size: 15))
                                .foregroundStyle(Tokens.Colors.primaryText)

                            Spacer()

                            Button {
                                invitedEmails.removeAll { $0 == email }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Tokens.Colors.tertiaryText)
                            }
                        }
                        .padding(.horizontal, Tokens.Spacing.m)
                        .padding(.vertical, Tokens.Spacing.s)
                    }
                }
                .background(Tokens.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            }
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            Task { await shareTape() }
        } label: {
            HStack(spacing: Tokens.Spacing.s) {
                if isSharing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSharing ? "Sharing..." : "Share Tape")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Tokens.Colors.systemBlue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isSharing)
        .padding(.top, Tokens.Spacing.s)
    }

    // MARK: - Success View

    private func shareSuccessView(_ result: ShareResult) -> some View {
        VStack(spacing: Tokens.Spacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Tape Shared")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Tokens.Colors.primaryText)

            Text("Share this link with your recipients:")
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Colors.secondaryText)

            HStack {
                Text(result.shareUrl)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    UIPasteboard.general.string = result.shareUrl
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundStyle(Tokens.Colors.systemBlue)
                }
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))

            Button {
                let items: [Any] = [result.shareUrl]
                let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = windowScene.windows.first?.rootViewController {
                    root.present(ac, animated: true)
                }
            } label: {
                HStack(spacing: Tokens.Spacing.s) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Link")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Tokens.Colors.systemBlue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("Done") {
                dismiss()
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Tokens.Colors.secondaryText)
            .padding(.top, Tokens.Spacing.s)
        }
        .padding(.top, Tokens.Spacing.xl)
    }

    // MARK: - Actions

    private func addInvite() {
        let trimmed = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@"), !invitedEmails.contains(trimmed) else { return }
        invitedEmails.append(trimmed)
        inviteEmail = ""
    }

    private func shareTape() async {
        guard let api = authManager.apiClient else {
            errorMessage = "Not signed in. Please sign in and try again."
            return
        }

        isSharing = true
        defer { isSharing = false }

        do {
            let apiMode = mode == .viewOnly ? "view_only" : "collaborative"
            let expiresAt: String? = (mode == .viewOnly && expiresIn7Days)
                ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(7 * 24 * 60 * 60))
                : nil

            let tapeSettings: [String: Any] = [
                "default_audio_level": 1.0,
                "transition": [
                    "type": tape.transition.rawValue,
                    "duration_ms": Int(tape.transitionDuration * 1000)
                ] as [String: Any],
                "merge_settings": [
                    "orientation": tape.exportOrientation.rawValue,
                    "background_blur": tape.blurExportBackground
                ] as [String: Any]
            ]

            let response = try await api.createTape(
                tapeId: tape.id.uuidString.lowercased(),
                title: tape.title,
                mode: apiMode,
                expiresAt: expiresAt,
                tapeSettings: tapeSettings
            )

            var failedInvites: [String] = []
            for email in invitedEmails {
                do {
                    try await api.inviteCollaborator(
                        tapeId: tape.id.uuidString.lowercased(),
                        email: email
                    )
                } catch {
                    failedInvites.append(email)
                }
            }

            if !failedInvites.isEmpty {
                await MainActor.run {
                    errorMessage = "Tape shared, but invites failed for: \(failedInvites.joined(separator: ", "))"
                }
            }

            await MainActor.run {
                shareResult = ShareResult(
                    shareUrl: response.shareUrl,
                    deepLink: response.deepLink,
                    shareId: response.shareId
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ShareFlowView(tape: Tape.sampleTapes[1])
        .environmentObject(EntitlementManager())
        .environmentObject(AuthManager())
}
