import SwiftUI

struct AppTheme {
    // Colors - Alpine Minimal Palette
    static let background = Color(hex: "F2EDE6")
    static let cardBackground = Color.white
    static let primary = Color(hex: "4A7C59") // Sage Green
    static let secondary = Color(hex: "7A7268")
    static let accent = Color(hex: "C85A1A") // Burnt Orange for Start Points
    static let textPrimary = Color(hex: "2A2420")
    static let textSecondary = Color(hex: "7A7268")
    
    // Shadows
    static let shadowRadius: CGFloat = 12
    static let shadowY: CGFloat = 4
    static let shadowColor = Color.black.opacity(0.08)
    
    // Corner Radius
    static let cornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16
    
    // Glassmorphism
    static let glassOpacity: CGFloat = 0.8
    static let glassBlur: CGFloat = 20
}

extension Color {
    init(hex: String) {
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

// Custom View Modifiers for Theme
struct AlpineCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cardCornerRadius)
            .shadow(color: AppTheme.shadowColor, radius: AppTheme.shadowRadius, x: 0, y: AppTheme.shadowY)
    }
}

extension View {
    func alpineCard() -> some View {
        self.modifier(AlpineCardStyle())
    }
}
