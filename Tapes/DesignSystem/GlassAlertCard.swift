import SwiftUI

struct GlassAlertButton {
    let title: String
    let style: Style
    let action: () -> Void

    enum Style {
        case secondary
        case primary
        case destructive
    }
}

struct GlassAlertCard<Icon: View, MessageContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let buttons: [GlassAlertButton]
    let icon: Icon
    let messageContent: MessageContent

    init(
        title: String,
        buttons: [GlassAlertButton],
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder message: () -> MessageContent
    ) {
        self.title = title
        self.buttons = buttons
        self.icon = icon()
        self.messageContent = message()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 10) {
                icon
                    .padding(.top, 14)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)

                    messageContent
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
        switch button.style {
        case .primary:
            Button {
                button.action()
            } label: {
                Text(button.title)
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .tint(Color(red: 0, green: 0.533, blue: 1))
            .layoutPriority(1)

        case .secondary:
            Button {
                button.action()
            } label: {
                Text(button.title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .buttonBorderShape(.capsule)

        case .destructive:
            Button(role: .destructive) {
                button.action()
            } label: {
                Text(button.title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }
}

extension GlassAlertCard where Icon == AnyView, MessageContent == AnyView {
    init(
        systemImage: String,
        iconSize: CGFloat = 48,
        title: String,
        message: String,
        buttons: [GlassAlertButton]
    ) {
        self.init(
            title: title,
            buttons: buttons,
            icon: {
                AnyView(
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(Color.primary)
                )
            },
            message: {
                AnyView(
                    Text(message)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                )
            }
        )
    }
}
