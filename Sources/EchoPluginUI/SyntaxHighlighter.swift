import Foundation
import Highlight

public final class SyntaxHighlighter {
    public static let shared = SyntaxHighlighter()

    public init() {}

    public func highlight(_ code: String, fontSize: CGFloat = 11) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(string: code)
        let highlighter = JsonSyntaxHighlightProvider(theme: DefaultJsonSyntaxHighlightingTheme(fontSize: fontSize))
        highlighter.highlight(mutableAttributedString, as: .json)
        return mutableAttributedString
    }
}
