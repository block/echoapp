import SwiftUI

/// A reusable footer component for lists that displays item count, optional filter button, and action buttons.
///
/// The footer provides a consistent layout for list views with:
/// - Item count with proper pluralization
/// - Optional filter button with a popover menu
/// - Optional action buttons with tooltips
///
/// Example usage:
/// ```swift
/// EchoListFooterView(
///     itemCount: 42,
///     itemLabel: "event",
///     itemLabelPlural: "events",
///     actionButtons: [
///         .init(
///             iconName: "trash",
///             helpText: "Clear all events",
///             action: {}
///         )
///     ]
/// ) {
///     Button {
///         // Custom action
///     } label: {
///         Image(systemName: "plus")
///     }
///     .help("Add new item")
/// }
/// ```
public struct EchoListFooterView<Content: View>: View {
    /// The number of items in the list
    let itemCount: Int
    
    /// The singular form of the item label (e.g., "event")
    let itemLabel: String
    
    /// The plural form of the item label (e.g., "events")
    let itemLabelPlural: String
    
    /// Array of action buttons to display
    let actionButtons: [ActionButton]
    
    /// The content to display between the count and action buttons
    let content: Content
    
    /// Creates a new list footer.
    /// - Parameters:
    ///   - itemCount: The number of items in the list
    ///   - itemLabel: The singular form of the item label (e.g., "event")
    ///   - itemLabelPlural: The plural form of the item label (e.g., "events"). If not provided, will append "s" to the singular form
    ///   - actionButtons: Array of action buttons to display
    ///   - content: A view builder that creates the content to display between the count and action buttons
    public init(
        itemCount: Int,
        itemLabel: String,
        itemLabelPlural: String? = nil,
        actionButtons: [ActionButton] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.itemCount = itemCount
        self.itemLabel = itemLabel
        self.itemLabelPlural = itemLabelPlural ?? itemLabel + "s"
        self.actionButtons = actionButtons
        self.content = content()
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: EchoTheme.Spacing.medium) {
                countLabel
                Spacer()
                content
                actionButtonsView
            }
            .frame(height: 40)
            .padding(.horizontal, EchoTheme.Spacing.large)
        }
    }
    
    private var countLabel: some View {
        Text("\(itemCount) \(itemCount == 1 ? itemLabel : itemLabelPlural)")
            .font(.body)
            .foregroundStyle(EchoTheme.Colors.text)
    }
    
    private var actionButtonsView: some View {
        ForEach(actionButtons) { button in
            Button {
                button.action()
            } label: {
                HStack(spacing: EchoTheme.Spacing.small) {
                    if let iconName = button.iconName {
                        Image(systemName: iconName)
                            .bold()
                    }
                    if let text = button.text {
                        Text(text)
                    }
                }
            }
            .buttonStyle(FooterButtonStyle(hoverBackgroundColor: button.isDestructive ? .red : .accentColor))
            .help(button.helpText)
        }
    }
}

// MARK: - Supporting Types

public extension EchoListFooterView {
    /// Configuration for an action button in the footer
    struct ActionButton: Identifiable {
        /// Unique identifier for the action button
        public let id = UUID()
        
        /// Optional SF Symbol name for the button icon
        let iconName: String?
        
        /// Optional text to display on the button
        let text: String?
        
        /// The tooltip text shown when hovering over the button
        let helpText: String
        
        /// The color of the button's text/icon
        let textColor: Color

        /// Whether the button is destructive
        let isDestructive: Bool
        
        /// The action to perform when the button is clicked
        let action: () -> Void
        
        /// Creates a new action button
        /// - Parameters:
        ///   - iconName: Optional SF Symbol name for the button icon
        ///   - text: Optional text to display on the button
        ///   - helpText: The tooltip text shown when hovering over the button
        ///   - textColor: The color of the button's text/icon. Defaults to .secondary
        ///   - action: The action to perform when the button is clicked
        public init(
            iconName: String? = nil,
            text: String? = nil,
            helpText: String? = nil,
            textColor: Color? = nil,
            isDestructive: Bool? = nil,
            action: @escaping () -> Void
        ) {
            self.iconName = iconName
            self.text = text
            self.helpText = helpText ?? ""
            self.textColor = textColor ?? EchoTheme.Colors.selectedText
            self.isDestructive = isDestructive ?? false
            self.action = action
        }
    }
}

public struct FooterButtonStyle: ButtonStyle {

    public enum Metrics {
        static let fontSize: CGFloat = 12
    }

    @State private var isHovered = false
    private var textColor: Color
    private var backgroundColor: Color
    private var hoverTextColor: Color
    private var hoverBackgroundColor: Color

    public init(
        textColor: Color = EchoTheme.Colors.text,
        backgroundColor: Color = EchoTheme.Colors.background,
        hoverTextColor: Color = .white,
        hoverBackgroundColor: Color = .accentColor
    ) {
        self.textColor = textColor
        self.hoverTextColor = hoverTextColor
        self.hoverBackgroundColor = hoverBackgroundColor
        self.backgroundColor = backgroundColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, EchoTheme.Spacing.small)
            .padding(.horizontal, EchoTheme.Spacing.medium)
            .foregroundStyle(isHovered ? .white : textColor)
            .background(isHovered ? hoverBackgroundColor : backgroundColor)
            .cornerRadius(EchoTheme.CornerRadius.small)
            .font(.system(size: Metrics.fontSize))
            .overlay(
                RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.small)
                    .stroke(Color.primary.opacity(EchoTheme.Opacity.light), lineWidth: 0.5)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        EchoListFooterView(
            itemCount: 42,
            itemLabel: "event",
            itemLabelPlural: "events",
            actionButtons: [
                .init(
                    iconName: "trash",
                    helpText: "Clear all events",
                    action: {}
                ),
                .init(
                    text: "Copy",
                    helpText: "Copy to clipboard",
                    textColor: .blue,
                    action: {}
                )
            ]
        ) {
            Button {
                // Custom action
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: EchoTheme.FontSize.extraLarge))
                    .foregroundStyle(EchoTheme.Colors.text)
            }
            .help("Add new item")
            
            Menu {
                Button("All Events") {}
                Button("Network Events") {}
                Button("Custom Events") {}
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: EchoTheme.FontSize.extraLarge))
                    .foregroundStyle(EchoTheme.Colors.text)
            }
            .help("Filter events")
        }
        
        EchoListFooterView(
            itemCount: 1,
            itemLabel: "route",
            itemLabelPlural: "routes",
            actionButtons: [
                .init(
                    text: "Documentation",
                    helpText: "Open documentation",
                    textColor: .blue,
                    action: {}
                )
            ]
        ) {
            Button {
                // Custom action
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: EchoTheme.FontSize.extraLarge))
                    .foregroundStyle(EchoTheme.Colors.text)
            }
            .help("Refresh routes")
        }
    }
} 
