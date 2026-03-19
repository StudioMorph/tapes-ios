import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    @ObservedObject var exportCoordinator: ExportCoordinator
    let onQAChecklistTapped: () -> Void

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

            if showExportIndicator {
                Button {
                    exportCoordinator.showProgressDialogAgain()
                } label: {
                    ZStack {
                        CircularProgressRing(
                            progress: exportCoordinator.progress,
                            lineWidth: 2.5,
                            size: 28,
                            ringColor: Tokens.Colors.systemRed
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
                Button(action: onQAChecklistTapped) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundColor(Tokens.Colors.systemRed)
                        .frame(width: Tokens.HitTarget.minimum, height: Tokens.HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("QA Checklist")
                .accessibilityHint("Opens the QA checklist for testing")
            }
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.top, Tokens.Spacing.s)
        .padding(.bottom, Tokens.Spacing.xs)
        .animation(.easeInOut(duration: 0.25), value: isJiggling)
        .animation(.easeInOut(duration: 0.25), value: showExportIndicator)
    }
}

#Preview {
    HeaderView(
        exportCoordinator: ExportCoordinator(),
        onQAChecklistTapped: {}
    )
    .background(Tokens.Colors.primaryBackground)
    .environmentObject(TapesStore())
}
