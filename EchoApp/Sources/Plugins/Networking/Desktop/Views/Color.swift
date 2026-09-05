import EchoPluginUI
import SwiftUI

extension Color {
    public enum Fakelin {
        public static let text = Color.text
        public static let selectedText = Color.white

        public static let background = Color.textBackground
        public static let selectedBackground = Color.selectedContentBackground

        public static let windowPaneBackground = Color.windowBackground

        // Matching the accessory views
        public static let successGreen = Color(red: 40/255, green: 202/255, blue: 65/255)
        public static let failedRed = Color(red: 253/255, green: 73/255, blue: 67/255)
    }
}
