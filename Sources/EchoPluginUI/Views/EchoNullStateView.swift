import SwiftUI

/// A reusable view for displaying null states (empty states) in lists and other content areas.
///
/// The view provides a consistent layout for empty states with:
/// - A large icon
/// - A descriptive message
/// - Optional custom content below the message
///
/// Example usage:
/// ```swift
/// // Simple null state
/// EchoNullStateView(
///     iconName: "flowchart",
///     message: "Launch a blocker flow on a connected client to get started."
/// )
///
/// // With custom content
/// EchoNullStateView(
///     iconName: "flowchart",
///     message: "Launch a blocker flow on a connected client to get started."
/// ) {
///     Button("Get Started") {
///         // Handle action
///     }
///     .buttonStyle(.plain)
///     .foregroundStyle(.blue)
/// }
/// ```
public struct EchoNullStateView<Content: View>: View {
    /// The SF Symbol name for the icon
    let iconName: String
    
    /// The message to display
    let message: String
    
    /// The content to display below the message
    let content: Content
    
    /// Creates a new null state view.
    /// - Parameters:
    ///   - iconName: The SF Symbol name for the icon
    ///   - message: The message to display
    ///   - content: A view builder that creates the content to display below the message
    public init(
        iconName: String,
        message: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.iconName = iconName
        self.message = message
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .center, spacing: EchoTheme.Spacing.large) {
            Spacer()
            iconView
            messageView
            content
                .padding(.top, EchoTheme.Spacing.medium)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var iconView: some View {
        Image(systemName: iconName)
            .font(.title)
            .foregroundStyle(EchoTheme.Colors.text)
    }
    
    private var messageView: some View {
        Text(message)
            .font(.body)
            .foregroundStyle(EchoTheme.Colors.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 250)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        EchoNullStateView(
            iconName: "flowchart",
            message: "Launch a blocker flow on a connected client to get started."
        )
        
        EchoNullStateView(
            iconName: "doc.text.magnifyingglass",
            message: "No search results found. Try adjusting your search criteria."
        ) {
            HStack(spacing: EchoTheme.Spacing.medium) {
                Button("Clear Search") {
                    // Handle action
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                
                Button("Try Again") {
                    // Handle action
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }
} 