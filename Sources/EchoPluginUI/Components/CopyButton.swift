import SwiftUI

public struct CopyButton: View {
    public let copyBlock: (NSPasteboard) -> Bool
    public let buttonStyle: HoverButtonStyle
    @State private var copyText = Strings.defaultCopyText

    public init(buttonStyle: HoverButtonStyle = .init(), copyBlock: @escaping (NSPasteboard) -> Bool) {
        self.buttonStyle = buttonStyle
        self.copyBlock = copyBlock
    }

    public var body: some View {
        Button(copyText) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            // Update the button text based on the success of the copy operation.
            copyText = copyBlock(pasteboard) ? Strings.copiedText : Strings.failedText
            // Reset the button text after a delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copyText = Strings.defaultCopyText
            }
        }
        .buttonStyle(buttonStyle)
    }

    private enum Strings {
        static let defaultCopyText = "Copy"
        static let copiedText = "Copied!"
        static let failedText = "Failed!"
    }
}
