import SwiftUI

struct ImportProgressOverlay: View {
    @ObservedObject var coordinator: MediaImportCoordinator

    var body: some View {
        if coordinator.isImporting {
            GlassAlertCard(
                title: coordinator.progressLabel,
                buttons: [
                    GlassAlertButton(title: "Cancel", style: .destructive) {
                        coordinator.cancelImport()
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

                        Image(systemName: "photo.stack")
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
