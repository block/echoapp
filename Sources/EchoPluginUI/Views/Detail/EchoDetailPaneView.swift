import SwiftUI

/// A reusable detail pane view that provides a consistent layout for displaying detailed information
/// with an optional header and footer.
///
/// Example usage:
/// ```swift
/// EchoDetailPaneView(
///     header: {
///         HStack {
///             Text("Active Journeys")
///                 .font(.system(size: EchoTheme.FontSize.medium, weight: .medium))
///                 .foregroundStyle(EchoTheme.Colors.text)
///             Spacer()
///             Text("None")
///                 .font(.system(size: EchoTheme.FontSize.medium))
///                 .foregroundStyle(.tertiary)
///                 .italic()
///         }
///     },
///     body: {
///         ScrollView {
///             Text("Content goes here")
///         }
///     },
///     footer: {
///         HStack {
///             Text("Footer content")
///         }
///     }
/// )
/// ```
public struct EchoDetailPaneView<Header: View, Body: View, Footer: View>: View {
    private let header: Header
    private let _body: Body
    private let footer: Footer
    
    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> Body,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self._body = body()
        self.footer = footer()
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            headerView
            bodyView
            footerView
        }
        .background(EchoTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium)
                .stroke(EchoTheme.Colors.text.opacity(EchoTheme.Opacity.light), lineWidth: 1)
        )
    }
    
    private var headerView: some View {
        header
            .padding(.horizontal, EchoTheme.Spacing.large)
            .padding(.vertical, EchoTheme.Spacing.mediumLarge)
            .background(EchoTheme.Colors.hoverBackground)
    }
    
    private var bodyView: some View {
        _body
            .padding(EchoTheme.Spacing.large)
    }
    
    private var footerView: some View {
        footer
            .padding(.horizontal, EchoTheme.Spacing.large)
            .padding(.vertical, EchoTheme.Spacing.medium)
            .background(EchoTheme.Colors.hoverBackground)
    }
}
