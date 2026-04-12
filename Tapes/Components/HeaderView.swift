import SwiftUI

// MARK: - Tapes Logo

struct TapesLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var height: CGFloat = 28
    var suffix: String?
    var forceDark: Bool = false

    private var iconSize: CGFloat { height }
    private var fontSize: CGFloat { height * 1.2 }
    private var dotSize: CGFloat { height * 0.33 }
    private var cornerRadius: CGFloat { height * 0.3 }
    private var foregroundColor: Color {
        (forceDark || colorScheme == .dark) ? .white : Color(red: 0.15, green: 0.17, blue: 0.24)
    }

    var body: some View {
        HStack(spacing: height * 0.3) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(foregroundColor, lineWidth: height * 0.1)
                    .frame(width: iconSize, height: iconSize)

                Circle()
                    .fill(Tokens.Colors.systemRed)
                    .frame(width: dotSize, height: dotSize)
            }

            HStack(spacing: 0) {
                Text("TAPES")
                    .font(.system(size: fontSize, weight: .heavy, design: .default))
                    .foregroundStyle(foregroundColor)
                    .tracking(height * 0.02)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: fontSize, weight: .light, design: .default))
                        .foregroundStyle(foregroundColor)
                }
            }
        }
    }
}

#Preview {
    TapesLogo()
        .padding()
        .background(Tokens.Colors.primaryBackground)
}
