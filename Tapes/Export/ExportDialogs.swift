import SwiftUI

// MARK: - Circular Progress Ring

struct CircularProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3
    var size: CGFloat = 56
    var trackColor: Color = Color.gray.opacity(0.3)
    var ringColor: Color = Tokens.Colors.systemRed

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Export Progress Dialog

struct ExportProgressDialog: View {
    @ObservedObject var coordinator: ExportCoordinator

    var body: some View {
        switch coordinator.dialogState {
        case .preparing:
            preparingDialog
        case .paused:
            pausedDialog
        case .exporting:
            exportingDialog
        }
    }

    // MARK: - Preparing (Phase 1 active)

    private var preparingDialog: some View {
        GlassAlertCard(
            title: "Preparing your tape…",
            buttons: [
                GlassAlertButton(title: "Cancel Export", style: .destructive) {
                    coordinator.cancelExport()
                }
            ],
            icon: {
                ZStack {
                    CircularProgressRing(
                        progress: coordinator.progress,
                        lineWidth: 3.5,
                        size: 56,
                        ringColor: .green
                    )

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            },
            message: {
                Text("Please keep the app open during this step.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    // MARK: - Paused (returned from background during Phase 1)

    private var pausedDialog: some View {
        GlassAlertCard(
            title: "Export Paused",
            buttons: [
                GlassAlertButton(title: "Cancel Export", style: .destructive) {
                    coordinator.cancelExport()
                },
                GlassAlertButton(title: "Resume", style: .primaryFill) {
                    coordinator.resumeFromPause()
                }
            ],
            icon: {
                Image(systemName: "pause.circle")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.primary)
            },
            message: {
                Text("Your progress has been saved — pick up where you left off.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    // MARK: - Exporting (Phase 2 with ETA)

    private var exportingDialog: some View {
        GlassAlertCard(
            title: "Exporting…",
            buttons: [
                GlassAlertButton(title: "Cancel Export", style: .destructive) {
                    coordinator.cancelExport()
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
                        ringColor: .green
                    )

                    Image(systemName: "arrow.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            },
            message: {
                VStack(spacing: 8) {
                    if let eta = coordinator.formattedTimeRemaining {
                        Text(eta)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary)
                    }

                    Text("You can leave the app — we'll notify you when it's saved.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }
}

// MARK: - Export Completion Dialog

struct ExportCompletionDialog: View {
    @ObservedObject var coordinator: ExportCoordinator

    var body: some View {
        GlassAlertCard(
            systemImage: "video.badge.checkmark",
            title: "Tape merged and saved",
            message: "Your video has been saved to photos",
            buttons: [
                GlassAlertButton(title: "Done", style: .secondary) {
                    coordinator.dismissCompletionDialog()
                },
                GlassAlertButton(title: "Show in Photos", style: .primary) {
                    coordinator.showInPhotos()
                }
            ]
        )
    }
}

// MARK: - Export Error Alert

struct ExportErrorAlert: View {
    @ObservedObject var coordinator: ExportCoordinator

    var body: some View {
        EmptyView()
            .alert("Export Failed", isPresented: Binding(
                get: { coordinator.exportError != nil },
                set: { if !$0 { coordinator.clearError() } }
            )) {
                Button("OK") {
                    coordinator.clearError()
                }
            } message: {
                if let error = coordinator.exportError {
                    Text(error)
                }
            }
    }
}
