import SwiftUI

/// Reusable sync badge showing a count and directional arrow.
///
/// Usage:
/// - `.download` (arrow down): new clips available to pull from the server
/// - `.upload` (arrow up): local clips ready to push to the server
///
/// Position this as an overlay on the tape card, aligned `.bottomTrailing`.
public struct SyncBadge: View {

    public enum Direction {
        case download, upload

        var systemImage: String {
            self == .download ? "arrow.down" : "arrow.up"
        }

        var animationOffset: CGFloat {
            self == .download ? 3 : -3
        }
    }

    let count: Int
    let direction: Direction
    var action: (() -> Void)?

    @State private var animating = false

    public var body: some View {
        Button {
            action?()
        } label: {
            badge
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                animating = true
            }
        }
    }

    private var badge: some View {
        ZStack(alignment: .topLeading) {
            arrowTile
                .padding(.top, 4)
                .padding(.leading, 4)

            countCircle
                .zIndex(1)
        }
    }

    private var countCircle: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Tokens.Colors.systemBlue))
    }

    private var arrowTile: some View {
        Image(systemName: direction.systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Tokens.Colors.systemBlue)
            .offset(y: animating ? direction.animationOffset : 0)
            .frame(minWidth: 44, minHeight: 28)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: Tokens.Radius.card,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: Tokens.Radius.card,
                    topTrailingRadius: 0
                )
                .fill(Tokens.Colors.tertiaryBackground)
            )
    }
}

// MARK: - Preview

#Preview("Download") {
    ZStack {
        Color(hex: "#14202F").ignoresSafeArea()

        RoundedRectangle(cornerRadius: Tokens.Radius.card)
            .fill(Color(hex: "#1A293B"))
            .frame(width: 340, height: 200)
            .overlay(alignment: .bottomTrailing) {
                SyncBadge(count: 5, direction: .download)
            }
    }
}

#Preview("Upload") {
    ZStack {
        Color(hex: "#14202F").ignoresSafeArea()

        RoundedRectangle(cornerRadius: Tokens.Radius.card)
            .fill(Color(hex: "#1A293B"))
            .frame(width: 340, height: 200)
            .overlay(alignment: .bottomTrailing) {
                SyncBadge(count: 3, direction: .upload)
            }
    }
}
