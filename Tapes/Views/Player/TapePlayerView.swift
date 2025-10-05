import SwiftUI
import AVFoundation
import AVKit
import Photos
import UIKit

// MARK: - Unified Tape Player View

struct TapePlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentClipIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var showingControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var totalDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isFinished: Bool = false
    @State private var progressTimer: Timer?
    @State private var nextPlayerItem: AVPlayerItem?
    @State private var currentImage: UIImage?
    @State private var imageAnimationProgress: CGFloat = 0
    @State private var imageAnimationDuration: Double = 0
    @State private var imageClipTotalDuration: Double = 0
    @State private var imageRemainingDuration: Double = 0
    @State private var imageClipStartTime: Date?
    @State private var imageClipWorkItem: DispatchWorkItem?
    
    let tape: Tape
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Video Player
                videoPlayerView
                
                // Controls
                if showingControls {
                    controlsView
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                setupPlayer()
                setupControlsTimer()
            }
        }
                .onDisappear {
                    // Stop all audio and clean up
                    player?.pause()
                    player?.replaceCurrentItem(with: nil)
                    player = nil
                    resetImageState()
                    controlsTimer?.invalidate()
                    progressTimer?.invalidate()
                    imageClipWorkItem?.cancel()
                    // Clean up notification observers
                    NotificationCenter.default.removeObserver(self)
                }
        .onTapGesture {
            toggleControls()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding()
    }
    
    // MARK: - Video Player View
    
    private var videoPlayerView: some View {
        GeometryReader { geometry in
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .onDisappear {
                        player.pause()
                    }
            } else if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1 + 0.12 * CGFloat(imageAnimationProgress))
                    .offset(x: -geometry.size.width * 0.04 * imageAnimationProgress,
                            y: -geometry.size.height * 0.05 * imageAnimationProgress)
                    .animation(.linear(duration: imageAnimationDuration), value: imageAnimationProgress)
                    .clipped()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Loading...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        VStack(spacing: 20) {
            if isFinished {
                // Finished state - show play again button
                finishedView
            } else {
                // Global progress bar
                globalProgressView
                
                // Global control buttons
                globalControlButtons
            }
        }
        .padding()
    }
    
    // MARK: - Finished View
    
    private var finishedView: some View {
        VStack(spacing: 20) {
            Text("Playback Complete")
                .font(.title2)
                .foregroundColor(.white)
            
            Button(action: playAgain) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Play Again")
                }
                .font(.title2)
                .foregroundColor(.black)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Global Progress View
    
    private var globalProgressView: some View {
        VStack(spacing: 8) {
            // Interactive progress bar
            GeometryReader { geometry in
                let progressValue = totalDuration > 0 ? min(max(currentTime / totalDuration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)
                    
                    // Progress track
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progressValue, height: 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let targetTime = progress * totalDuration
                            currentTime = targetTime
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let _ = progress * totalDuration
                            scrubToPosition(value.location.x, in: geometry.size.width)
                        }
                )
            }
            .frame(height: 6)
            
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .foregroundColor(.white)
                    .font(.caption)
                
                Spacer()
                
                Text(formatTime(totalDuration))
                    .foregroundColor(.white)
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Global Control Buttons
    
    private var globalControlButtons: some View {
        HStack(spacing: 40) {
            // Previous button
            Button(action: previousClip) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex == 0)
            
            // Play/Pause button
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            
            // Next button
            Button(action: nextClip) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex >= tape.clips.count - 1)
        }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        HStack {
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .foregroundColor(.white)
            
            Spacer()
            
            if let clip = currentClip {
                Text(formatTime(effectiveDuration(for: clip)))
                    .foregroundColor(.white)
            }
        }
        .font(.caption)
    }
    
    // MARK: - Current Clip
    
    private var currentClip: Clip? {
        guard currentClipIndex < tape.clips.count else { return nil }
        return tape.clips[currentClipIndex]
    }

    private func effectiveDuration(for clip: Clip) -> Double {
        if clip.clipType == .image {
            let base = clip.duration > 0 ? clip.duration : 4.0
            return max(base, 0.1)
        }
        return max(clip.duration, 0)
    }
    
    // MARK: - Setup
    
    private func setupPlayer() {
        guard !tape.clips.isEmpty else { return }
        currentClipIndex = 0
        isFinished = false
        calculateTotalDuration()
        loadCurrentClip()
        startProgressTracking()
        updateCurrentTime()
    }
    
    private func calculateTotalDuration() {
        totalDuration = tape.clips.reduce(0) { total, clip in
            total + effectiveDuration(for: clip)
        }
    }
    
    private func loadCurrentClip() {
        resetImageState()
        player?.pause()
        currentTime = calculateElapsedTimeForCurrentClip()
        isFinished = false

        guard let clip = currentClip else {
            TapesLog.player.error("No clip available")
            return
        }

        if clip.clipType == .image {
            if let data = clip.imageData, let image = UIImage(data: data) {
                startImageClip(with: image, clip: clip)
            } else if let localURL = clip.localURL, let image = UIImage(contentsOfFile: localURL.path) {
                startImageClip(with: image, clip: clip)
            } else if let assetLocalId = clip.assetLocalId {
                loadPhotoFromPHAsset(assetLocalId: assetLocalId, clip: clip)
            } else if let thumbData = clip.thumbnail, let image = UIImage(data: thumbData) {
                startImageClip(with: image, clip: clip)
            } else {
                TapesLog.player.error("Unable to resolve image clip: \(clip.id)")
                onVideoEnded()
            }
            return
        }

        if let localURL = clip.localURL {
            playVideo(from: localURL)
        } else if let assetLocalId = clip.assetLocalId {
            loadVideoFromPHAsset(assetLocalId: assetLocalId)
        } else {
            TapesLog.player.error("No valid media source for clip \(clip.id)")
        }
    }



    private func playVideo(from url: URL) {
        let playerItem = AVPlayerItem(url: url)
        attachPlayerItem(playerItem)
    }

    private func loadVideoFromPHAsset(assetLocalId: String) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            TapesLog.player.error("PHAsset not found: \(assetLocalId)")
            return
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                if let urlAsset = avAsset as? AVURLAsset {
                    self.playVideo(from: urlAsset.url)
                } else if let composition = avAsset as? AVComposition {
                    let playerItem = AVPlayerItem(asset: composition)
                    self.attachPlayerItem(playerItem)
                } else {
                    TapesLog.player.error("Failed to resolve PHAsset to playable format: \(assetLocalId)")
                }
            }
        }
    }

    private func attachPlayerItem(_ playerItem: AVPlayerItem) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            self.onVideoEnded()
        }

        if let existingPlayer = player {
            existingPlayer.replaceCurrentItem(with: playerItem)
        } else {
            player = AVPlayer(playerItem: playerItem)
        }

        player?.play()
        isPlaying = true
    }

    private func loadPhotoFromPHAsset(assetLocalId: String, clip: Clip) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            TapesLog.player.error("Photo asset not found: \(assetLocalId)")
            onVideoEnded()
            return
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(for: phAsset,
                                               targetSize: PHImageManagerMaximumSize,
                                               contentMode: .aspectFill,
                                               options: options) { image, _ in
            DispatchQueue.main.async {
                guard self.currentClip?.id == clip.id else { return }
                if let image {
                    self.startImageClip(with: image, clip: clip)
                } else {
                    TapesLog.player.error("Failed to load image for asset: \(assetLocalId)")
                    self.onImageClipEnded()
                }
            }
        }
    }

    private func startImageClip(with image: UIImage, clip: Clip) {
        resetImageState()
        currentImage = image
        player = nil
        isPlaying = true

        let duration = effectiveDuration(for: clip)
        imageClipTotalDuration = duration
        imageRemainingDuration = duration
        imageClipStartTime = Date()
        imageAnimationProgress = 0
        imageAnimationDuration = duration

        withAnimation(.linear(duration: imageAnimationDuration)) {
            imageAnimationProgress = 1
        }

        scheduleImageClipCompletion(after: duration)
        updateCurrentTime()
    }

    private func scheduleImageClipCompletion(after duration: Double) {
        imageClipWorkItem?.cancel()
        guard duration > 0 else {
            onImageClipEnded()
            return
        }
        let workItem = DispatchWorkItem {
            onImageClipEnded()
        }
        imageClipWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func pauseImageClip() {
        guard let start = imageClipStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        imageClipWorkItem?.cancel()
        imageClipWorkItem = nil
        imageRemainingDuration = max(0, imageClipTotalDuration - elapsed)
        imageClipStartTime = nil
        imageAnimationDuration = 0
        let progress = imageClipTotalDuration > 0 ? min(max(elapsed / imageClipTotalDuration, 0), 1) : 1
        withAnimation(.linear(duration: 0)) {
            imageAnimationProgress = CGFloat(progress)
        }
        isPlaying = false
    }

    private func resumeImageClip() {
        guard imageRemainingDuration > 0 else {
            onImageClipEnded()
            return
        }
        imageClipStartTime = Date()
        imageAnimationDuration = imageRemainingDuration
        withAnimation(.linear(duration: imageAnimationDuration)) {
            imageAnimationProgress = 1
        }
        scheduleImageClipCompletion(after: imageRemainingDuration)
        isPlaying = true
        updateCurrentTime()
    }

    private func onImageClipEnded() {
        imageClipWorkItem?.cancel()
        imageClipWorkItem = nil
        imageClipStartTime = nil
        imageRemainingDuration = 0
        imageClipTotalDuration = 0
        imageAnimationDuration = 0
        imageAnimationProgress = 0
        currentImage = nil
        isPlaying = false
        onVideoEnded()
    }

    private func resetImageState() {
        imageClipWorkItem?.cancel()
        imageClipWorkItem = nil
        imageClipStartTime = nil
        imageClipTotalDuration = 0
        imageRemainingDuration = 0
        imageAnimationDuration = 0
        imageAnimationProgress = 0
        currentImage = nil
        isPlaying = false
    }

    private func onVideoEnded() {
        resetImageState()

        if currentClipIndex < tape.clips.count - 1 {
            currentClipIndex += 1
            loadCurrentClip()
        } else {
            player?.pause()
            isPlaying = false
            isFinished = true
        }
    }

    private func playAgain() {
        resetImageState()
        player?.pause()
        currentClipIndex = 0
        currentTime = 0
        isFinished = false
        loadCurrentClip()
    }


    // MARK: - Controls
    
    private func togglePlayPause() {
        if let player = player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        } else if currentImage != nil {
            if isPlaying {
                pauseImageClip()
            } else {
                resumeImageClip()
                setupControlsTimer()
            }
        }
    }
    
    private func nextClip() {
        guard currentClipIndex < tape.clips.count - 1 else { return }
        currentClipIndex += 1
        loadCurrentClip()
    }
    
    private func previousClip() {
        guard currentClipIndex > 0 else { return }
        currentClipIndex -= 1
        loadCurrentClip()
    }
    
    private func toggleControls() {
        withAnimation {
            showingControls.toggle()
        }
        
        if showingControls {
            setupControlsTimer()
        } else {
            controlsTimer?.invalidate()
        }
    }
    
    private func setupControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showingControls = false
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Progress Tracking
    
    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateCurrentTime()
        }
    }
    
    private func updateCurrentTime() {
        if let player = player, let currentItem = player.currentItem {
            let currentTimeInSeconds = CMTimeGetSeconds(currentItem.currentTime())
            let totalElapsedTime = calculateElapsedTimeForCurrentClip() + max(currentTimeInSeconds, 0)
            currentTime = min(totalElapsedTime, totalDuration)

            if totalElapsedTime >= totalDuration, !isFinished {
                currentTime = totalDuration
                isFinished = true
                player.pause()
                isPlaying = false
            }
        } else if currentImage != nil {
            let elapsed: Double
            if let start = imageClipStartTime {
                elapsed = Date().timeIntervalSince(start)
            } else {
                elapsed = imageClipTotalDuration - imageRemainingDuration
            }
            let clampedElapsed = min(max(elapsed, 0), imageClipTotalDuration)
            currentTime = min(calculateElapsedTimeForCurrentClip() + clampedElapsed, totalDuration)
        } else {
            currentTime = min(currentTime, totalDuration)
        }
    }

    private func calculateElapsedTimeForCurrentClip() -> Double {
        guard currentClipIndex > 0 else { return 0 }
        return tape.clips.prefix(currentClipIndex).reduce(0) { $0 + effectiveDuration(for: $1) }
    }

    private func scrubToPosition(_ x: CGFloat, in width: CGFloat) {
        guard totalDuration > 0 else { return }
        let progress = max(0, min(1, x / width))
        let targetTime = progress * totalDuration

        var accumulatedTime: Double = 0
        var targetClipIndex = 0

        for (index, clip) in tape.clips.enumerated() {
            let clipDuration = effectiveDuration(for: clip)
            if targetTime <= accumulatedTime + clipDuration {
                targetClipIndex = index
                break
            }
            accumulatedTime += clipDuration
        }

        if targetClipIndex != currentClipIndex {
            currentClipIndex = targetClipIndex
            loadCurrentClip()
        }

        let targetClip = tape.clips[currentClipIndex]
        let clipDuration = effectiveDuration(for: targetClip)
        let timeInCurrentClip = min(max(targetTime - accumulatedTime, 0), clipDuration)

        if let player = player {
            let targetCMTime = CMTime(seconds: timeInCurrentClip, preferredTimescale: 600)
            player.seek(to: targetCMTime)
        } else if currentImage != nil {
            imageClipStartTime = Date().addingTimeInterval(-timeInCurrentClip)
            imageRemainingDuration = max(clipDuration - timeInCurrentClip, 0)
            imageAnimationDuration = imageRemainingDuration
            let progress = clipDuration > 0 ? min(max(timeInCurrentClip / clipDuration, 0), 1) : 1
            withAnimation(.linear(duration: 0)) {
                imageAnimationProgress = CGFloat(progress)
            }
            if isPlaying {
                scheduleImageClipCompletion(after: imageRemainingDuration)
                withAnimation(.linear(duration: imageAnimationDuration)) {
                    imageAnimationProgress = 1
                }
            }
        }

        currentTime = min(targetTime, totalDuration)
    }

}


#Preview {
    TapePlayerView(
        tape: Tape.sampleTapes[0],
        onDismiss: {}
    )
}