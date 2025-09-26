import SwiftUI

public struct Tokens {
    public enum Spacing {
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
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
        public static let bg = Color(hex: "#0F172A")        // dark navy, not pure black
        public static let card = Color(hex: "#111827")       // slightly lighter than bg
        public static let elevated = Color(hex: "#1F2937")   // thumbnail tile
        public static let red = Color(hex: "#E50914")
        public static let onSurface = Color.white
        public static let muted = Color(hex: "#9CA3AF")      // muted text color
    }
    
    public enum Typography {
        public static let title = Font.system(size: 17, weight: .semibold)
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