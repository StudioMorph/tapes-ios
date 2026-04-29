import SwiftUI

struct BackgroundMusicSheet: View {
    @Binding var tape: Tape
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case library = "12k Library"
        case moods = "Moods"
        case aiPrompt = "AI Prompt"
    }

    @State private var selectedTab: Tab = .moods

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.s)

                switch selectedTab {
                case .library:
                    LibraryBrowserView(tape: $tape, onTrackSelected: handleDismiss)
                case .moods:
                    BackgroundMusicPickerView(tape: $tape)
                case .aiPrompt:
                    AIPromptMusicView(tape: $tape, onTrackGenerated: handleDismiss)
                }
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Background Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func handleDismiss() {
        dismiss()
    }
}
