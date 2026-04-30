import SwiftUI

struct BackgroundMusicSheet: View {
    @Binding var tape: Tape
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var libraryVM = LibraryBrowserViewModel()
    @State private var showingPaywall = false

    /// Set to `true` to re-enable the Moods tab in the segmented
    /// control. The mood enum, picker view, generation pipeline, and
    /// playback / export plumbing are all left intact while this is
    /// `false` — only the entry point in this sheet is hidden.
    static let moodsTabEnabled = false

    enum Tab: String, CaseIterable, Identifiable {
        case library = "12k Library"
        case moods = "Moods"
        case aiPrompt = "AI Prompt"

        var id: String { rawValue }

        static var visibleCases: [Tab] {
            allCases.filter { tab in
                switch tab {
                case .moods: return BackgroundMusicSheet.moodsTabEnabled
                default: return true
                }
            }
        }
    }

    @State private var selectedTab: Tab = .library

    var body: some View {
        NavigationStack {
            tabContent
                .modifier(MusicBarModifier(selectedTab: pickerBinding, libraryVM: libraryVM))
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
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    /// Picker binding that gates the AI Prompt segment for Free users.
    /// Tapping `.aiPrompt` while not entitled opens the paywall and the
    /// `selectedTab` value stays unchanged — the segmented control snaps
    /// back to its previous state automatically because the binding setter
    /// rejects the change.
    private var pickerBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .aiPrompt && !entitlementManager.canUseAIPrompt {
                    showingPaywall = true
                    return
                }
                selectedTab = newValue
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .library:
            LibraryBrowserView(
                tape: $tape,
                viewModel: libraryVM,
                onTrackSelected: handleDismiss,
                onUpgradeTapped: { showingPaywall = true }
            )
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
            ForEach(BackgroundMusicSheet.Tab.visibleCases) { tab in
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
