import SwiftUI
import PhotosUI
import Photos
import os

struct SharedTapeDetailView: View {
    let tapeId: String
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var validation: TapesAPIClient.TapeValidation?
    @State private var manifest: TapeManifest?
    @State private var downloadManager: CloudDownloadManager?
    @State private var uploadManager: CloudUploadManager?
    @State private var isValidating = true
    @State private var errorMessage: String?
    @State private var showingPlayer = false
    @State private var playableTape: Tape?
    @State private var showingCollaborators = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var syncPushResult: String?
    @State private var isSyncPushing = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isSavingToDevice = false
    @State private var saveToDeviceResult: String?

    private var hasAnyCompleted: Bool {
        downloadManager?.activeTasks.contains { if case .completed = $0.state { return true }; return false } ?? false
    }

    private var isCollaborative: Bool {
        validation?.mode == "collaborative"
    }

    private var canContribute: Bool {
        validation?.permissions.canContribute ?? false
    }

    private var isOwnerOrAdmin: Bool {
        let role = validation?.role ?? ""
        return role == "owner" || role == "co-admin"
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
        .toolbar {
            if isCollaborative {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCollaborators = true
                    } label: {
                        Image(systemName: "person.2")
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.Colors.systemBlue)
                    }
                }
            }
        }
        .task {
            await validateAndLoad()
        }
        .refreshable {
            await refreshManifest()
        }
        .fullScreenCover(item: $playableTape) { tape in
            TapePlayerView(tape: tape, onDismiss: {
                playableTape = nil
            })
        }
        .sheet(isPresented: $showingCollaborators) {
            CollaboratorsView(tapeId: tapeId, isOwner: validation?.role == "owner")
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 20,
            matching: .any(of: [.videos, .images, .livePhotos])
        )
        .onChange(of: selectedPhotos) { _, newItems in
            if !newItems.isEmpty {
                Task { await handleContribution(newItems) }
            }
        }
        .alert("Delete Tape", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteTape() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the tape and all its clips for everyone. This cannot be undone.")
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

                if canContribute {
                    contributeSection
                }

                if let um = uploadManager, !um.activeTasks.isEmpty {
                    uploadProgressSection(um)
                }

                downloadProgressSection

                if isOwnerOrAdmin {
                    adminSection
                }

                clipListSection(manifest)

                if let dm = downloadManager, dm.isComplete {
                    saveToDeviceSection
                }

                if validation?.role == "owner" {
                    deleteSection
                }
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

    // MARK: - Contribute Section

    private var contributeSection: some View {
        Button {
            showingPhotoPicker = true
        } label: {
            HStack(spacing: Tokens.Spacing.m) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Tokens.Colors.systemBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Clips")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.primaryText)
                    Text("Contribute photos and videos to this tape")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.tertiaryText)
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Upload Progress

    private func uploadProgressSection(_ um: CloudUploadManager) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            HStack {
                Text("Uploading clips...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.Colors.primaryText)
                Spacer()
                Text("\(Int(um.totalProgress * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Tokens.Colors.secondaryText)
            }

            ProgressView(value: um.totalProgress)
                .tint(Tokens.Colors.systemBlue)

            ForEach(um.activeTasks) { task in
                HStack(spacing: Tokens.Spacing.s) {
                    clipTypeIcon(task.clipType)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.Colors.secondaryText)
                        .frame(width: 20)

                    Text("Clip")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.Colors.secondaryText)

                    Spacer()

                    uploadStateLabel(task.state)
                }
            }
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    @ViewBuilder
    private func uploadStateLabel(_ state: CloudUploadManager.UploadState) -> some View {
        switch state {
        case .idle:
            Text("Waiting")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Colors.tertiaryText)
        case .uploading(let p):
            Text("\(Int(p * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Tokens.Colors.systemBlue)
        case .confirming:
            Text("Confirming")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Colors.secondaryText)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .failed(let msg):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Tokens.Colors.systemRed)
                .font(.system(size: 14))
                .help(msg)
        }
    }

    // MARK: - Admin Section

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Admin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, Tokens.Spacing.xs)

            Button {
                Task { await triggerSyncPush() }
            } label: {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20))
                        .foregroundStyle(isSyncPushing ? Tokens.Colors.tertiaryText : Tokens.Colors.systemBlue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync Push")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Tokens.Colors.primaryText)
                        Text("Notify participants to download pending clips")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Colors.secondaryText)
                    }

                    Spacer()

                    if isSyncPushing {
                        ProgressView()
                            .tint(Tokens.Colors.secondaryText)
                    }
                }
                .padding(Tokens.Spacing.m)
                .background(Tokens.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))
            }
            .buttonStyle(.plain)
            .disabled(isSyncPushing)

            if let result = syncPushResult {
                Text(result)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .padding(.leading, Tokens.Spacing.xs)
            }
        }
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
        let isExpired = clip.cloudUrl == nil && state == nil

        return HStack(spacing: Tokens.Spacing.m) {
            clipTypeIcon(clip.type)
                .font(.system(size: 16))
                .foregroundStyle(isExpired ? Tokens.Colors.tertiaryText : Tokens.Colors.secondaryText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clip \(clip.orderIndex)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isExpired ? Tokens.Colors.tertiaryText : Tokens.Colors.primaryText)

                HStack(spacing: Tokens.Spacing.xs) {
                    if isExpired {
                        Text("Expired")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.systemRed)
                    } else {
                        Text(formatDuration(clip.durationMs))
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Colors.tertiaryText)
                    }

                    if let contributor = clip.contributorName {
                        Text("· \(contributor)")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Colors.tertiaryText)
                    }
                }
            }

            Spacer()

            if isExpired {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Tokens.Colors.tertiaryText)
            } else {
                clipStateIndicator(state)
            }
        }
        .padding(.vertical, Tokens.Spacing.s)
        .padding(.horizontal, Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground)
        .opacity(isExpired ? 0.6 : 1.0)
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

    // MARK: - Save to Device

    private var saveToDeviceSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Button {
                Task { await saveClipsToPhotos() }
            } label: {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundStyle(isSavingToDevice ? Tokens.Colors.tertiaryText : Tokens.Colors.systemBlue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to Device")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Tokens.Colors.primaryText)
                        Text("Save all clips to your Photos library")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Colors.secondaryText)
                    }

                    Spacer()

                    if isSavingToDevice {
                        ProgressView()
                            .tint(Tokens.Colors.secondaryText)
                    }
                }
                .padding(Tokens.Spacing.m)
                .background(Tokens.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))
            }
            .buttonStyle(.plain)
            .disabled(isSavingToDevice)

            if let result = saveToDeviceResult {
                Text(result)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .padding(.leading, Tokens.Spacing.xs)
            }
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.systemRed)
                .textCase(.uppercase)
                .padding(.leading, Tokens.Spacing.xs)

            Button {
                showingDeleteConfirm = true
            } label: {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                        .foregroundStyle(isDeleting ? Tokens.Colors.tertiaryText : Tokens.Colors.systemRed)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete Tape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Tokens.Colors.primaryText)
                        Text("Permanently remove this tape and all its content")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Colors.secondaryText)
                    }

                    Spacer()

                    if isDeleting {
                        ProgressView()
                            .tint(Tokens.Colors.secondaryText)
                    }
                }
                .padding(Tokens.Spacing.m)
                .background(Tokens.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
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

            if v.permissions.canContribute {
                uploadManager = CloudUploadManager(api: api)
            }

            isValidating = false
        } catch {
            log.error("Failed to load shared tape \(tapeId): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isValidating = false
        }
    }

    private func refreshManifest() async {
        guard let api = authManager.apiClient else { return }

        do {
            let m = try await api.getManifest(tapeId: tapeId)
            manifest = m

            downloadManager?.downloadNewClips(tapeId: tapeId, clips: m.clips)
        } catch {
            log.error("Failed to refresh manifest: \(error.localizedDescription)")
        }
    }

    // MARK: - Contribution

    private func handleContribution(_ items: [PhotosPickerItem]) async {
        guard let api = authManager.apiClient,
              let um = uploadManager else { return }

        for item in items {
            do {
                let clipId = UUID().uuidString.lowercased()

                if let videoData = try await item.loadTransferable(type: Data.self) {
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent("\(clipId).mp4")
                    try videoData.write(to: fileURL)

                    um.upload(
                        tapeId: tapeId,
                        clipId: clipId,
                        fileURL: fileURL,
                        thumbnailData: nil,
                        clipType: "video",
                        durationMs: 5000
                    )
                }
            } catch {
                log.error("Failed to process contribution: \(error.localizedDescription)")
            }
        }

        selectedPhotos = []

        try? await Task.sleep(for: .seconds(2))
        await refreshManifest()
    }

    // MARK: - Save to Photos

    private func saveClipsToPhotos() async {
        guard let dm = downloadManager, let manifest = manifest else { return }

        isSavingToDevice = true
        saveToDeviceResult = nil
        var saved = 0

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveToDeviceResult = "Photos access denied."
            isSavingToDevice = false
            return
        }

        for clip in manifest.clips {
            guard let localURL = dm.localURL(for: clip.clipId) else { continue }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    if clip.type == "video" || clip.type == "live_photo" {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
                    } else {
                        if let data = try? Data(contentsOf: localURL),
                           let image = UIImage(data: data) {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }
                    }
                }
                saved += 1
            } catch {
                log.error("Failed to save clip \(clip.clipId): \(error.localizedDescription)")
            }
        }

        saveToDeviceResult = "Saved \(saved) clip\(saved == 1 ? "" : "s") to Photos."
        isSavingToDevice = false
    }

    // MARK: - Delete Tape

    private func deleteTape() async {
        guard let api = authManager.apiClient else { return }

        isDeleting = true

        do {
            try await api.deleteTape(tapeId: tapeId)
            CloudDownloadManager.clearCache(for: tapeId)
            dismiss()
        } catch {
            log.error("Failed to delete tape: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }

    // MARK: - Sync Push

    private func triggerSyncPush() async {
        guard let api = authManager.apiClient else { return }

        isSyncPushing = true
        syncPushResult = nil

        do {
            let result = try await api.syncPush(tapeId: tapeId)
            await MainActor.run {
                syncPushResult = "Notified \(result.notifiedCount) participant\(result.notifiedCount == 1 ? "" : "s")."
                isSyncPushing = false
            }
        } catch {
            log.error("Sync push failed: \(error.localizedDescription)")
            await MainActor.run {
                syncPushResult = error.localizedDescription
                isSyncPushing = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        SharedTapeDetailView(tapeId: "test-tape-id")
            .environmentObject(AuthManager())
    }
}
