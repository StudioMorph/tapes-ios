import SwiftUI

struct SharedTapesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator

    @State private var filter: SharedFilter = .viewOnly
    @State private var sharedTapes: [SharedTapeItem] = []
    @State private var isLoading = false
    @State private var selectedTapeId: String?

    enum SharedFilter: String, CaseIterable {
        case viewOnly = "View Only"
        case collaborative = "Collaborative"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(SharedFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.top, Tokens.Spacing.m)
                .padding(.bottom, Tokens.Spacing.m)

                if !authManager.isSignedIn {
                    signInPrompt
                } else if isLoading {
                    loadingState
                } else if filteredTapes.isEmpty {
                    emptyState
                } else {
                    tapeList
                }
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Shared")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: Binding(
                get: { selectedTapeId != nil },
                set: { if !$0 { selectedTapeId = nil } }
            )) {
                if let tapeId = selectedTapeId {
                    SharedTapeDetailView(tapeId: tapeId)
                }
            }
            .task {
                await loadSharedTapes()
            }
            .refreshable {
                await loadSharedTapes()
            }
            .onChange(of: navigationCoordinator.pendingSharedTapeId) { _, newId in
                if let tapeId = newId {
                    selectedTapeId = tapeId
                    navigationCoordinator.clearPendingTape()
                    Task { await loadSharedTapes() }
                }
            }
        }
    }

    // MARK: - Filtered Data

    private var filteredTapes: [SharedTapeItem] {
        sharedTapes.filter { item in
            switch filter {
            case .viewOnly: return item.mode == "view_only"
            case .collaborative: return item.mode == "collaborative"
            }
        }
    }

    // MARK: - Sign In Prompt

    private var signInPrompt: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text("Sign in to see shared tapes")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("Tapes shared with you will appear here after you sign in with your Apple ID.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(Tokens.Colors.secondaryText)
            Text("Loading shared tapes...")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .padding(.top, Tokens.Spacing.m)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Spacer()

            Image(systemName: filter == .viewOnly ? "eye.slash" : "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(Tokens.Colors.tertiaryText)

            Text(filter == .viewOnly
                 ? "No view-only tapes yet"
                 : "No collaborative tapes yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("When someone shares a tape with you, it will appear here.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.xxl)

            Spacer()
        }
    }

    // MARK: - Tape List

    private var tapeList: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.m) {
                ForEach(filteredTapes) { item in
                    Button {
                        selectedTapeId = item.tapeId
                    } label: {
                        SharedTapeCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.vertical, Tokens.Spacing.s)
        }
    }

    // MARK: - Data Loading

    private func loadSharedTapes() async {
        guard authManager.isSignedIn, let api = authManager.apiClient else { return }
        isLoading = sharedTapes.isEmpty

        do {
            let tapes = try await api.getSharedTapes()
            await MainActor.run {
                sharedTapes = tapes
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Shared Tape Card

private struct SharedTapeCard: View {
    let item: SharedTapeItem

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Tokens.Typography.headline)
                        .foregroundStyle(Tokens.Colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: Tokens.Spacing.s) {
                        Text("by \(item.ownerName)")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Colors.secondaryText)

                        if let clipCount = item.clipCount {
                            Text("· \(clipCount) clips")
                                .font(Tokens.Typography.caption)
                                .foregroundStyle(Tokens.Colors.tertiaryText)
                        }
                    }
                }

                Spacer()

                if item.mode == "collaborative" {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.Colors.systemBlue)
                } else {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
            }

            if let expiresAt = item.expiresAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("Expires \(expiresAt, style: .relative)")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Tokens.Colors.tertiaryText)
            }
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}

#Preview {
    SharedTapesView()
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
        .environmentObject(NavigationCoordinator())
}
