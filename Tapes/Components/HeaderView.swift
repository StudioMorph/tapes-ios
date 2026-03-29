import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var exportCoordinator: ExportCoordinator
    @State private var showingAccountSettings = false

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID != nil
    }

    private var showExportIndicator: Bool {
        exportCoordinator.isExporting && !exportCoordinator.showProgressDialog
    }

    var body: some View {
        HStack {
            Text("TAPES")
                .font(Tokens.Typography.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Tokens.Colors.systemRed)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if isJiggling {
                Button("Done") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if tapeStore.isFloatingClip {
                            tapeStore.returnFloatingClip()
                        }
                        tapeStore.jigglingTapeID = nil
                    }
                }
                .font(.body.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .accessibilityLabel("Done")
                .accessibilityHint("Exits jiggle editing mode")
            } else {
                HStack(spacing: Tokens.Spacing.m) {
                    if showExportIndicator {
                        Button {
                            exportCoordinator.showProgressDialogAgain()
                        } label: {
                            ZStack {
                                CircularProgressRing(
                                    progress: exportCoordinator.progress,
                                    lineWidth: 2.5,
                                    size: 28,
                                    ringColor: .green
                                )

                                Image(systemName: "arrow.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Tokens.Colors.primaryText)
                            }
                            .frame(width: Tokens.HitTarget.minimum, height: Tokens.HitTarget.minimum)
                            .contentShape(Rectangle())
                        }
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Export in progress")
                        .accessibilityHint("Tap to view export progress")
                    }

                    Button {
                        showingAccountSettings = true
                    } label: {
                        accountIcon
                            .frame(width: Tokens.HitTarget.minimum, height: Tokens.HitTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Account and settings")
                }
            }
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.top, Tokens.Spacing.s)
        .padding(.bottom, Tokens.Spacing.xs)
        .animation(.easeInOut(duration: 0.25), value: isJiggling)
        .animation(.easeInOut(duration: 0.25), value: showExportIndicator)
        .sheet(isPresented: $showingAccountSettings) {
            AccountSettingsView()
        }
    }

    @ViewBuilder
    private var accountIcon: some View {
        if let name = authManager.userName, let initial = name.first {
            Text(String(initial).uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.blue))
        } else {
            Image(systemName: "person.circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Tokens.Colors.primaryText)
        }
    }
}

#Preview {
    HeaderView(
        exportCoordinator: ExportCoordinator()
    )
    .background(Tokens.Colors.primaryBackground)
    .environmentObject(TapesStore())
    .environmentObject(AuthManager())
}
