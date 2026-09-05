import Highlight
import SwiftUI

public struct HighlightedSyntaxView: View {
    @Environment(\.colorScheme) var colorScheme

    public let headerLabel: String?
    public let language: String
    public let code: String
    private let showHeader: Bool
    
    private let maxCodeLengthForHighlighting = 15000

    public init(code: String, language: String, headerLabel: String? = nil, showHeader: Bool = true) {
        self.code = code
        self.language = language
        self.headerLabel = headerLabel
        self.showHeader = showHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                headerView
            }
            codeView
        }
        .frame(maxWidth: .infinity)
        .background(EchoTheme.Colors.background)
        .cornerRadius(EchoTheme.CornerRadius.large)
    }
    
    private var headerView: some View {
        HStack {
            Text(headerLabel ?? language)
                .foregroundColor(.tertiaryLabel)
            Spacer()
            Text("\(code.count)")
                .foregroundColor(.tertiaryLabel)
                .help("Character Count")
            CopyButton { pasteboard in
                pasteboard.setString(code, forType: .string)
            }
        }
        .font(.system(size: EchoTheme.FontSize.small, weight: .medium, design: .rounded))
        .padding(.horizontal, EchoTheme.Spacing.medium)
        .padding(.vertical, EchoTheme.Spacing.small)
        .background(Color(white: 0.0, opacity: EchoTheme.Opacity.light))
        .cornerRadius(EchoTheme.CornerRadius.small)
    }
    
    private var codeView: some View {
        HStack {
            if code.count < maxCodeLengthForHighlighting {
                Text(AttributedString(SyntaxHighlighter.shared.highlight(code)))
                    .textSelection(.enabled)
            } else {
                Text(code)
                    .font(.system(size: EchoTheme.FontSize.medium, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(EchoTheme.Spacing.large)
    }
}
