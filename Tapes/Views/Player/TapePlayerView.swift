import SwiftUI
import AVFoundation
import AVKit

struct TapePlayerView: View {
    @StateObject private var vm: TapePlayerViewModel
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.scenePhase) private var scenePhase
    let onDismiss: () -> Void
    let onSave: ((Tape) -> Void)?

    private let startAtClip: Int

    init(tape: Tape, startAtClip: Int = 0, onDismiss: @escaping () -> Void, onSave: ((Tape) -> Void)? = nil) {
        _vm = StateObject(wrappedValue: TapePlayerViewModel(tape: tape))
        self.startAtClip = startAtClip
        self.onDismiss = onDismiss
        self.onSave = onSave
    }

    // MARK: - Body

    var body: some View {
        playerContent
    }

    private var playerContent: some View {
        Color.clear
            .background { mediaLayer }
            .contentShape(Rectangle())
            .onTapGesture {
                if !vm.isAdPlaying { vm.toggleControls() }
            }
            .gesture(vm.isAdPlaying ? nil : swipeGesture)
            .overlay { vm.isAdPlaying ? nil : controlsOverlay }
            .overlay { adCloseButton }
            .overlay { toastLayer }
            .overlay { loadingLayer }
            .overlay { offlineAdLayer }
            .onAppear {
                startPlayback(from: startAtClip)
            }
            .onDisappear {
                AdManager.shared.tearDown()
                vm.shutdown()
            }
            .onChange(of: scenePhase) { _, newPhase in
                vm.handleScenePhaseChange(newPhase)
            }
    }

    @ViewBuilder
    private var offlineAdLayer: some View {
        if vm.showOfflineAdView {
            OfflineAdView(onCountdownFinished: { vm.offlineCountdownFinished() })
                .transition(.opacity)
        }
    }

    // MARK: - Ad Close Button

    @ViewBuilder
    private var adCloseButton: some View {
        if vm.isAdPlaying {
            VStack {
                HStack {
                    Button(action: { dismissPlayer() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.2))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Close player")
                    .padding(.leading, 16)
                    .padding(.top, 8)

                    Spacer()
                }
                Spacer()
            }
        }
    }

    // MARK: - Layer 1: Media (full-bleed)

    private var mediaLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                blurredBackdrop(for: .primary)
                blurredBackdrop(for: .secondary)

                playerLayerView(for: .primary)
                playerLayerView(for: .secondary)
            }
            .onAppear { vm.viewportSize = geo.size }
            .onChange(of: geo.size) { _, newSize in vm.viewportSize = newSize }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func blurredBackdrop(for slot: PlayerSlot) -> some View {
        if let player = vm.player(for: slot) {
            PlayerLayerView(player: player, videoGravity: .resizeAspectFill)
                .disabled(true)
                .opacity(vm.opacity(for: slot) * 0.7)
                .blur(radius: 100)
                .clipped()
        }
    }

    @ViewBuilder
    private func playerLayerView(for slot: PlayerSlot) -> some View {
        if let player = vm.player(for: slot) {
            PlayerLayerView(player: player, videoGravity: vm.videoGravity(for: slot))
                .disabled(true)
                .opacity(vm.opacity(for: slot))
                .offset(vm.offset(for: slot, viewSize: vm.viewportSize))
        }
    }

    // MARK: - Layer 2: Controls overlay

    @ViewBuilder
    private var controlsOverlay: some View {
        if vm.showingControls {
            VStack(spacing: 0) {
                PlayerHeader(
                    tapeName: vm.tape.title,
                    currentClipIndex: vm.currentClipIndex,
                    totalClips: vm.totalClips,
                    totalDuration: vm.totalTapeDuration,
                    onDismiss: { dismissPlayer() }
                )
                .padding(.top, 8)

                Spacer()

                HStack(alignment: .bottom) {
                    AirPlayButton()
                        .offset(y: 2)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.2))
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())

                    Spacer()

                    HStack(alignment: .bottom, spacing: 16) {
                        if vm.hasClipAudio {
                            VerticalVolumeSlider(
                                value: Binding(
                                    get: { vm.clipVolume },
                                    set: { vm.setClipVolume($0) }
                                ),
                                icon: "speaker.wave.2.fill"
                            )
                        }

                        if vm.hasBackgroundMusic {
                            VerticalVolumeSlider(
                                value: Binding(
                                    get: { vm.clipMusicVolume },
                                    set: { vm.setClipMusicVolume($0) }
                                ),
                                icon: "music.note"
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                PlayerTimeScrubBar(
                    timeState: vm.timeState,
                    isDisabled: vm.isAdPlaying,
                    onSeek: { time in
                        Task { await vm.seekWithinClip(time) }
                    }
                )

                VStack(spacing: 0) {
                    PlayerTimeLabelsView(timeState: vm.timeState)
                        .padding(.top, 6)

                    Spacer()

                    PlayerControls(
                        isPlaying: vm.isPlaying,
                        isFinished: vm.isFinished,
                        canGoBack: vm.canGoBack,
                        canGoForward: vm.canGoForward,
                        isDisabled: vm.isAdPlaying,
                        onPlayPause: { vm.togglePlayPause() },
                        onPrevious: { vm.previousClip() },
                        onNext: { vm.nextClip() }
                    )

                    Spacer()
                }
                .frame(height: 72)
                .background(
                    Color.black.opacity(0.4)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                )
            }
            .background(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.6), location: 0),
                        .init(color: .black.opacity(0.25), location: 0.4),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()
            }
            .background(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.15), location: 0.5),
                        .init(color: .black.opacity(0.5), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
                .ignoresSafeArea()
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: vm.showingControls)
        }
    }

    // MARK: - Toast

    private var toastLayer: some View {
        PlayerSkipToast(
            skippedCount: vm.skippedClipCount,
            isVisible: vm.showSkipToast
        )
    }

    // MARK: - Loading

    private var loadingLayer: some View {
        PlayerLoadingOverlay(
            isLoading: vm.isLoading,
            loadError: vm.loadError,
            onRetry: { Task { await vm.retryLoading() } },
            onDismiss: { dismissPlayer() }
        )
    }

    // MARK: - Playback Start

    private func startPlayback(from clipIndex: Int) {
        Task {
            await vm.prepare(
                api: authManager.apiClient,
                entitlementManager: entitlementManager,
                startAtClip: clipIndex
            )
        }
        vm.resetControlsTimer()
    }

    // MARK: - Dismiss

    private func dismissPlayer() {
        onSave?(vm.tape)
        vm.shutdown()
        onDismiss()
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                vm.handleSwipeChanged(
                    translation: value.translation.width,
                    viewWidth: vm.viewportSize.width
                )
            }
            .onEnded { value in
                vm.handleSwipeEnded(
                    translation: value.translation.width,
                    viewWidth: vm.viewportSize.width
                )
            }
    }
}

// MARK: - Time-Driven Views (isolated observation to avoid full-tree invalidation at 10 Hz)

private struct PlayerTimeScrubBar: View {
    @ObservedObject var timeState: PlayerTimeState
    var isDisabled: Bool
    var onSeek: (Double) -> Void

    var body: some View {
        PlayerScrubBar(
            currentTime: timeState.clipTime,
            totalDuration: timeState.clipDuration,
            isDisabled: isDisabled,
            onSeek: onSeek
        )
    }
}

private struct PlayerTimeLabelsView: View {
    @ObservedObject var timeState: PlayerTimeState

    var body: some View {
        PlayerTimeLabels(
            currentTime: timeState.clipTime,
            totalDuration: timeState.clipDuration
        )
    }
}

// MARK: - Player Layer View

private final class PlayerLayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        uiView.playerLayer.videoGravity = videoGravity
        CATransaction.commit()
    }
}
