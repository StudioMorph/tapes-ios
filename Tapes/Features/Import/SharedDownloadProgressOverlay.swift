import SwiftUI

struct SharedDownloadProgressOverlay: View {
    @ObservedObject var coordinator: SharedTapeDownloadCoordinator

    var body: some View {
        if coordinator.isDownloading && coordinator.showProgressDialog {
            GlassAlertCard(
                title: coordinator.progressLabel,
                buttons: [
                    GlassAlertButton(title: "OK", style: .secondary) {
                        coordinator.dismissProgressDialog()
                    },
                    GlassAlertButton(title: "Cancel", style: .destructive) {
                        coordinator.cancelDownload()
                    }
                ],
                icon: {
                    ZStack {
                        CircularProgressRing(
                            progress: coordinator.progress,
                            lineWidth: 3.5,
                            size: 56,
                            ringColor: .blue
                        )

                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                },
                message: {
                    EmptyView()
                }
            )
        }
    }
}
