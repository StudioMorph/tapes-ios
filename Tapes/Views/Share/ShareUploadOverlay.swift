import SwiftUI

struct ShareUploadProgressDialog: View {
    @ObservedObject var coordinator: ShareUploadCoordinator

    var body: some View {
        GlassAlertCard(
            title: "Sharing Tape…",
            buttons: [
                GlassAlertButton(title: "Cancel", style: .destructive) {
                    coordinator.cancelUpload()
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

                    Text("You can leave the app — we'll notify you when it's done.")
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

    var body: some View {
        GlassAlertCard(
            systemImage: "checkmark.circle",
            title: "Tape Shared",
            message: "Your tape has been uploaded and shared successfully.",
            buttons: [
                GlassAlertButton(title: "Done", style: .primary) {
                    coordinator.dismissCompletionDialog()
                }
            ]
        )
    }
}

struct ShareUploadErrorAlert: View {
    @ObservedObject var coordinator: ShareUploadCoordinator

    var body: some View {
        EmptyView()
            .alert("Upload Failed", isPresented: Binding(
                get: { coordinator.uploadError != nil },
                set: { if !$0 { coordinator.clearError() } }
            )) {
                Button("Retry") {
                    coordinator.clearError()
                }
                Button("Cancel", role: .cancel) {
                    coordinator.clearError()
                    coordinator.cancelUpload()
                }
            } message: {
                if let error = coordinator.uploadError {
                    Text(error)
                }
            }
    }
}
