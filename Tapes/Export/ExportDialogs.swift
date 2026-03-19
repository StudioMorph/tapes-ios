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
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 10) {
                Image(systemName: "video.badge.checkmark")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(height: 87)

                VStack(spacing: 10) {
                    Text("Tape merged and saved")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)

                    Text("Your video has been saved to photos")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
                .padding(.horizontal, 8)

                HStack(spacing: 16) {
                    Button {
                        coordinator.dismissCompletionDialog()
                    } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .frame(height: 48)
                            .frame(minWidth: 108)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray4).opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        coordinator.showInPhotos()
                    } label: {
                        Text("Show in Photos")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0, green: 0.533, blue: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 40, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: 340)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
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
