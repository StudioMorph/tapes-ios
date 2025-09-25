import SwiftUI

struct Tokens {
    struct Colors {
        static let brandRed = Color(hex: 0xE50914)
        static let bg       = Color.dynamic(light: 0xFFFFFF, dark: 0x0B0B0F)
        static let surface  = Color.dynamic(light: 0xF2F4F7, dark: 0x15181D)
        static let elevated = Color.dynamic(light: 0xEEF1F5, dark: 0x1E2229)
        static let text     = Color.dynamic(light: 0x0B0B0F, dark: 0xFFFFFF)
        static let muted    = Color.dynamic(light: 0x6B7280, dark: 0x9CA3AF)
        static let border   = Color.dynamic(light: 0xE5E7EB, dark: 0x2A2F36)
        static let onAccent = Color.white
    }
    
    struct Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    struct Radius {
        static let card: CGFloat = 16
        static let sheet: CGFloat = 20
        static let fab: CGFloat = 32
    }
    
    struct Typography {
        static func headline(_ c: Color) -> some View { 
            TextStyle(size: 24, weight: .semibold, color: c) 
        }
        static func title(_ c: Color) -> some View { 
            TextStyle(size: 18, weight: .semibold, color: c) 
        }
        static func body(_ c: Color) -> some View { 
            TextStyle(size: 16, weight: .regular, color: c) 
        }
        static func caption(_ c: Color) -> some View { 
            TextStyle(size: 12, weight: .regular, color: c) 
        }
    }
}

extension Color {
    init(hex: Int) {
        self.init(.sRGB, 
                 red: Double((hex >> 16) & 0xFF) / 255, 
                 green: Double((hex >> 8) & 0xFF) / 255, 
                 blue: Double(hex & 0xFF) / 255, 
                 opacity: 1)
    }
    
    static func dynamic(light: Int, dark: Int) -> Color {
        Color(UIColor { tc in
            let hex = (tc.userInterfaceStyle == .dark) ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct TextStyle: View {
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    
    var body: some View { 
        EmptyView() // marker; use .font(.system(size:..., weight:...)).foregroundStyle(color)
    }
}