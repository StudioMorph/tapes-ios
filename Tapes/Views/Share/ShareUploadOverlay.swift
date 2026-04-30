import SwiftUI

struct ShareUploadProgressDialog: View {
    @ObservedObject var coordinator: ShareUploadCoordinator
    var onDismissToBackground: (() -> Void)?

    private var isUpdate: Bool {
        coordinator.sourceTape?.lastUploadedClipCount != nil
    }

    private var isContribution: Bool {
        coordinator.resultMode == .collaborating && coordinator.sourceTape?.isShared == true
    }

    private var title: String {
        if isContribution { return "Contributing…" }
        if isUpdate { return "Updating Shared Tape…" }
        return "Sharing Tape…"
    }

    var body: some View {
        GlassAlertCard(
            title: title,
            buttons: [
                GlassAlertButton(title: "Cancel", style: .destructive) {
                    coordinator.cancelUpload()
                },
                GlassAlertButton(title: "OK", style: .primaryFill) {
                    coordinator.dismissToBackground()
                    onDismissToBackground?()
                }
            ],
            icon: {
                ZStack {
                    CircularProgressRing(
                        progress: coordinator.progress,
                        lineWidth: 3.5,
                        size: 56,
                        ringColor: .blue,
                        indeterminateWhenZero: true
                    )

                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            },
            message: {
                VStack(spacing: 8) {
                    Text(coordinator.progressLabel)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)

                    if let eta = coordinator.formattedTimeRemaining {
                        Text(eta)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                    }

                    Text("You can leave the app.\nWe'll notify you when it's done.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }
}

struct ShareUploadCompletionDialog: View {
    @ObservedObject var coordinator: ShareUploadCoordinator

    private var isUpdate: Bool {
        coordinator.sourceTape?.lastUploadedClipCount != nil
    }

    var body: some View {
        GlassAlertCard(
            title: isUpdate ? "Shared Tape Updated" : "Tape Shared",
            buttons: [
                GlassAlertButton(title: "Done", style: .primary) {
                    coordinator.dismissCompletionDialog()
                }
            ],
            icon: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.green)
            },
            message: {
                Text(isUpdate
                     ? "All users have been notified."
                     : "Your tape has been uploaded and shared successfully.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
            }
        )
    }
}

struct SharePostUploadDialog: View {
    @ObservedObject var coordinator: ShareUploadCoordinator
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @State private var copiedConfirmation = false
    @State private var shareActivityURL: URL?

    var body: some View {
        GlassAlertCard(
            title: "Link Ready to Share",
            buttons: [
                GlassAlertButton(title: "Cancel", style: .secondary) {
                    coordinator.dismissPostUploadDialog()
                },
                GlassAlertButton(title: "Share Now", style: .primaryFill) {
                    shareActivityURL = coordinator.completedShareURL
                }
            ],
            icon: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.green)
            },
            message: {
                VStack(spacing: 12) {
                    let clipCount = coordinator.lastUploadedClipCount ?? coordinator.totalClips
                    Text("Uploaded \(clipCount) clip\(clipCount == 1 ? "" : "s") successfully.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)

                    if let url = coordinator.completedShareURL {
                        HStack(spacing: 8) {
                            Text(url.absoluteString)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Tokens.Colors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button {
                                UIPasteboard.general.string = url.absoluteString
                                copiedConfirmation = true
                                if let tapeID = coordinator.sourceTape?.id {
                                    entitlementManager.markTapeActivated(tapeID)
                                }
                                let gen = UINotificationFeedbackGenerator()
                                gen.notificationOccurred(.success)
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.6))
                                    copiedConfirmation = false
                                }
                            } label: {
                                Image(systemName: copiedConfirmation ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(copiedConfirmation ? .green : Tokens.Colors.systemBlue)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Tokens.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        )
        .sheet(item: Binding(
            get: { shareActivityURL.map(SharePostUploadURLItem.init) },
            set: { newValue in
                if newValue == nil {
                    shareActivityURL = nil
                    coordinator.dismissPostUploadDialog()
                }
            }
        )) { item in
            SharePostUploadActivityView(url: item.url) { completed, activityType in
                if completed, activityType != nil,
                   let tapeID = coordinator.sourceTape?.id {
                    entitlementManager.markTapeActivated(tapeID)
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct SharePostUploadURLItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SharePostUploadActivityView: UIViewControllerRepresentable {
    let url: URL
    /// Same shape as the inline `ShareActivityView` in `ShareLinkSection` —
    /// fires only when the OS-level share completes with a chosen activity.
    var onCompleted: (_ completed: Bool, _ activityType: UIActivity.ActivityType?) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            onCompleted(completed, activityType)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareUploadErrorAlert: View {
    @ObservedObject var coordinator: ShareUploadCoordinator

    var body: some View {
        GlassAlertCard(
            title: "Upload Failed",
            buttons: [
                GlassAlertButton(title: "Dismiss", style: .secondary) {
                    coordinator.clearError()
                }
            ],
            icon: {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Tokens.Colors.systemRed)
            },
            message: {
                if let error = coordinator.uploadError {
                    Text(error)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }
}
