import AppKit
import EchoPluginUI

extension String {
    func toNSAttributedString(shouldHighlight: Bool, fontSize: CGFloat) -> NSAttributedString {
        if shouldHighlight {
            SyntaxHighlighter.shared.highlight(self, fontSize: fontSize)
        } else {
            NSAttributedString(
                string: self,
                attributes: [
                    .foregroundColor: NSColor.textColor,
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
                ]
            )
        }
    }
}
