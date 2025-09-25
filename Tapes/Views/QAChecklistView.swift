import SwiftUI

struct QAChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    Text("QA Smoke Test Checklist")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Tokens.Colors.text)
                        .padding(.bottom, Tokens.Space.s)
                    
                    Text("Follow these steps to verify the app functionality:")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Tokens.Colors.muted)
                        .padding(.bottom, Tokens.Space.l)
                    
                    // Section 1: App Launch & New Tape
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("1) App Launch & New Tape")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "1.1",
                            action: "Launch the app",
                            expected: "Home shows empty Tape or last opened Tape."
                        )
                        
                        QAChecklistItem(
                            step: "1.2", 
                            action: "Create a new Tape",
                            expected: "New timeline opens with start + and end +; record button centered."
                        )
                        
                        QAChecklistItem(
                            step: "1.3",
                            action: "Verify snapping math", 
                            expected: "Carousel snaps so a thumbnail/+ sits on each side of the fixed center button."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                    
                    // Section 2: Insert Clips
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("2) Insert Clips")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "2.1",
                            action: "Record a short clip",
                            expected: "Clip inserts at the center slot."
                        )
                        
                        QAChecklistItem(
                            step: "2.2",
                            action: "Add from device", 
                            expected: "Clip inserts at the center slot."
                        )
                        
                        QAChecklistItem(
                            step: "2.3",
                            action: "Insert at start",
                            expected: "Clip appears at index 0 via the start +."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                    
                    // Section 3: Edit Sheet
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("3) Edit Sheet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "3.1",
                            action: "Tap a clip",
                            expected: "Edit sheet shows Trim / Rotate / Fit-Fill / Share / Remove."
                        )
                        
                        QAChecklistItem(
                            step: "3.2",
                            action: "Trim",
                            expected: "Saves new trimmed asset and replaces in Tape."
                        )
                        
                        QAChecklistItem(
                            step: "3.3",
                            action: "Remove",
                            expected: "Confirmation dialog; if Tape empty → only start + remains."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                    
                    // Section 4: Settings
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("4) Settings (Tape-Level)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "4.1",
                            action: "Orientation",
                            expected: "Switches to 9:16 or 16:9 canvas."
                        )
                        
                        QAChecklistItem(
                            step: "4.2",
                            action: "Aspect Fit",
                            expected: "Whole video, letter/pillar-boxing."
                        )
                        
                        QAChecklistItem(
                            step: "4.3",
                            action: "Aspect Fill",
                            expected: "Crops to fill."
                        )
                        
                        QAChecklistItem(
                            step: "4.4",
                            action: "Transition None",
                            expected: "Hard cuts preview + export."
                        )
                        
                        QAChecklistItem(
                            step: "4.5",
                            action: "Transition Crossfade",
                            expected: "Fades preview + export."
                        )
                        
                        QAChecklistItem(
                            step: "4.6",
                            action: "Slide L→R / R→L",
                            expected: "Slides preview + export (iOS AVF, Android FFmpeg)."
                        )
                        
                        QAChecklistItem(
                            step: "4.7",
                            action: "Randomise",
                            expected: "Deterministic per Tape; 0.5s clamp."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                    
                    // Section 5: Preview
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("5) Preview")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "5.1",
                            action: "▶️ → Preview",
                            expected: "Plays with correct transitions and Fit/Fill/Rotation."
                        )
                        
                        QAChecklistItem(
                            step: "5.2",
                            action: "Restart",
                            expected: "Seeks to 0; plays."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                    
                    // Section 6: Export
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("6) Export")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "6.1",
                            action: "▶️ → Merge & Save",
                            expected: "Progress UI appears."
                        )
                        
                        QAChecklistItem(
                            step: "6.2",
                            action: "iOS",
                            expected: "Saves to Photos › Tapes with video+audio crossfades."
                        )
                        
                        QAChecklistItem(
                            step: "6.3",
                            action: "Android",
                            expected: "Saves to Movies/Tapes with xfade/acrossfade & 1080p canvas."
                        )
                        
                        QAChecklistItem(
                            step: "6.4",
                            action: "Error",
                            expected: "Alerts/Toasts on failure."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                    
                    // Section 7: Casting UI
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("7) Casting UI")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        QAChecklistItem(
                            step: "7.1",
                            action: "No devices",
                            expected: "Cast button hidden."
                        )
                        
                        QAChecklistItem(
                            step: "7.2",
                            action: "Device available (iOS)",
                            expected: "AirPlay button appears; system picker opens."
                        )
                        
                        QAChecklistItem(
                            step: "7.3",
                            action: "Device available (Android)",
                            expected: "Cast button appears; toast \"not implemented\"."
                        )
                    }
                    .padding(.bottom, Tokens.Space.xl)
                }
                .padding(.horizontal, Tokens.Space.xl)
                .padding(.vertical, Tokens.Space.l)
            }
            .navigationTitle("QA Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QAChecklistItem: View {
    let step: String
    let action: String
    let expected: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .top) {
                Text(step)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.brandRed)
                    .frame(width: 30, alignment: .leading)
                
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(action)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Tokens.Colors.text)
                    
                    Text("Expected: \(expected)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.muted)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, Tokens.Space.xs)
    }
}

#Preview("Dark Mode") {
    QAChecklistView()
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    QAChecklistView()
        .preferredColorScheme(.light)
}

