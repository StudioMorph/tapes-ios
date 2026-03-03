import SwiftUI
import AVFoundation
import AVKit

struct TapePlayerView: View {
    @StateObject private var vm: TapePlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    let onDismiss: () -> Void

    init(tape: Tape, onDismiss: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: TapePlayerViewModel(tape: tape))
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    var body: some View {
        Color.clear
            .background { mediaLayer }
            .contentShape(Rectangle())
            .onTapGesture { vm.toggleControls() }
            .gesture(swipeGesture)
            .overlay { controlsOverlay }
            .overlay { toastLayer }
            .overlay { loadingLayer }
            .onAppear {
                Task { await vm.prepare() }
                vm.resetControlsTimer()
            }
            .onDisappear {
                vm.shutdown()
            }
            .onChange(of: scenePhase) { _, newPhase in
                vm.handleScenePhaseChange(newPhase)
            }
    }

    // MARK: - Layer 1: Media (full-bleed)

    private var mediaLayer: some View {
        let size = vm.viewportSize
        return ZStack {
            Color.black
            playerLayerView(for: .primary, size: size)
            playerLayerView(for: .secondary, size: size)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func playerLayerView(for slot: PlayerSlot, size: CGSize) -> some View {
        if let player = vm.player(for: slot) {
            PlayerLayerView(player: player, videoGravity: vm.videoGravity(for: slot))
                .disabled(true)
                .opacity(vm.opacity(for: slot))
                .offset(vm.offset(for: slot, viewSize: size))
                .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Layer 2: Controls overlay (safe-area-respecting)

    @ViewBuilder
    private var controlsOverlay: some View {
        if vm.showingControls {
            VStack(spacing: 0) {
                PlayerHeader(
                    tapeName: vm.tape.title,
                    currentClipIndex: vm.currentClipIndex,
                    totalClips: vm.totalClips,
                    onDismiss: { vm.shutdown(); onDismiss() }
                )
                .padding(.top, 8)
                .padding(.bottom, 20)
                .background {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.8), location: 0),
                            .init(color: .black.opacity(0.3), location: 0.7),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                }

                Spacer()

                VStack(spacing: 32) {
                    PlayerProgressBar(
                        currentTime: vm.globalCurrentTime,
                        totalDuration: vm.totalTapeDuration,
                        onSeek: { time in
                            Task { await vm.seekToGlobalTime(time) }
                        }
                    )

                    PlayerControls(
                        isPlaying: vm.isPlaying,
                        isFinished: vm.isFinished,
                        canGoBack: vm.canGoBack,
                        canGoForward: vm.canGoForward,
                        onPlayPause: { vm.togglePlayPause() },
                        onPrevious: { vm.previousClip() },
                        onNext: { vm.nextClip() }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.3), location: 0.3),
                            .init(color: .black.opacity(0.8), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
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
            onDismiss: { vm.shutdown(); onDismiss() }
        )
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
        uiView.playerLayer.videoGravity = videoGravity
    }
}
