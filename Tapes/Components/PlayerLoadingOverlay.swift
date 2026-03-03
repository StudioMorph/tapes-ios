import SwiftUI

struct PlayerLoadingOverlay: View {
    let isLoading: Bool
    let loadError: String?
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if isLoading && loadError == nil {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)

                    Text("Getting tape ready\u{2026}")
                        .font(Tokens.Typography.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if let loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                    Text("Playback Error")
                        .font(Tokens.Typography.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text(loadError)
                        .font(Tokens.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        if let onRetry {
                            Button(action: onRetry) {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(Tokens.Typography.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .accessibilityLabel("Retry loading")
                        }

                        if let onDismiss {
                            Button(action: onDismiss) {
                                Text("Close")
                                    .font(Tokens.Typography.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .accessibilityLabel("Close player")
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .opacity((isLoading || loadError != nil) ? 1 : 0)
        .allowsHitTesting(loadError != nil)
    }
}

#Preview {
    ZStack {
        Color.black
        PlayerLoadingOverlay(
            isLoading: false,
            loadError: "Could not load clip",
            onRetry: {},
            onDismiss: {}
        )
    }
}
