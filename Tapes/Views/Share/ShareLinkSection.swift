import SwiftUI
import UIKit

/// Inline share-link section embedded in `ShareModalView`.
///
/// The sharing role is determined by the tape's type:
/// - My Tapes → always view-only
/// - Collab tapes (owner) → always collaborative
///
/// The "Secured by email" toggle switches between open / protected
/// within the fixed role.
struct ShareLinkSection: View {

    let tape: Tape

    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var entitlementManager: EntitlementManager

    // MARK: - UI state

    @State private var securedByEmail = false
    @State private var emailInput = ""

    // MARK: - Server state

    @State private var collaborators: [TapesAPIClient.CollaboratorInfo] = []
    @State private var isBootstrapping = false
    @State private var isInviting = false
    @State private var revokingIds: Set<String> = []
    @State private var shareActivityURL: URL?
    @State private var copiedConfirmation = false
    @State private var errorMessage: String?
    @State private var showingPaywall = false

    // MARK: - Derived

    private var isCollabTape: Bool {
        tape.isCollabTape
    }

    private var currentVariant: TapesAPIClient.ShareVariant {
        if isCollabTape {
            return securedByEmail ? .collabProtected : .collabOpen
        } else {
            return securedByEmail ? .viewProtected : .viewOpen
        }
    }

    private var cachedResponse: TapesAPIClient.CreateTapeResponse? {
        uploadCoordinator.cachedCreateResponse(for: tape)
    }

    private var shareURL: URL? {
        guard let response = cachedResponse else { return nil }
        let shareId = response.shareId(for: currentVariant)
        let base = response.shareUrl.components(separatedBy: "/t/").first ?? ""
        return URL(string: "\(base)/t/\(shareId)")
    }

    /// Users invited against the currently-selected variant only.
    private var collaboratorsForCurrentVariant: [TapesAPIClient.CollaboratorInfo] {
        collaborators.filter { $0.shareVariant == currentVariant && $0.role != "owner" }
    }

    private var canInvite: Bool {
        guard authManager.isSignedIn else { return false }
        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidEmail(trimmed) && !isInviting
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            SectionHeader(title: isCollabTape ? "Share for Collaboration" : "Share This Tape")

            VStack(spacing: Tokens.Spacing.m) {
                securedToggle

                if securedByEmail {
                    emailInputRow
                        .transition(.opacity)
                    authorisedUsersList
                        .transition(.opacity)
                }

                linkBlock

                if let error = errorMessage {
                    Text(error)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.systemRed)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: securedByEmail)
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
        .task { await bootstrapShareState() }
        .sheet(item: Binding(
            get: { shareActivityURL.map(ShareURLItem.init) },
            set: { if $0 == nil { shareActivityURL = nil } }
        )) { item in
            ShareActivityView(url: item.url) { completed, activityType in
                // Only count when the user actually picked a destination
                // and the OS-level share completed. Swipe-to-dismiss yields
                // completed=false, no activityType — that's not a share.
                if completed, activityType != nil {
                    entitlementManager.markTapeActivated(tape.id)
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if copiedConfirmation {
                CopiedToast()
                    .padding(.top, Tokens.Spacing.m)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: copiedConfirmation)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    /// Free-tier gate. Returns `true` if the action should proceed; `false`
    /// (and presents `PaywallView`) when the cap has been hit and this tape
    /// is not yet in the activation set. Already-activated tapes — including
    /// everything grandfathered on first launch — always pass.
    private func passesActivationGate() -> Bool {
        if entitlementManager.isTapeAlreadyActivated(tape.id) { return true }
        if entitlementManager.canActivateNewTape() { return true }
        showingPaywall = true
        return false
    }

    // MARK: - Secured Toggle

    private var securedToggle: some View {
        HStack(spacing: Tokens.Spacing.m) {
            Image(systemName: securedByEmail ? "lock.fill" : "lock.open")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(securedByEmail ? Tokens.Colors.systemBlue : Tokens.Colors.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Secured by email")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                Text(securedByEmail
                     ? "Only invited emails can add this tape."
                     : "Anyone with the link can add this tape.")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.secondaryText)
            }

            Spacer()

            Toggle("", isOn: securedByEmailBinding)
                .labelsHidden()
                .disabled(!authManager.isSignedIn)
        }
    }

    /// Toggle binding that gates the *on-flip* against the Free-tier
    /// activation cap. Same pattern as the AI Prompt segment in
    /// `BackgroundMusicSheet`: tapping the toggle while at the cap on a
    /// not-yet-activated tape opens the paywall and the toggle stays OFF.
    /// Turning the toggle off, or flipping it on for a tape that's already
    /// activated, is always allowed.
    private var securedByEmailBinding: Binding<Bool> {
        Binding(
            get: { securedByEmail },
            set: { newValue in
                if newValue, !passesActivationGate() {
                    return
                }
                securedByEmail = newValue
            }
        )
    }

    // MARK: - Link Block (URL row + Share Link button in one container)

    private var linkBlock: some View {
        VStack(spacing: Tokens.Spacing.s) {
            HStack(spacing: Tokens.Spacing.s) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Tokens.Colors.secondaryText)

                Text(linkDisplayString)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if uploadCoordinator.isUploading && cachedResponse == nil {
                    ProgressView().controlSize(.small)
                }

                Button {
                    copyLinkTapped()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.systemBlue)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy link")
            }

            shareLinkButton
        }
        .padding(Tokens.Spacing.s)
        .background(Tokens.Colors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - Share Link Button

    @ViewBuilder
    private var shareLinkButton: some View {
        let label = Label("Share Link", systemImage: "square.and.arrow.up")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)

        if securedByEmail {
            Button { shareLinkTapped() } label: { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Tokens.Colors.systemBlue)
        } else {
            Button { shareLinkTapped() } label: { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Tokens.Colors.systemBlue)
        }
    }

    private var linkDisplayString: String {
        if let url = shareURL { return url.absoluteString }
        if uploadCoordinator.isUploading { return uploadCoordinator.statusMessage }
        return "tapes.app/t/…"
    }

    // MARK: - Email Input Row

    private var emailInputRow: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "envelope")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .frame(width: 24)

