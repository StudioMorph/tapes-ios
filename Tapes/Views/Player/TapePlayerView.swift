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
                    .foregroundColor(Tokens.Colors.onSurface)
            }
            
            Spacer()
            
            VStack(spacing: Tokens.Spacing.s) {
                Text(tape.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.Colors.onSurface)
                    .lineLimit(1)
                
                Text("\(tape.clipCount) clips • \(formatDuration(composer.totalDuration))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.muted)
            }
            
            Spacer()
            
            // Placeholder for future settings
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Tokens.Colors.muted)
            }
            .opacity(0.5) // Placeholder styling
        }
        .padding(.horizontal, Tokens.Spacing.l)
        .padding(.top, Tokens.Spacing.l)
        .padding(.bottom, Tokens.Spacing.l)
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
                .fill(Tokens.Colors.elevated)
                .aspectRatio(tape.orientation == .portrait ? 9/16 : 16/9, contentMode: .fit)
            
            // Video Content Placeholder
            VStack(spacing: Tokens.Spacing.l) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Tokens.Colors.muted)
                
                Text("Video Preview")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.Colors.muted)
                
                if composer.currentClip != nil {
                    Text("Clip \(composer.currentClipIndex + 1) of \(tape.clipCount)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.muted)
                }
            }
        }
        .padding(.horizontal, Tokens.Spacing.l)
    }
    
    private var clipIndicator: some View {
        VStack(spacing: Tokens.Spacing.s) {
            ForEach(0..<tape.clipCount, id: \.self) { index in
                Circle()
                    .fill(index == composer.currentClipIndex ? 
                          Tokens.Colors.red : 
                          Tokens.Colors.muted)
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == composer.currentClipIndex ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: composer.currentClipIndex)
            }
        }
        .padding(.vertical, Tokens.Spacing.m)
        .padding(.horizontal, Tokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.6))
        )
    }
    
    private func transitionIndicator(_ transition: TransitionInfo) -> some View {
        VStack(spacing: Tokens.Spacing.s) {
            Text(transition.type.displayName)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .fontWeight(.medium)
            
            Text("\(String(format: "%.1f", transition.duration))s")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Tokens.Colors.red)
        )
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        VStack(spacing: Tokens.Spacing.l) {
            // Progress Bar
            progressBar
            
            // Control Buttons
            controlButtons
        }
        .padding(.horizontal, Tokens.Spacing.l)
        .padding(.bottom, Tokens.Spacing.l)
    }
    
    private var progressBar: some View {
        VStack(spacing: Tokens.Spacing.s) {
            // Progress Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Tokens.Colors.elevated)
                        .frame(height: 4)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Tokens.Colors.red)
                        .frame(width: geometry.size.width * composer.progress, height: 4)
                        .animation(.easeInOut(duration: 0.1), value: composer.progress)
                }
            }
            .frame(height: 4)
            
            // Time Labels
            HStack {
                Text(formatTime(composer.currentTime))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.muted)
                
                Spacer()
                
                Text(formatTime(composer.totalDuration))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.muted)
            }
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: Tokens.Spacing.l) {
            // Restart Button
            Button(action: composer.restart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.onSurface)
            }
            
            // Play/Pause Button
            Button(action: composer.togglePlayPause) {
                Image(systemName: composer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(Tokens.Colors.red)
            }
            
            // Placeholder for future controls
            Button(action: {}) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.muted)
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
