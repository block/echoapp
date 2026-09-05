import AppKit
import SwiftUI

// MARK: - Echo Colors

public extension Color {
    struct Echo {
        public struct Text {
            public static let foreground = Color(hexLight: 0x272727, dark: 0xDEDEDE)
        }

        public struct SegmentedControl {
            public static let selectedBackground = Color(hexLight: 0x000000, dark: 0xFFFFFF, alpha: 0.1)
            public static let hoverBackground = Color(hexLight: 0x333333, dark: 0xCCCCCC, alpha: 0.1)

            public static let text = Color(hexLight: 0x6B6461, dark: 0xBFB7B6)
            public static let selectedText = Color(hexLight: 0x3E3C3B, dark: 0xEDEDED)

        }

        public struct Toolbar {
            public static let background = Color(hexLight: 0xEAE3E0, dark: 0x4A4444)
            public static let hoverBackground = Color(hexLight: 0xEAE3E0, dark: 0x4A4444)
        }

        public struct Inspector {
            public static let background = Color(hexLight: 0xF2EDEB, dark: 0x362A26)
        }

        public struct Token {
            public static let enabled = Color(hexLight: 0x00D54B, dark: 0x00522E)
            public static let disabled = Color(hexLight: 0xEAE3E0, dark: 0x4A4444)
        }
    }
}

// MARK: - Dynamic Hex Color

private extension Color {
    init(hexLight: UInt, dark: UInt, alpha: CGFloat = 1.0) {
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(
                from: [.aqua, .darkAqua]
            ) == .aqua ? NSColor(hex: hexLight, alpha: alpha) : NSColor(hex: dark, alpha: alpha)
        }
        self.init(color)
    }
}

extension NSColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 08) & 0xff) / 255,
            blue: CGFloat((hex >> 00) & 0xff) / 255,
            alpha: alpha
        )
    }
}

// MARK: - SwiftUI System Colors

// MacOS specific colors taken from: https://github.com/diniska/swiftui-system-colors/
//
// Copyright (c) 2020 Denis
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

private typealias PlatformColor = NSColor

// MARK: - Adaptable colors

// https://developer.apple.com/documentation/appkit/nscolor/standard_colors
public extension Color {
    /// A blue color that automatically adapts to the current trait environment.
    static var systemBlue: Color { Color(PlatformColor.systemBlue) }
    /// A brown color that automatically adapts to the current trait environment.
    static var systemBrown: Color { Color(PlatformColor.systemBrown) }
    /// A cyan color that automatically adapts to the current trait environment.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, *)
    static var systemCyan: Color { Color(PlatformColor.systemCyan) }
    /// A green color that automatically adapts to the current trait environment.
    static var systemGreen: Color { Color(PlatformColor.systemGreen) }
    /// An indigo color that automatically adapts to the current trait environment.
    static var systemIndigo: Color { Color(PlatformColor.systemIndigo) }
    /// A mint color that automatically adapts to the current trait environment.
    @available(iOS 15.0, macOS 10.15, tvOS 15.0, *)
    static var systemMint: Color { Color(PlatformColor.systemMint) }
    /// An orange color that automatically adapts to the current trait environment.
    static var systemOrange: Color { Color(PlatformColor.systemOrange) }
    /// A pink color that automatically adapts to the current trait environment.
    static var systemPink: Color { Color(PlatformColor.systemPink) }
    /// A purple color that automatically adapts to the current trait environment.
    static var systemPurple: Color { Color(PlatformColor.systemPurple) }
    /// A red color that automatically adapts to the current trait environment.
    static var systemRed: Color { Color(PlatformColor.systemRed) }
    /// A teal color that automatically adapts to the current trait environment.
    static var systemTeal: Color { Color(PlatformColor.systemTeal) }
    /// A yellow color that automatically adapts to the current trait environment.
    static var systemYellow: Color { Color(PlatformColor.systemYellow) }
}

// MARK: - Adaptable Gray Colors

// https://developer.apple.com/documentation/appkit/nscolor/standard_colors
public extension Color {
    /// The standard base gray color that adapts to the environment.
    static var systemGray: Color { Color(PlatformColor.systemGray) }
}

// MARK: - Fixed Colors

// https://developer.apple.com/documentation/appkit/nscolor/standard_colors

public extension Color {
    /// A color object with a grayscale value of 1/3 and an alpha value of 1.0.
    static var darkGray: Color { Color(PlatformColor.darkGray) }
    /// A color object with a grayscale value of 2/3 and an alpha value of 1.0.
    static var lightGray: Color { Color(PlatformColor.lightGray) }
    /// A color object with RGB values of 1.0, 0.0, and 1.0, and an alpha value of 1.0.
    static var magenta: Color { Color(PlatformColor.magenta) }
}

// MARK: - UI Element Colors

// https://developer.apple.com/documentation/appkit/nscolor/ui_element_colors

public extension Color {
    // MARK: - Label Colors

