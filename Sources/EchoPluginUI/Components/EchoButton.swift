import SwiftUI

public struct EchoButton: View {
    var title: String
    var buttonStyle: HoverButtonStyle
    var action: () -> Void

    public init(
        _ title: String,
        buttonStyle: HoverButtonStyle = .init(
            textColor: .controlText,
            backgroundColor: .clear,
            hoverTextColor: .alternateSelectedControlText,
            hoverBackgroundColor: .selectedContentBackground
        ),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.buttonStyle = buttonStyle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .cornerRadius(4)
        }
        .buttonStyle(buttonStyle)
    }
}

public struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false
    private var textColor: Color
    private var backgroundColor: Color
    private var hoverTextColor: Color
    private var hoverBackgroundColor: Color

    public init(
        textColor: Color = .controlText,
        backgroundColor: Color = .clear,
        hoverTextColor: Color = .link,
        hoverBackgroundColor: Color = Color.init(white: 0.5, opacity: 0.2)
    ) {
        self.textColor = textColor
        self.hoverTextColor = hoverTextColor
        self.hoverBackgroundColor = hoverBackgroundColor
        self.backgroundColor = backgroundColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .foregroundColor(isHovered ? hoverTextColor : textColor)
            .background(isHovered ? hoverBackgroundColor : backgroundColor)
            .cornerRadius(4)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

