import SwiftUI
import os

struct SharedTapeDetailView: View {
    let tapeId: String
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var validation: TapesAPIClient.TapeValidation?
    @State private var manifest: TapeManifest?
    @State private var downloadManager: CloudDownloadManager?
    @State private var isValidating = true
    @State private var errorMessage: String?
    @State private var showingPlayer = false
    @State private var playableTape: Tape?

    private var hasAnyCompleted: Bool {
        downloadManager?.activeTasks.contains { if case .completed = $0.state { return true }; return false } ?? false
    }

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "SharedDetail")

    var body: some View {
        Group {
            if isValidating {
                validatingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let manifest = manifest {
                tapeContentView(manifest)
            }
        }
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle(validation?.title ?? "Shared Tape")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await validateAndLoad()
        }
        .fullScreenCover(item: $playableTape) { tape in
            TapePlayerView(tape: tape, onDismiss: {
                playableTape = nil
            })
        }
    }

    // MARK: - Validating

    private var validatingView: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(Tokens.Colors.secondaryText)
            Text("Loading tape...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.systemRed)

            Text("Unable to Load Tape")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Tokens.Colors.primaryText)

            Text(message)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            Button("Try Again") {
                Task { await validateAndLoad() }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Tokens.Colors.systemBlue)

            Spacer()
        }
    }

    // MARK: - Tape Content

    private func tapeContentView(_ manifest: TapeManifest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
                tapeHeader(manifest)
                downloadProgressSection
                clipListSection(manifest)
            }
            .padding(.horizontal, Tokens.Spacing.l)
            .padding(.top, Tokens.Spacing.m)
            .padding(.bottom, Tokens.Spacing.xxl)
        }
    }

    // MARK: - Header

    private func tapeHeader(_ manifest: TapeManifest) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let ownerName = manifest.ownerName {
                        Text("by \(ownerName)")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Colors.secondaryText)
                    }

                    HStack(spacing: Tokens.Spacing.m) {
                        Label("\(manifest.clips.count) clips", systemImage: "film")
                        Label(manifest.mode == "view_only" ? "View Only" : "Collaborative",
                              systemImage: manifest.mode == "view_only" ? "eye" : "person.2")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.Colors.tertiaryText)
                }

                Spacer()

                if let dm = downloadManager, dm.isComplete || hasAnyCompleted {
                    Button {
                        if let tape = SharedTapeBuilder.buildTape(from: manifest, downloadManager: dm) {
                            playableTape = tape
                        }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Tokens.Colors.systemBlue)
                            .clipShape(Circle())
                    }
                }
            }

            if let expiresAt = manifest.expiresAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("Expires: \(expiresAt)")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Tokens.Colors.tertiaryText)
            }
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - Download Progress

    @ViewBuilder
    private var downloadProgressSection: some View {
        if let dm = downloadManager, dm.hasActiveDownloads {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                HStack {
                    Text("Downloading clips...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.Colors.primaryText)
                    Spacer()
                    Text("\(Int(dm.totalProgress * 100))%")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }

                ProgressView(value: dm.totalProgress)
                    .tint(Tokens.Colors.systemBlue)
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        } else if let dm = downloadManager, dm.isComplete {
            HStack(spacing: Tokens.Spacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("All clips downloaded")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.Colors.primaryText)
                Spacer()
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    // MARK: - Clip List

    private func clipListSection(_ manifest: TapeManifest) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Clips")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .textCase(.uppercase)

            ForEach(manifest.clips) { clip in
                clipRow(clip)
            }
        }
    }

    private func clipRow(_ clip: ManifestClip) -> some View {
        let state = downloadManager?.activeTasks.first(where: { $0.clipId == clip.clipId })?.state

        return HStack(spacing: Tokens.Spacing.m) {
            clipTypeIcon(clip.type)
                .font(.system(size: 16))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clip \(clip.orderIndex)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.Colors.primaryText)

                Text(formatDuration(clip.durationMs))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.tertiaryText)
            }

            Spacer()

            clipStateIndicator(state)
        }
        .padding(.vertical, Tokens.Spacing.s)
        .padding(.horizontal, Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))
    }

    @ViewBuilder
    private func clipTypeIcon(_ type: String) -> some View {
        switch type {
        case "video":
            Image(systemName: "video.fill")
        case "live_photo":
            Image(systemName: "livephoto")
        default:
            Image(systemName: "photo")
        }
    }

    @ViewBuilder
    private func clipStateIndicator(_ state: CloudDownloadManager.DownloadState?) -> some View {
        switch state {
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 40)
                .tint(Tokens.Colors.systemBlue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Tokens.Colors.systemRed)
                .help(msg)
        default:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(Tokens.Colors.tertiaryText)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Data Loading

    private func validateAndLoad() async {
        guard let api = authManager.apiClient else {
            errorMessage = "Not signed in."
            isValidating = false
            return
        }

        isValidating = true
        errorMessage = nil

        do {
            let v = try await api.validateTape(tapeId: tapeId)
            validation = v

            let m = try await api.getManifest(tapeId: tapeId)
            manifest = m

            let dm = CloudDownloadManager(api: api)
            downloadManager = dm
            dm.downloadTape(tapeId: tapeId, manifest: m)

            isValidating = false
        } catch {
            log.error("Failed to load shared tape \(tapeId): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isValidating = false
        }
    }
}

#Preview {
    NavigationStack {
        SharedTapeDetailView(tapeId: "test-tape-id")
            .environmentObject(AuthManager())
    }
}
