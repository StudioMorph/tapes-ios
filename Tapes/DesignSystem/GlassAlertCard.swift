import SwiftUI

struct GlassAlertButton {
    let title: String
    let style: Style
    let action: () -> Void

    enum Style {
        case secondary
        case primary
    }
}

struct GlassAlertCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let iconSize: CGFloat
    let title: String
    let message: String
    let buttons: [GlassAlertButton]

    init(
        icon: String,
        iconSize: CGFloat = 48,
        title: String,
        message: String,
        buttons: [GlassAlertButton]
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.title = title
        self.message = message
        self.buttons = buttons
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.top, 14)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 24)
                .padding(.horizontal, 8)

                HStack(spacing: 16) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                        buttonView(for: button)
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 40, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.45), .white.opacity(0.12)]
                                : [.white.opacity(0.6), .white.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: 340)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    @ViewBuilder
    private func buttonView(for button: GlassAlertButton) -> some View {
        Button {
            button.action()
        } label: {
            Text(button.title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(button.style == .primary ? .white : Color.primary)
                .frame(maxWidth: button.style == .primary ? .infinity : nil)
                .frame(height: 48)
                .frame(minWidth: button.style == .secondary ? 108 : nil)
                .background(
                    Capsule()
                        .fill(button.style == .primary
                              ? Color(red: 0, green: 0.533, blue: 1)
                              : Color(.secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }
}
