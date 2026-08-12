import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Central Design System for FocusGuard macOS Native Application
public struct FocusGuardTheme {
    // MARK: - Color System (Semantic Tokens)
    public struct Colors {
        // Deep background surfaces
        public static let background = Color(red: 0.043, green: 0.059, blue: 0.090) // #0B0F17
        public static let surface = Color(red: 0.086, green: 0.114, blue: 0.165)    // #161D2A
        public static let surfaceElevated = Color(red: 0.122, green: 0.161, blue: 0.239) // #1F293D
        public static let border = Color(red: 0.176, green: 0.220, blue: 0.302)     // #2D384D

        // Accent / Brand Colors
        public static let accent = Color(red: 0.231, green: 0.510, blue: 0.965)     // #3B82F6 (Electric Blue)
        public static let indigo = Color(red: 0.388, green: 0.400, blue: 0.945)     // #6366F1
        public static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)     // #8B5CF6

        // Semantic Feedback States
        public static let success = Color(red: 0.063, green: 0.725, blue: 0.506)    // #10B981 (Emerald)
        public static let warning = Color(red: 0.961, green: 0.620, blue: 0.043)    // #F59E0B (Amber)
        public static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)     // #EF4444 (Rose/Red)
        public static let info = Color(red: 0.235, green: 0.706, blue: 0.965)       // #38BDF8 (Sky Blue)

        // Neutral Typography Colors
        public static let textPrimary = Color(red: 0.973, green: 0.980, blue: 0.988) // #F8FAFC
        public static let textSecondary = Color(red: 0.580, green: 0.639, blue: 0.722) // #94A3B8
        public static let textMuted = Color(red: 0.392, green: 0.455, blue: 0.545)     // #64748B
    }

    // MARK: - Radius Tokens
    public struct Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let full: CGFloat = 999
    }

    // MARK: - Spacing Tokens
    public struct Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
    }
}
