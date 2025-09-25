import SwiftUI

public enum DesignTokens {
    public enum Colors {
        public static let primaryRed: Color = Color(hex: "#E50914")
        public static let secondaryGray: Color = Color(hex: "#222222")

        public static func surface(_ colorScheme: ColorScheme) -> Color {
            switch colorScheme {
            case .dark:
                return Color(hex: "#0B0B0F")
            default:
                return Color(hex: "#FFFFFF")
            }
        }

        public static func onSurface(_ colorScheme: ColorScheme) -> Color {
            switch colorScheme {
            case .dark:
                return Color(hex: "#FFFFFF")
            default:
                return Color(hex: "#0B0B0F")
            }
        }

        // Muted grayscale ramp (8–96)
        // Usage: Colors.muted(8), Colors.muted(16), ..., Colors.muted(96)
        public static func muted(_ value: Int) -> Color {
            let clamped = max(8, min(96, value))
            let white = Double(clamped) / 100.0
            return Color(.sRGB, white: white, opacity: 1.0)
        }
    }

    public enum Typography {
        // Heading / Headline: 20–24pt, Semibold/Bold
        public static func heading(_ size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
            Font.system(size: size, weight: weight, design: .default)
        }

        // Title: 18pt Semibold
        public static var title: Font { Font.system(size: 18, weight: .semibold, design: .default) }

        // Body: 16pt Regular
        public static var body: Font { Font.system(size: 16, weight: .regular, design: .default) }

        // Caption: 12pt Regular
        public static var caption: Font { Font.system(size: 12, weight: .regular, design: .default) }
    }

    public enum Spacing {
        public static let s4: CGFloat = 4
        public static let s8: CGFloat = 8
        public static let s12: CGFloat = 12
        public static let s16: CGFloat = 16
        public static let s20: CGFloat = 20
        public static let s24: CGFloat = 24
        public static let s32: CGFloat = 32
    }

    public enum Radius {
        // Cards
        public static let card: CGFloat = 12
        // Sheets
        public static let sheet: CGFloat = 20
        // Thumbnails
        public static let thumbnail: CGFloat = 8
        // Full (FAB) — large value to achieve full rounding in cornerRadius APIs
        public static let full: CGFloat = .greatestFiniteMagnitude
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        let r, g, b, a: CGFloat
        var hexColor = hex
        if hexColor.hasPrefix("#") {
            hexColor.removeFirst()
        }

        var rgbaValue: UInt64 = 0
        Scanner(string: hexColor).scanHexInt64(&rgbaValue)

        switch hexColor.count {
        case 8: // RRGGBBAA
            r = CGFloat((rgbaValue & 0xFF000000) >> 24) / 255
            g = CGFloat((rgbaValue & 0x00FF0000) >> 16) / 255
            b = CGFloat((rgbaValue & 0x0000FF00) >> 8) / 255
            a = CGFloat(rgbaValue & 0x000000FF) / 255
        case 6: // RRGGBB
            r = CGFloat((rgbaValue & 0xFF0000) >> 16) / 255
            g = CGFloat((rgbaValue & 0x00FF00) >> 8) / 255
            b = CGFloat(rgbaValue & 0x0000FF) / 255
            a = 1.0
        default:
            r = 1; g = 1; b = 1; a = 1
        }

        self = Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}


