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
            Tokens.Colors.bg
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
                    .foregroundColor(Tokens.Colors.textPrimary)
            }
            
            Spacer()
            
            VStack(spacing: Tokens.Space.s4) {
                Text(tape.title)
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.Colors.textPrimary)
                    .lineLimit(1)
                
                Text("\(tape.clipCount) clips • \(formatDuration(composer.totalDuration))")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.textMuted)
            }
            
            Spacer()
            
            // Placeholder for future settings
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Tokens.Colors.textMuted)
            }
            .opacity(0.5) // Placeholder styling
        }
        .padding(.horizontal, Tokens.Space.s20)
        .padding(.top, Tokens.Space.s16)
        .padding(.bottom, Tokens.Space.s20)
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
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.surfaceElevated)
                .aspectRatio(tape.orientation == .portrait ? 9/16 : 16/9, contentMode: .fit)
            
            // Video Content Placeholder
            VStack(spacing: Tokens.Space.s16) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Tokens.Colors.textMuted)
                
                Text("Video Preview")
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.Colors.textMuted)
                
                if composer.currentClip != nil {
                    Text("Clip \(composer.currentClipIndex + 1) of \(tape.clipCount)")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Colors.textMuted)
                }
            }
        }
        .padding(.horizontal, Tokens.Space.s20)
    }
    
    private var clipIndicator: some View {
        VStack(spacing: Tokens.Space.s8) {
            ForEach(0..<tape.clipCount, id: \.self) { index in
                Circle()
                    .fill(index == composer.currentClipIndex ? 
                          Tokens.Colors.brandRed : 
                          Tokens.Colors.textMuted)
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == composer.currentClipIndex ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: composer.currentClipIndex)
            }
        }
        .padding(.vertical, Tokens.Space.s12)
        .padding(.horizontal, Tokens.Space.s8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail)
                .fill(.black.opacity(0.6))
        )
    }
    
    private func transitionIndicator(_ transition: TransitionInfo) -> some View {
        VStack(spacing: Tokens.Space.s4) {
            Text(transition.type.displayName)
                .font(Tokens.Typography.caption)
                .foregroundColor(.white)
                .fontWeight(.medium)
            
            Text("\(String(format: "%.1f", transition.duration))s")
                .font(Tokens.Typography.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, Tokens.Space.s12)
        .padding(.vertical, Tokens.Space.s8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail)
                .fill(Tokens.Colors.brandRed)
        )
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        VStack(spacing: Tokens.Space.s20) {
            // Progress Bar
            progressBar
            
            // Control Buttons
            controlButtons
        }
        .padding(.horizontal, Tokens.Space.s20)
        .padding(.bottom, Tokens.Space.s32)
    }
    
    private var progressBar: some View {
        VStack(spacing: Tokens.Space.s8) {
            // Progress Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Tokens.Colors.surfaceElevated)
                        .frame(height: 4)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Tokens.Colors.brandRed)
                        .frame(width: geometry.size.width * composer.progress, height: 4)
                        .animation(.easeInOut(duration: 0.1), value: composer.progress)
                }
            }
            .frame(height: 4)
            
            // Time Labels
            HStack {
                Text(formatTime(composer.currentTime))
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.textMuted)
                
                Spacer()
                
                Text(formatTime(composer.totalDuration))
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.textMuted)
            }
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: Tokens.Space.s32) {
            // Restart Button
            Button(action: composer.restart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.textPrimary)
            }
            
            // Play/Pause Button
            Button(action: composer.togglePlayPause) {
                Image(systemName: composer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(Tokens.Colors.brandRed)
            }
            
            // Placeholder for future controls
            Button(action: {}) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.textMuted)
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

#Preview("Dark Mode") {
    TapePlayerView(tape: Tape.sampleTapes[0]) {
        print("Dismissed")
    }
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapePlayerView(tape: Tape.sampleTapes[0]) {
        print("Dismissed")
    }
    .preferredColorScheme(.light)
}
