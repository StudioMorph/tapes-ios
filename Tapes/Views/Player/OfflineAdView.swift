import SwiftUI

struct OfflineAdView: View {

    let onCountdownFinished: () -> Void

    @State private var remaining = AdConfig.offlineCountdownDuration
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Tokens.Colors.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: Tokens.Spacing.l) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("You're offline")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Tokens.Colors.primaryText)

                Text("We can't load the ads that keep Tapes free\n— but we've got you.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Tokens.Spacing.xl)

                Text("Your tape will play in 0:\(String(format: "%02d", remaining))")
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .padding(.top, Tokens.Spacing.m)
            }
        }
        .onAppear { startCountdown() }
        .onDisappear { timerTask?.cancel() }
    }

    private func startCountdown() {
        timerTask?.cancel()
        remaining = AdConfig.offlineCountdownDuration
        timerTask = Task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
            }
            guard !Task.isCancelled else { return }
            onCountdownFinished()
        }
    }
}

#Preview {
    OfflineAdView(onCountdownFinished: {})
}
