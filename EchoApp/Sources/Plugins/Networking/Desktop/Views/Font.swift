import SwiftUI

extension Font {
    public enum Fakelin {
        public static let sectionHeader = Font.system(size: 13, weight: .bold)
        public static let sectionHeaderSubtitle = Font(NSFont.Fakelin.code)
        public static let toolbar = Font.system(size: 11, weight: .regular)
    }
}

extension NSFont {
    public enum Fakelin {
        public static let code = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    }
}