    /// The primary color to use for text labels.
    static var label: Color { Color(PlatformColor.labelColor) }
    /// The secondary color to use for text labels.
    static var secondaryLabel: Color { Color(PlatformColor.secondaryLabelColor) }
    /// The tertiary color to use for text labels.
    static var tertiaryLabel: Color { Color(PlatformColor.tertiaryLabelColor) }
    /// The quaternary color to use for text labels and separators.
    static var quaternaryLabel: Color { Color(PlatformColor.quaternaryLabelColor) }

    // MARK: - Text Colors

    /// The color to use for text.
    static var text: Color { Color(PlatformColor.textColor) }
    /// The color to use for placeholder text in controls or text views.
    static var placeholderText: Color { Color(PlatformColor.placeholderTextColor) }
    /// The color to use for selected text.
    static var selectedText: Color { Color(PlatformColor.selectedTextColor) }
    /// The color to use for the background area behind text.
    static var textBackground: Color { Color(PlatformColor.textBackgroundColor) }
    /// The color to use for the background of selected text.
    static var selectedTextBackground: Color { Color(PlatformColor.selectedTextBackgroundColor) }
    /// The color to use for the keyboard focus ring around controls.
    static var keyboardFocusIndicator: Color { Color(PlatformColor.keyboardFocusIndicatorColor) }
    /// The color to use for selected text in an unemphasized context.
    static var unemphasizedSelectedText: Color { Color(PlatformColor.unemphasizedSelectedTextColor) }
    /// The color to use for the text background in an unemphasized context.
    static var unemphasizedSelectedTextBackground: Color { Color(PlatformColor.unemphasizedSelectedTextBackgroundColor) }

    // MARK: - Content Colors

    /// The color to use for links.
    static var link: Color { Color(PlatformColor.linkColor) }
    /// The color to use for separators between different sections of content.
    static var separator: Color { Color(PlatformColor.separatorColor) }
    /// The color to use for the background of selected and emphasized content.
    static var selectedContentBackground: Color { Color(PlatformColor.selectedContentBackgroundColor) }
    /// The color to use for selected and unemphasized content.
    static var unemphasizedSelectedContentBackground: Color { Color(PlatformColor.unemphasizedSelectedContentBackgroundColor) }

    // MARK: - Menu Colors

    /// The color to use for the text in menu items.
    static var selectedMenuItemText: Color { Color(PlatformColor.selectedMenuItemTextColor) }

    // MARK: - Table Colors

    /// The color to use for the optional gridlines, such as those in a table view.
    static var grid: Color { Color(PlatformColor.gridColor) }
    /// The color to use for text in header cells in table views and outline views.
    static var headerText: Color { Color(PlatformColor.headerTextColor) }
    /// The colors to use for alternating content, typically found in table views and collection views.
    static var alternatingContentBackgroundColors: [Color] { PlatformColor.alternatingContentBackgroundColors.map(Color.init) }

    // MARK: - Control Colors

    /// The user's current accent color preference.
    static var controlAccent: Color { Color(PlatformColor.controlAccentColor) }
    /// The color to use for the flat surfaces of a control.
    static var control: Color { Color(PlatformColor.controlColor) }
    /// The color to use for the background of large controls, such as scroll views or table views.
    static var controlBackground: Color { Color(PlatformColor.controlBackgroundColor) }
    /// The color to use for text on enabled controls.
    static var controlText: Color { Color(PlatformColor.controlTextColor) }
    /// The color to use for text on disabled controls.
    static var disabledControlText: Color { Color(PlatformColor.disabledControlTextColor) }
    /// The color to use for the face of a selected control—that is, a control that has been clicked or is being dragged.
    static var selectedControl: Color { Color(PlatformColor.selectedControlColor) }
    /// The color to use for text in a selected control—that is, a control being clicked or dragged.
    static var selectedControlText: Color { Color(PlatformColor.selectedControlTextColor) }
    /// The color to use for text in a selected control.
    static var alternateSelectedControlText: Color { Color(PlatformColor.alternateSelectedControlTextColor) }
    /// The patterned color to use for the background of a scrubber control.
    static var scrubberTexturedBackground: Color { Color(PlatformColor.scrubberTexturedBackground) }

    // MARK: - Window Colors

    /// The color to use for the window background.
    static var windowBackground: Color { Color(PlatformColor.windowBackgroundColor) }
    /// The color to use for text in a window's frame.
    static var windowFrameText: Color { Color(PlatformColor.windowFrameTextColor) }
    /// The color to use in the area beneath your window's views.
    static var underPageBackground: Color { Color(PlatformColor.underPageBackgroundColor) }

    // MARK: - Highlights and Shadows

    /// The highlight color to use for the bubble that shows inline search result values.
    static var findHighlight: Color { Color(PlatformColor.findHighlightColor) }
    /// The color to use as a virtual light source on the screen.
    static var highlight: Color { Color(PlatformColor.highlightColor) }
    /// The color to use for virtual shadows cast by raised objects on the screen.
    static var shadow: Color { Color(PlatformColor.shadowColor) }
}
