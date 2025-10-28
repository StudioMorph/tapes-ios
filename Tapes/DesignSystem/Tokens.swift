import SwiftUI

public struct Tokens {
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }
    
    public enum Radius {
        public static let card: CGFloat = 20
        public static let thumb: CGFloat = 12
        public static let fab: CGFloat = 999
    }
    
    public enum FAB {
        public static let size: CGFloat = 64
    }
    
    public enum Colors {
        // Custom adaptive background colors with specific hex values
        public static let primaryBackground = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#14202F") : UIColor(hex: "#FFFFFF")
        })
        public static let secondaryBackground = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#1A293B") : UIColor(hex: "#F3F5F8")
        })
        public static let tertiaryBackground = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#223347") : UIColor(hex: "#E2E7EF")
        })
        
        // System colors for text (adapts automatically)
        public static let primaryText = Color.primary
        public static let secondaryText = Color.secondary
        public static let tertiaryText = Color(.tertiaryLabel)
        
        // Interactive/accent colors
        public static let systemRed = Color(hex: "#E50914")
        public static let systemBlue = Color.blue
        
        // Legacy tokens for backward compatibility
        public static let bg = primaryBackground
        public static let card = secondaryBackground
        public static let elevated = secondaryBackground
        public static let red = systemRed
        public static let onSurface = primaryText
        public static let muted = secondaryText
    }
    
    public enum Typography {
        public static let largeTitle = Font.largeTitle
        public static let title = Font.title2
        public static let headline = Font.headline
        public static let body = Font.body
        public static let caption = Font.caption
        public static let caption2 = Font.caption2
    }
    
    public enum HitTarget {
        public static let minimum: CGFloat = 44
        public static let recommended: CGFloat = 48
    }
    
    public enum Timing {
        public static let photoDefaultDuration: TimeInterval = 3.0
    }
}

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}