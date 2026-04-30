import SwiftUI
import AVFoundation

// MARK: - Filter Bar (used by BackgroundMusicSheet in the bar area)

struct LibraryFilterBar: View {
    @ObservedObject var viewModel: LibraryBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.s) {
                    ForEach(viewModel.displayFilters) { filter in
                        FilterMenuButton(
                            filter: filter,
                            displayName: viewModel.displayName(for: filter.param),
                            selectedValue: binding(for: filter.param),
                            onChange: { viewModel.requestTrackReload = true }
                        )
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

    private func binding(for param: String) -> Binding<String?> {
        Binding(
            get: { viewModel.activeFilters[param] },
            set: { newValue in
                if let newValue {
                    viewModel.activeFilters[param] = newValue
                } else {
                    viewModel.activeFilters.removeValue(forKey: param)
                }
            }
        )
    }
}

private struct FilterMenuButton: View {
    let filter: TapesAPIClient.LibraryParam
    let displayName: String
    @Binding var selectedValue: String?
    let onChange: () -> Void

    var body: some View {
        Menu {
            Picker(displayName, selection: $selectedValue) {
                Text("All").tag(String?.none)
                ForEach(filter.values) { value in
                    Text("\(value.value) (\(value.tracksCount))")
                        .tag(String?.some(value.value))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedValue ?? displayName)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .frame(minHeight: 28)
            .padding(.horizontal, 4)
        }
        .modifier(GlassPillStyle())
        .onChange(of: selectedValue) { _, _ in onChange() }
    }
}

private struct GlassPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// Bottom safe-area bar that promotes the upgrade-to-Plus action when
/// the Free-tier track cap is in effect. Sits below the scroll content
/// and above the system home indicator. Hidden for Plus users.
private struct UpgradeBottomBar: ViewModifier {
    let visible: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if visible {
            if #available(iOS 26.0, *) {
                content.safeAreaBar(edge: .bottom) { bar }
            } else {
                content.safeAreaInset(edge: .bottom, spacing: 0) {
                    bar.background(.bar)
                }
            }
        } else {
            content
        }
    }

    private var bar: some View {
        Button(action: onTap) {
            HStack(spacing: Tokens.Spacing.s) {
                Text("Upgrade to unlock 12,000 tracks")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Spacing.s)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(Tokens.Colors.systemBlue)
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
    }
}

// MARK: - Library Browser View

struct LibraryBrowserView: View {
    @Binding var tape: Tape
    @ObservedObject var viewModel: LibraryBrowserViewModel
    let onTrackSelected: () -> Void
    /// Called by the bottom upgrade toolbar (Free tier only). Hosts use
    /// this to flip their `showingPaywall` state.
    var onUpgradeTapped: () -> Void = {}

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore
    @EnvironmentObject private var entitlementManager: EntitlementManager

    private var inUseTrackID: String? {
        guard let mood = tape.backgroundMusicMood,
              mood.hasPrefix("library:") else { return nil }
        return String(mood.dropFirst("library:".count))
    }

    /// Number of tracks the current tier can browse. `nil` for Plus.
    private var trackCap: Int? { entitlementManager.libraryTrackCap }

    /// Whether to show the bottom upgrade toolbar. Free tier only.
    private var showsUpgradeToolbar: Bool { trackCap != nil }

    var body: some View {
        Group {
            if viewModel.isLoadingParams {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(spacing: Tokens.Spacing.s) {
                        trackListContent
                    }
                    .padding(Tokens.Spacing.m)
                }
            }
        }
        .modifier(UpgradeBottomBar(visible: showsUpgradeToolbar, onTap: onUpgradeTapped))
        .task {
            guard let api = authManager.apiClient else { return }
            if viewModel.availableFilters.isEmpty {
                await viewModel.loadParams(api: api)
            }
            if viewModel.tracks.isEmpty {
                await viewModel.loadTracks(api: api, trackCap: trackCap)
            }
        }
        .onChange(of: viewModel.requestTrackReload) { _, reload in
            if reload {
                viewModel.requestTrackReload = false
                Task {
                    guard let api = authManager.apiClient else { return }
                    // Refresh both: params (so chip visibility updates with
                    // the new context) and tracks (the actual list).
                    async let params: Void = viewModel.loadParams(api: api)
                    async let list: Void = viewModel.loadTracks(api: api, reset: true, trackCap: trackCap)
                    _ = await (params, list)
                }
            }
        }
        .onDisappear {
            viewModel.stopPlayback()
            viewModel.expandedTrackID = nil
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
            let isInUse = track.id == inUseTrackID
            LibraryTrackRow(
                track: track,
                isExpanded: viewModel.expandedTrackID == track.id || isInUse,
                isPlaying: viewModel.playingTrackID == track.id,
                isInUse: isInUse,
                isCommitting: viewModel.committingTrackID == track.id,
                onTap: { viewModel.selectTrack(track) },
                onTogglePreview: { viewModel.togglePlayback(for: track) },
                onUse: { Task { await commitTrack(track) } }
            )
            .onAppear {
                if track.id == viewModel.tracks.last?.id {
                    Task {
                        guard let api = authManager.apiClient else { return }
                        await viewModel.loadMore(api: api, trackCap: trackCap)
                    }
                }
            }
        }

        if viewModel.isLoadingTracks {
            ProgressView()
                .padding(Tokens.Spacing.l)
        }
    }

    // MARK: - Actions

    private func commitTrack(_ track: TapesAPIClient.LibraryTrack) async {
        guard let streamURL = track.streamURL else { return }

        viewModel.stopPlayback()
        viewModel.committingTrackID = track.id
        defer { viewModel.committingTrackID = nil }

        do {
            _ = try await MubertAPIClient.shared.downloadLibraryTrack(
                from: streamURL,
                tapeID: tape.id
            )
            tape.backgroundMusicMood = "library:\(track.id)"
            tape.backgroundMusicPrompt = nil
            if tape.waveColorHue == nil {
                tape.waveColorHue = Double.random(in: 0...1)
            }
            // Mutating the @Binding writes back into TapesStore.tapes[i]
            // and updates the UI, but TapesStore only persists when one
            // of its mutator methods explicitly schedules a save.
            // updateTape replays the current value through that path.
            tapesStore.updateTape(tape)
            onTrackSelected()
        } catch {
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
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
    @Published var committingTrackID: String?

    private var currentOffset = 0
    private var hasMore = true
    private var player: AVPlayer?

    // MARK: - Filter Customisation

    /// Params that we don't show in the filter bar.
    private static let hiddenParams: Set<String> = ["mode", "key"]

    /// User-facing names for raw API param keys.
    private static let paramDisplayNames: [String: String] = [
        "bpm": "Tempo",
        "playlists": "Vibes"
    ]

    private struct BPMBucket {
        let label: String
        let lowerInclusive: Int
        let upperInclusive: Int

        func contains(_ bpm: Int) -> Bool {
            bpm >= lowerInclusive && bpm <= upperInclusive
        }
    }

    private static let bpmBuckets: [BPMBucket] = [
        BPMBucket(label: "Slow", lowerInclusive: 0, upperInclusive: 99),
        BPMBucket(label: "Medium", lowerInclusive: 100, upperInclusive: 130),
        BPMBucket(label: "Fast", lowerInclusive: 131, upperInclusive: 1000)
    ]

    func displayName(for param: String) -> String {
        Self.paramDisplayNames[param] ?? param.capitalized
    }

    /// Filter pills shown in the UI. Hides Mode/Key, replaces BPM values
    /// with 3 buckets, drops any individual value with `tracksCount == 0`,
    /// and drops the whole category if no values remain. Re-evaluated
    /// every time `availableFilters` is refreshed (which happens on each
    /// filter change), so categories disappear / reappear in step with
    /// the user's current selection.
    var displayFilters: [TapesAPIClient.LibraryParam] {
        availableFilters
            .filter { !Self.hiddenParams.contains($0.param) }
            .compactMap { filter -> TapesAPIClient.LibraryParam? in
                let trimmed: [TapesAPIClient.LibraryParamValue] = {
                    if filter.param == "bpm" {
                        return Self.bucketedBPMValues(from: filter.values)
                    }
                    return filter.values.filter { $0.tracksCount > 0 }
                }()
                guard !trimmed.isEmpty else { return nil }
                return TapesAPIClient.LibraryParam(param: filter.param, values: trimmed)
            }
    }

    private static func bucketedBPMValues(from rawValues: [TapesAPIClient.LibraryParamValue]) -> [TapesAPIClient.LibraryParamValue] {
        bpmBuckets.compactMap { bucket in
            let count = rawValues
                .compactMap { Int($0.value) != nil ? $0 : nil }
                .filter { Int($0.value).map(bucket.contains) ?? false }
                .reduce(0) { $0 + $1.tracksCount }
            guard count > 0 else { return nil }
            return TapesAPIClient.LibraryParamValue(value: bucket.label, tracksCount: count)
        }
    }

    /// Converts the user-facing active filters into the raw query params Mubert expects.
    /// For BPM buckets, expands the bucket label back into the actual BPM values.
    private var apiFilters: [String: String] {
        var result: [String: String] = [:]
        for (param, value) in activeFilters {
            if param == "bpm",
               let bucket = Self.bpmBuckets.first(where: { $0.label == value }),
               let rawBPM = availableFilters.first(where: { $0.param == "bpm" }) {
                let matches = rawBPM.values
                    .compactMap { Int($0.value) }
                    .filter(bucket.contains)
                    .map(String.init)
                if !matches.isEmpty {
                    result[param] = matches.joined(separator: ",")
                }
            } else {
                result[param] = value
            }
        }
        return result
    }

    // MARK: - Loading

    func loadParams(api: TapesAPIClient) async {
        isLoadingParams = true
        defer { isLoadingParams = false }

        do {
            availableFilters = try await api.fetchLibraryParams(filters: apiFilters)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Loads the next page of tracks. Respects an optional `trackCap`
    /// (Free-tier limit): once the loaded count reaches the cap, the
    /// remaining server-side tracks are simply not fetched. Filter counts
    /// returned by the params endpoint are unchanged — we still tell Free
    /// users the true library size, just don't surface the tracks.
    func loadTracks(api: TapesAPIClient, reset: Bool = false, trackCap: Int? = nil) async {
        if reset {
            currentOffset = 0
            tracks = []
            hasMore = true
        }
        guard hasMore, !isLoadingTracks else { return }

        if let cap = trackCap, tracks.count >= cap {
            hasMore = false
            return
        }

        isLoadingTracks = true
        defer { isLoadingTracks = false }

        let pageSize = 50
        let limit: Int
        if let cap = trackCap {
            limit = max(1, min(pageSize, cap - tracks.count))
        } else {
            limit = pageSize
        }

        do {
            let response = try await api.fetchLibraryTracks(
                filters: apiFilters,
                offset: currentOffset,
                limit: limit
            )
            tracks.append(contentsOf: response.data)
            totalTracks = response.meta?.total
            currentOffset += response.data.count
            hasMore = response.data.count == limit
            if let cap = trackCap, tracks.count >= cap {
                hasMore = false
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func loadMore(api: TapesAPIClient, trackCap: Int? = nil) async {
        await loadTracks(api: api, trackCap: trackCap)
    }

    func toggleFilter(param: String, value: String) {
        if activeFilters[param] == value {
            activeFilters.removeValue(forKey: param)
        } else {
            activeFilters[param] = value
        }
    }

    /// Tap on the cell body. Opens the tapped cell, starts preview, and
    /// closes any previously expanded (non-in-use) cell.
    func selectTrack(_ track: TapesAPIClient.LibraryTrack) {
        guard expandedTrackID != track.id else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedTrackID = track.id
        }
        startPlayback(for: track)
    }

    /// Tap on the icon. Toggles preview; cell stays open.
    func togglePlayback(for track: TapesAPIClient.LibraryTrack) {
        if playingTrackID == track.id {
            stopPlayback()
        } else {
            startPlayback(for: track)
        }
    }

    private func startPlayback(for track: TapesAPIClient.LibraryTrack) {
        stopPlayback()
        guard let url = track.streamURL else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        playingTrackID = track.id
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        playingTrackID = nil
    }

    deinit {
        player?.pause()
    }
}
