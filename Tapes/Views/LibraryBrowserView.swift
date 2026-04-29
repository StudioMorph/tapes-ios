import SwiftUI
import AVFoundation

// MARK: - Filter Bar (used by BackgroundMusicSheet in the bar area)

struct LibraryFilterBar: View {
    @ObservedObject var viewModel: LibraryBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.s) {
                    ForEach(viewModel.availableFilters) { filter in
                        Menu {
                            ForEach(filter.values) { value in
                                Button {
                                    viewModel.toggleFilter(param: filter.param, value: value.value)
                                    viewModel.requestTrackReload = true
                                } label: {
                                    HStack {
                                        Text("\(value.value) (\(value.tracksCount))")
                                        if viewModel.activeFilters[filter.param] == value.value {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            filterPill(
                                title: viewModel.activeFilters[filter.param] ?? filter.param.capitalized,
                                isActive: viewModel.activeFilters[filter.param] != nil
                            )
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.s)
            }

            HStack {
                if let total = viewModel.totalTracks {
                    Text("\(total) tracks")
                        .font(.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.bottom, Tokens.Spacing.xs)
        }
    }

    private func filterPill(title: String, isActive: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Tokens.Colors.systemBlue.opacity(0.15) : Tokens.Colors.secondaryBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Tokens.Colors.systemBlue : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Tokens.Colors.systemBlue : Tokens.Colors.primaryText)
    }
}

// MARK: - Library Browser View

struct LibraryBrowserView: View {
    @Binding var tape: Tape
    @ObservedObject var viewModel: LibraryBrowserViewModel
    let onTrackSelected: () -> Void

    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            if viewModel.isLoadingParams {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        trackListContent
                    }
                }
            }
        }
        .task {
            guard let api = authManager.apiClient else { return }
            if viewModel.availableFilters.isEmpty {
                await viewModel.loadParams(api: api)
            }
            if viewModel.tracks.isEmpty {
                await viewModel.loadTracks(api: api)
            }
        }
        .onChange(of: viewModel.requestTrackReload) { _, reload in
            if reload {
                viewModel.requestTrackReload = false
                Task {
                    guard let api = authManager.apiClient else { return }
                    await viewModel.loadTracks(api: api, reset: true)
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Track List

    @ViewBuilder
    private var trackListContent: some View {
        ForEach(viewModel.tracks) { track in
            trackRow(track)
                .onAppear {
                    if track.id == viewModel.tracks.last?.id {
                        Task {
                            guard let api = authManager.apiClient else { return }
                            await viewModel.loadMore(api: api)
                        }
                    }
                }
        }

        if viewModel.isLoadingTracks {
            ProgressView()
                .padding(Tokens.Spacing.l)
        }
    }

    private func trackRow(_ track: TapesAPIClient.LibraryTrack) -> some View {
        let isExpanded = viewModel.expandedTrackID == track.id
        let isPlaying = viewModel.playingTrackID == track.id

        return VStack(spacing: 0) {
            Button {
                viewModel.selectTrack(track)
            } label: {
                HStack(spacing: 12) {
                    waveformIcon(for: track, isPlaying: isPlaying)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Tokens.Colors.primaryText)
                            .lineLimit(1)

                        trackTags(track)
                    }

                    Spacer()

                    Button {
                        viewModel.togglePlayback(for: track)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Tokens.Colors.systemBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedSection(track)
            }

            Divider()
                .padding(.leading, Tokens.Spacing.m + 36)
        }
    }

    private func waveformIcon(for track: TapesAPIClient.LibraryTrack, isPlaying: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(waveformGradient(for: track))
                .frame(width: 36, height: 36)

            Image(systemName: isPlaying ? "waveform" : "music.note")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private func waveformGradient(for track: TapesAPIClient.LibraryTrack) -> LinearGradient {
        let hue = Double(abs(track.id.hashValue)) / Double(Int.max)
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.6, brightness: 0.7),
                     Color(hue: hue + 0.1, saturation: 0.5, brightness: 0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func trackTags(_ track: TapesAPIClient.LibraryTrack) -> some View {
        HStack(spacing: 6) {
            if let bpm = track.bpm {
                tagLabel("\(bpm) BPM")
            }
            if let key = track.key {
                tagLabel(key)
            }
            if let duration = track.duration {
                tagLabel(formatDuration(duration))
            }
            if let intensity = track.intensity {
                tagLabel(intensity.capitalized)
            }
        }
    }

    private func tagLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Tokens.Colors.secondaryText)
    }

    private func expandedSection(_ track: TapesAPIClient.LibraryTrack) -> some View {
        VStack(spacing: 10) {
            if viewModel.playingTrackID == track.id {
                ProgressView(value: viewModel.playbackProgress)
                    .tint(Tokens.Colors.systemBlue)
                    .padding(.horizontal, Tokens.Spacing.m)
            }

            Button {
                Task { await selectLibraryTrack(track) }
            } label: {
                Text("Use this track")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Tokens.Colors.systemBlue, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .disabled(viewModel.isDownloading)
            .overlay {
                if viewModel.isDownloading {
                    ProgressView()
                }
            }
        }
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Actions

    private func selectLibraryTrack(_ track: TapesAPIClient.LibraryTrack) async {
        guard let streamURL = track.streamURL else { return }

        viewModel.isDownloading = true
        defer { viewModel.isDownloading = false }

        do {
            let localURL = try await MubertAPIClient.shared.downloadLibraryTrack(
                from: streamURL,
                tapeID: tape.id
            )
            tape.backgroundMusicMood = "library:\(track.id)"
            if tape.waveColorHue == nil {
                tape.waveColorHue = Double.random(in: 0...1)
            }
            _ = localURL
            onTrackSelected()
        } catch {
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - ViewModel

@MainActor
final class LibraryBrowserViewModel: ObservableObject {
    @Published var availableFilters: [TapesAPIClient.LibraryParam] = []
    @Published var activeFilters: [String: String] = [:]
    @Published var tracks: [TapesAPIClient.LibraryTrack] = []
    @Published var totalTracks: Int?
    @Published var isLoadingParams = false
    @Published var isLoadingTracks = false
    @Published var isDownloading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var requestTrackReload = false

    @Published var expandedTrackID: String?
    @Published var playingTrackID: String?
    @Published var playbackProgress: Double = 0

    private var currentOffset = 0
    private var hasMore = true
    private var player: AVPlayer?
    private var timeObserver: Any?

    func loadParams(api: TapesAPIClient) async {
        isLoadingParams = true
        defer { isLoadingParams = false }

        do {
            availableFilters = try await api.fetchLibraryParams(filters: activeFilters)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func loadTracks(api: TapesAPIClient, reset: Bool = false) async {
        if reset {
            currentOffset = 0
            tracks = []
            hasMore = true
        }
        guard hasMore, !isLoadingTracks else { return }

        isLoadingTracks = true
        defer { isLoadingTracks = false }

        do {
            let response = try await api.fetchLibraryTracks(
                filters: activeFilters,
                offset: currentOffset,
                limit: 50
            )
            tracks.append(contentsOf: response.data)
            totalTracks = response.meta?.total
            currentOffset += response.data.count
            hasMore = response.data.count == 50
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func loadMore(api: TapesAPIClient) async {
        await loadTracks(api: api)
    }

    func toggleFilter(param: String, value: String) {
        if activeFilters[param] == value {
            activeFilters.removeValue(forKey: param)
        } else {
            activeFilters[param] = value
        }
    }

    func selectTrack(_ track: TapesAPIClient.LibraryTrack) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedTrackID = expandedTrackID == track.id ? nil : track.id
        }
    }

    func togglePlayback(for track: TapesAPIClient.LibraryTrack) {
        if playingTrackID == track.id {
            stopPlayback()
            return
        }

        stopPlayback()
        guard let url = track.streamURL else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        playingTrackID = track.id
        expandedTrackID = track.id

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, let duration = self.player?.currentItem?.duration,
                  duration.isValid, !duration.isIndefinite else { return }
            self.playbackProgress = time.seconds / duration.seconds
        }
    }

    func stopPlayback() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playingTrackID = nil
        playbackProgress = 0
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
    }
}
