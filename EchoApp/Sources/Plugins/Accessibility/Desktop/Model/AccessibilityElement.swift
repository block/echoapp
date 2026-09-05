import Foundation

public struct AccessibilityElement: Codable, Equatable {
    /// The description of the accessibility element that will be read by VoiceOver when the element is brought into
    /// focus.
    public var description: String

    /// A unique identifier for the element, primarily used in UI tests for locating and interacting with elements.
    /// This identifier is not visible to users.
    public var identifier: String?

    /// A hint that will be read by VoiceOver if focus remains on the element after the `description` is read.
    public var hint: String?

    /// The labels that will be used by Voice Control for user input.
    public var userInputLabels: [String]?

    /// The names of the custom actions supported by the element.
    public var customActions: [String]

    var frame: Rect
}

public struct Rect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var displayValues: [String] {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        return [
            "X: \(formatter.string(from: NSNumber(value: x)) ?? "-")",
            "Y: \(formatter.string(from: NSNumber(value: y)) ?? "-")",
            "Width: \(formatter.string(from: NSNumber(value: width)) ?? "-")",
            "Height: \(formatter.string(from: NSNumber(value: height)) ?? "-")",
        ]
    }
}