            ZStack(alignment: .leading) {
                if emailInput.isEmpty {
                    Text("name@example.com")
                        .font(.system(size: 15))
                        .foregroundColor(Color(.placeholderText))
                        .allowsHitTesting(false)
                }

                TextField("", text: $emailInput)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .tint(Tokens.Colors.systemBlue)
                    .onSubmit {
                        if canInvite { inviteTapped() }
                    }
            }

            Button {
                inviteTapped()
            } label: {
                if isInviting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Label("Invite", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Tokens.Colors.systemBlue)
            .disabled(!canInvite)
        }
        .padding(.leading, Tokens.Spacing.m)
        .padding(.trailing, 10)
        .frame(height: 48)
        .background(Tokens.Colors.primaryBackground)
        .clipShape(Capsule())
    }

    // MARK: - Authorised Users

    private var authorisedUsersList: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            HStack {
                Text("Authorised users")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.secondaryText)
                Spacer()
                if isBootstrapping {
                    ProgressView().controlSize(.mini)
                }
            }

            if collaboratorsForCurrentVariant.isEmpty {
                Text("No one invited yet.")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.tertiaryText)
                    .padding(.vertical, Tokens.Spacing.xs)
            } else {
                WrapHStack(spacing: Tokens.Spacing.xs) {
                    ForEach(collaboratorsForCurrentVariant) { collab in
                        collaboratorChip(collab)
                    }
                }
            }
        }
    }

    private func collaboratorChip(_ collab: TapesAPIClient.CollaboratorInfo) -> some View {
        HStack(spacing: 6) {
            Text(collab.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Button {
                revokeTapped(collab)
            } label: {
                if revokingIds.contains(collab.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(collab.displayName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Tokens.Colors.primaryBackground)
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func copyLinkTapped() {
        errorMessage = nil

        guard passesActivationGate() else { return }

        guard let api = authManager.apiClient else {
            errorMessage = "Please sign in to share tapes."
            return
        }

        uploadCoordinator.ensureTapeUploaded(
            tape: tape,
            intendedForCollaboration: isCollabTape,
            api: api
        ) { response in
            finaliseShareInfo(response: response)
            uploadCoordinator.dismissCompletionDialog()

            let base = response.shareUrl.components(separatedBy: "/t/").first ?? ""
            if let url = URL(string: "\(base)/t/\(response.shareId(for: currentVariant))") {
                if uploadCoordinator.userDismissedModal {
                    uploadCoordinator.completedShareURL = url
                    uploadCoordinator.showPostUploadDialog = true
                } else {
                    UIPasteboard.general.string = url.absoluteString
                    // Copying the link is the user's commitment to share —
                    // count it against the Free-tier activation cap. Idempotent;
                    // re-copying the same tape later is a no-op.
                    entitlementManager.markTapeActivated(tape.id)
                    flashCopiedToast()
                }
            }
        }
    }

    private func shareLinkTapped() {
        errorMessage = nil

        guard passesActivationGate() else { return }

        guard let api = authManager.apiClient else {
            errorMessage = "Please sign in to share tapes."
            return
        }

        uploadCoordinator.ensureTapeUploaded(
            tape: tape,
            intendedForCollaboration: isCollabTape,
            api: api
        ) { response in
            finaliseShareInfo(response: response)
            uploadCoordinator.dismissCompletionDialog()

            let base = response.shareUrl.components(separatedBy: "/t/").first ?? ""
            if let url = URL(string: "\(base)/t/\(response.shareId(for: currentVariant))") {
                if uploadCoordinator.userDismissedModal {
                    uploadCoordinator.completedShareURL = url
                    uploadCoordinator.showPostUploadDialog = true
                } else {
                    shareActivityURL = url
                }
            }
        }
    }

    /// After the first successful upload of a collab tape, persist ShareInfo.
    /// Activation against the Free-tier cap is **not** triggered here — upload
    /// alone doesn't count as sharing. The cap moves at the moment the user
    /// commits to a share action: copying the link, completing a system share
    /// sheet with a destination, or sending an in-app email invite.
    private func finaliseShareInfo(response: TapesAPIClient.CreateTapeResponse) {
        guard isCollabTape, tape.shareInfo == nil else { return }
        let info = ShareInfo(
            shareId: response.shareIdCollab,
            ownerName: authManager.userName,
            mode: "collaborative",
            expiresAt: nil,
            remoteTapeId: response.tapeId
        )
        tapesStore.setCollabShareInfo(tapeId: tape.id, shareInfo: info)
    }

    private func inviteTapped() {
        errorMessage = nil

        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(trimmed) else { return }

        guard let api = authManager.apiClient else {
            errorMessage = "Please sign in to invite collaborators."
            return
        }

        let variant = currentVariant
        guard variant.isProtected else { return }

        if collaborators.contains(where: {
            $0.shareVariant == variant && $0.email.lowercased() == trimmed
        }) {
            errorMessage = "\(trimmed) has already been invited to this link."
            return
        }

        isInviting = true

        Task { @MainActor in
            defer { isInviting = false }

            await withCheckedContinuation { cont in
                if uploadCoordinator.cachedCreateResponse(for: tape) != nil {
                    cont.resume()
                    return
                }
                uploadCoordinator.ensureTapeUploaded(
                    tape: tape,
                    intendedForCollaboration: isCollabTape,
                    api: api
                ) { response in
                    finaliseShareInfo(response: response)
                    cont.resume()
                }
            }

            guard let remoteTapeId = uploadCoordinator.resultRemoteTapeId
                ?? uploadCoordinator.cachedCreateResponse(for: tape)?.tapeId else {
                errorMessage = "Couldn't upload this tape. Please try again."
                return
            }

            do {
                try await api.inviteCollaborator(
                    tapeId: remoteTapeId,
                    email: trimmed,
                    shareVariant: variant
                )
                // Inviting by email is the most deliberate share action the
                // user can take — they typed a specific recipient and we sent
                // mail. Counts against the Free-tier activation cap.
                entitlementManager.markTapeActivated(tape.id)
                emailInput = ""
                await reloadCollaborators(using: api, tapeId: remoteTapeId)
            } catch {
                errorMessage = friendlyError(error)
            }
        }
    }

    private func revokeTapped(_ collab: TapesAPIClient.CollaboratorInfo) {
        guard let api = authManager.apiClient,
              let remoteTapeId = uploadCoordinator.resultRemoteTapeId
                ?? uploadCoordinator.cachedCreateResponse(for: tape)?.tapeId,
              let variant = collab.shareVariant else { return }

        revokingIds.insert(collab.id)

        Task { @MainActor in
            defer { revokingIds.remove(collab.id) }
            do {
                let identifier = collab.userId ?? collab.email
                try await api.revokeCollaborator(
                    tapeId: remoteTapeId,
                    identifier: identifier,
                    shareVariant: variant
                )
                await reloadCollaborators(using: api, tapeId: remoteTapeId)
            } catch {
                errorMessage = friendlyError(error)
            }
        }
    }

    // MARK: - Bootstrapping

    private func bootstrapShareState() async {
        guard let api = authManager.apiClient else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        let remoteTapeId = tape.id.uuidString.lowercased()

        do {
            let info = try await api.getTape(tapeId: remoteTapeId)
            let base = TapesPublicShareBase
            let shareUrl = "\(base)/t/\(info.shareId)"
            let response = TapesAPIClient.CreateTapeResponse(
                tapeId: info.tapeId,
                shareId: info.shareId,
                shareIdCollab: info.shareIdCollab,
                shareIdViewProtected: info.shareIdViewProtected,
                shareIdCollabProtected: info.shareIdCollabProtected,
                shareUrl: shareUrl,
                deepLink: "tapes://t/\(info.shareId)",
                createdAt: info.createdAt,
                clipsUploaded: true,
                hasBackgroundMusic: nil
            )
            uploadCoordinator.seedCreateResponse(response, for: tape)
            await reloadCollaborators(using: api, tapeId: remoteTapeId)

            let hasProtectedCollaborators = collaborators.contains {
                $0.role != "owner" && ($0.shareVariant?.isProtected == true)
            }
            if hasProtectedCollaborators {
                securedByEmail = true
            }
        } catch {
            // Tape hasn't been shared yet — this is the normal first-time path.
        }
    }

    private func reloadCollaborators(using api: TapesAPIClient, tapeId: String) async {
        do {
            collaborators = try await api.listCollaborators(tapeId: tapeId)
        } catch {
            // Non-fatal — the UI just won't display the chips.
        }
    }

    // MARK: - Helpers

    private func flashCopiedToast() {
        copiedConfirmation = true
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            copiedConfirmation = false
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let regex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return value.range(of: regex, options: .regularExpression) != nil
    }

    private func friendlyError(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .validation(let message), .server(let message):
                return message
            case .unauthorized:
                return "Your session has expired. Please sign in again."
            default: break
            }
        }
        return "Something went wrong. Please try again."
    }
}

// MARK: - ShareURLItem

private struct ShareURLItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - ShareActivityView (UIActivityViewController wrapper)

private struct ShareActivityView: UIViewControllerRepresentable {
    let url: URL
    /// Fires when the system share sheet finishes. `completed` is true only
    /// when the user picked a destination and the share went through (not
    /// when they swiped down to dismiss). Used to drive the Free-tier
    /// activation count: a completed share with a chosen activity is the
    /// user committing to share this tape.
    var onCompleted: (_ completed: Bool, _ activityType: UIActivity.ActivityType?) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            onCompleted(completed, activityType)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - CopiedToast

private struct CopiedToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text("Link copied")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.75), in: Capsule())
    }
}

// MARK: - WrapHStack (lightweight flow layout)

private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: spacing) { content() }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxUsedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth && lineWidth > 0 {
                maxUsedWidth = max(maxUsedWidth, lineWidth - spacing)
                totalHeight += lineHeight + spacing
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        maxUsedWidth = max(maxUsedWidth, lineWidth - spacing)
        return CGSize(width: min(maxUsedWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Public share base (mirrors TapesAPIClient)

#if DEBUG
private let TapesPublicShareBase = "https://tapes-api.hi-7d5.workers.dev"
#else
private let TapesPublicShareBase = "https://api.tapes.app"
#endif
