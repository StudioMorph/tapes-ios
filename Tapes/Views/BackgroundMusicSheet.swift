import SwiftUI

struct BackgroundMusicSheet: View {
    @Binding var tape: Tape
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var libraryVM = LibraryBrowserViewModel()

    enum Tab: String, CaseIterable, Identifiable {
        case library = "12k Library"
        case moods = "Moods"
        case aiPrompt = "AI Prompt"

        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .moods

    var body: some View {
        NavigationStack {
            tabContent
                .modifier(MusicBarModifier(selectedTab: $selectedTab, libraryVM: libraryVM))
                .modifier(ScrollEdgeSoftModifier())
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

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .library:
            LibraryBrowserView(tape: $tape, viewModel: libraryVM, onTrackSelected: handleDismiss)
        case .moods:
            BackgroundMusicPickerView(tape: $tape)
        case .aiPrompt:
            AIPromptMusicView(tape: $tape, onTrackGenerated: handleDismiss)
        }
    }

    private func handleDismiss() {
        dismiss()
    }
}

private struct ScrollEdgeSoftModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct MusicBarModifier: ViewModifier {
    @Binding var selectedTab: BackgroundMusicSheet.Tab
    @ObservedObject var libraryVM: LibraryBrowserViewModel

    private var picker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(BackgroundMusicSheet.Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
    }

    @ViewBuilder
    private var bar: some View {
        VStack(spacing: 0) {
            picker
            if selectedTab == .library && !libraryVM.availableFilters.isEmpty {
                LibraryFilterBar(viewModel: libraryVM)
            }
        }
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top) { bar }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                bar.background(.bar)
            }
        }
    }
}
