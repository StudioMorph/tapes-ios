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
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    ZStack {
                        CircularProgressRing(
                            progress: coordinator.progress,
                            lineWidth: 3.5,
                            size: 56
                        )

                        Image(systemName: "arrow.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.top, 4)

                    VStack(spacing: 6) {
                        Text("Merging Tape…")
                            .font(.system(size: 17, weight: .semibold))

                        if let eta = coordinator.formattedTimeRemaining {
                            Text(eta)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Preparing…")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("You can dismiss this — merging will continue in the background.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                HStack(spacing: 0) {
                    Button {
                        coordinator.cancelExport()
                    } label: {
                        Text("Cancel Merge")
                            .font(.system(size: 17))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }

                    Divider()
                        .frame(height: 44)

                    Button {
                        coordinator.dismissProgressDialog()
                    } label: {
                        Text("OK")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(width: 270)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }
}

// MARK: - Export Completion Dialog

struct ExportCompletionDialog: View {
    @ObservedObject var coordinator: ExportCoordinator

    var body: some View {
        GlassAlertCard(
            icon: "video.badge.checkmark",
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
            .alert("Export Failed", isPresented: .constant(coordinator.exportError != nil)) {
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
