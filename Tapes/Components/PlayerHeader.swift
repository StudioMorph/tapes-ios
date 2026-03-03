import SwiftUI

struct PlayerHeader: View {
    let tapeName: String
    let currentClipIndex: Int
    let totalClips: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Close player")
            .accessibilityHint("Dismisses the video player")

            Spacer()

            Text(tapeName)
                .font(Tokens.Typography.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            HStack(spacing: 12) {
                AirPlayButton()
                    .frame(width: 44, height: 44)

                Text("\(currentClipIndex + 1)/\(totalClips)")
                    .font(Tokens.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    PlayerHeader(
        tapeName: "Summer Holidays",
        currentClipIndex: 2,
        totalClips: 5,
        onDismiss: {}
    )
    .background(Color.black)
}
