import SwiftUI

struct CollabSyncProgressDialog: View {
    @ObservedObject var coordinator: CollabSyncCoordinator

    var body: some View {
        GlassAlertCard(
            title: "Syncing Contributions…",
            buttons: [
                GlassAlertButton(title: "Cancel", style: .destructive) {
                    coordinator.cancelSync()
                },
                GlassAlertButton(title: "OK", style: .primaryFill) {
                    coordinator.dismissProgressDialog()
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

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .semibold))
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

struct CollabSyncCompletionDialog: View {
    @ObservedObject var coordinator: CollabSyncCoordinator

    var body: some View {
        GlassAlertCard(
            title: "Tape Synced",
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
                Text("All clips are up to date.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
            }
        )
    }
}

struct CollabSyncErrorAlert: View {
    @ObservedObject var coordinator: CollabSyncCoordinator

    var body: some View {
        GlassAlertCard(
            title: "Sync Failed",
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
                if let error = coordinator.syncError {
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
