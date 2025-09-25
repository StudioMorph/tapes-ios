import SwiftUI
import UIKit

// MARK: - Design Tokens

public struct Tokens {
    
    // MARK: - Colors
    
    public struct Colors {
        // Brand colors
        public static let brandRed = Color(UIColor(hex: "#E50914"))
        public static let textOnAccent = Color.white
        
        // Dynamic colors
        public static let bg = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#0B0B0F") : UIColor(hex: "#FFFFFF")
        })
        
        public static let surface = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#15181D") : UIColor(hex: "#F2F4F7")
        })
        
        public static let surfaceElevated = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#1E2229") : UIColor(hex: "#EEF1F5")
        })
        
        public static let textPrimary = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#FFFFFF") : UIColor(hex: "#0B0B0F")
        })
        
        public static let textMuted = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#9CA3AF") : UIColor(hex: "#6B7280")
        })
        
        public static let border = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#2A2F36") : UIColor(hex: "#E5E7EB")
        })
    }
    
    // MARK: - Spacing
    
    public struct Space {
        public static let s4: CGFloat = 4
        public static let s8: CGFloat = 8
        public static let s12: CGFloat = 12
        public static let s16: CGFloat = 16
        public static let s20: CGFloat = 20
        public static let s24: CGFloat = 24
        public static let s32: CGFloat = 32
    }
    
    // MARK: - Radius
    
    public struct Radius {
        public static let card: CGFloat = 16
        public static let sheet: CGFloat = 20
        public static let fab: CGFloat = 32
        public static let thumbnail: CGFloat = 8
    }
    
    // MARK: - Typography
    
    public struct Typography {
        public static let headline: Font = .system(size: 24, weight: .semibold)
        public static let title: Font = .system(size: 18, weight: .semibold)
        public static let body: Font = .system(size: 16, weight: .regular)
        public static let caption: Font = .system(size: 12, weight: .regular)
    }
}

// MARK: - UIColor Hex Helper

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

