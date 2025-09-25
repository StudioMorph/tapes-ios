import SwiftUI

// MARK: - Tape Player View

public struct TapePlayerView: View {
    @StateObject private var composer: PlayerComposer
    @State private var showingControls: Bool = true
    @State private var controlsTimer: Timer?
    
    let tape: Tape
    let onDismiss: () -> Void
    
    public init(tape: Tape, onDismiss: @escaping () -> Void) {
        self.tape = tape
        self.onDismiss = onDismiss
        self._composer = StateObject(wrappedValue: PlayerComposer(tape: tape))
    }
    
    public var body: some View {
        ZStack {
            // Background
            DesignTokens.Colors.surface(.light)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Main Player Area
                mainPlayerArea
                
                // Controls
                if showingControls {
                    controlsView
                }
            }
        }
        .onAppear {
            setupControlsTimer()
        }
        .onDisappear {
            composer.pause()
            controlsTimer?.invalidate()
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
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.onSurface(.light))
            }
            
            Spacer()
            
            VStack(spacing: DesignTokens.Spacing.s4) {
                Text(tape.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundColor(DesignTokens.Colors.onSurface(.light))
                    .lineLimit(1)
                
                Text("\(tape.clipCount) clips • \(formatDuration(composer.totalDuration))")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.muted(60))
            }
            
            Spacer()
            
            // Placeholder for future settings
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.muted(60))
            }
            .opacity(0.5) // Placeholder styling
        }
        .padding(.horizontal, DesignTokens.Spacing.s20)
        .padding(.top, DesignTokens.Spacing.s16)
        .padding(.bottom, DesignTokens.Spacing.s20)
    }
    
    // MARK: - Main Player Area
    
    private var mainPlayerArea: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Preview Area
                videoPreviewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Clip Indicator
                clipIndicator
                    .position(x: geometry.size.width - 60, y: 60)
                
                // Transition Indicator
                if let transition = composer.getCurrentTransition() {
                    transitionIndicator(transition)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 100)
                }
            }
        }
    }
    
    private var videoPreviewArea: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Colors.muted(20))
                .aspectRatio(tape.orientation == .portrait ? 9/16 : 16/9, contentMode: .fit)
            
            // Video Content Placeholder
            VStack(spacing: DesignTokens.Spacing.s16) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(DesignTokens.Colors.muted(40))
                
                Text("Video Preview")
                    .font(DesignTokens.Typography.title)
                    .foregroundColor(DesignTokens.Colors.muted(60))
                
                if composer.currentClip != nil {
                    Text("Clip \(composer.currentClipIndex + 1) of \(tape.clipCount)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.muted(60))
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s20)
    }
    
    private var clipIndicator: some View {
        VStack(spacing: DesignTokens.Spacing.s8) {
            ForEach(0..<tape.clipCount, id: \.self) { index in
                Circle()
                    .fill(index == composer.currentClipIndex ? 
                          DesignTokens.Colors.primaryRed : 
                          DesignTokens.Colors.muted(40))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == composer.currentClipIndex ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: composer.currentClipIndex)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.s12)
        .padding(.horizontal, DesignTokens.Spacing.s8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                .fill(.black.opacity(0.6))
        )
    }
    
    private func transitionIndicator(_ transition: TransitionInfo) -> some View {
        VStack(spacing: DesignTokens.Spacing.s4) {
            Text(transition.type.displayName)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.white)
                .fontWeight(.medium)
            
            Text("\(String(format: "%.1f", transition.duration))s")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, DesignTokens.Spacing.s12)
        .padding(.vertical, DesignTokens.Spacing.s8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                .fill(DesignTokens.Colors.primaryRed)
        )
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        VStack(spacing: DesignTokens.Spacing.s20) {
            // Progress Bar
            progressBar
            
            // Control Buttons
            controlButtons
        }
        .padding(.horizontal, DesignTokens.Spacing.s20)
        .padding(.bottom, DesignTokens.Spacing.s32)
    }
    
    private var progressBar: some View {
        VStack(spacing: DesignTokens.Spacing.s8) {
            // Progress Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.Colors.muted(30))
                        .frame(height: 4)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.Colors.primaryRed)
                        .frame(width: geometry.size.width * composer.progress, height: 4)
                        .animation(.easeInOut(duration: 0.1), value: composer.progress)
                }
            }
            .frame(height: 4)
            
            // Time Labels
            HStack {
                Text(formatTime(composer.currentTime))
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.muted(60))
                
                Spacer()
                
                Text(formatTime(composer.totalDuration))
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.muted(60))
            }
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: DesignTokens.Spacing.s32) {
            // Restart Button
            Button(action: composer.restart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.onSurface(.light))
            }
            
            // Play/Pause Button
            Button(action: composer.togglePlayPause) {
                Image(systemName: composer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.primaryRed)
            }
            
            // Placeholder for future controls
            Button(action: {}) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.muted(60))
            }
            .opacity(0.5) // Placeholder styling
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
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
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls = false
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

struct TapePlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleTape = Tape(
            title: "Sample Tape",
            orientation: .landscape,
            scaleMode: .fit,
            transition: .crossfade,
            transitionDuration: 0.5
        )
        
        TapePlayerView(tape: sampleTape) {
            print("Dismissed")
        }
        .previewDisplayName("Tape Player")
    }
}
