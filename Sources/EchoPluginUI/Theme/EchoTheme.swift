import SwiftUI

public enum EchoTheme {
    // MARK: - Spacing
    public enum Spacing {
        public static let small: CGFloat = 4
        public static let medium: CGFloat = 8
        public static let mediumLarge: CGFloat = 12
        public static let large: CGFloat = 16
        public static let extraLarge: CGFloat = 24
    }
    
    // MARK: - Font Sizes
    public enum FontSize {
        public static let small: CGFloat = 11
        public static let medium: CGFloat = 13
        public static let large: CGFloat = 15
        public static let extraLarge: CGFloat = 18
    }
    
    // MARK: - Corner Radius
    public enum CornerRadius {
        public static let small: CGFloat = 4
        public static let medium: CGFloat = 6
        public static let large: CGFloat = 10
        public static let extraLarge: CGFloat = 16
    }
    
    // MARK: - Opacity
    public enum Opacity {
        public static let subtle: Double = 0.05
        public static let light: Double = 0.1
        public static let medium: Double = 0.5
        public static let strong: Double = 0.7
    }
    
    // MARK: - Colors
    public enum Colors {
        public static let background = Color(white: 0.5, opacity: Opacity.subtle)
        public static let hoverBackground = Color(white: 0, opacity: Opacity.light)
        public static let selectedBackground = Color.primary.opacity(Opacity.light)
        public static let text = Color.secondary
        public static let selectedText = Color.primary
    }
} 
