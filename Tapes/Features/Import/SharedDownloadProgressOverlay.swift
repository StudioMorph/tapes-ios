import SwiftUI

struct SharedDownloadProgressOverlay: View {
    @ObservedObject var coordinator: SharedTapeDownloadCoordinator
    var title: String = "Downloading…"

    var body: some View {
        if coordinator.isDownloading && coordinator.showProgressDialog {
            GlassAlertCard(
                title: title,
                buttons: [
                    GlassAlertButton(title: "Cancel", style: .destructive) {
                        coordinator.cancelDownload()
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

                        Image(systemName: "arrow.down")
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
}
