import AppKit
import SwiftUI

public struct ScrollableText: NSViewRepresentable {
    public typealias NSViewType = ScrollableNSTextView

    let text: String
    let shouldHighlight: Bool
    let fontSize: CGFloat

    public init(
        _ text: String,
        shouldHighlight: Bool,
        fontSize: CGFloat
    ) {
        self.text = text
        self.shouldHighlight = shouldHighlight
        self.fontSize = fontSize
    }

    public func makeNSView(context: NSViewRepresentableContext<Self>) -> NSViewType {
        let scrollableTextView = NSViewType()
        scrollableTextView.isEditable = false
        return scrollableTextView
    }

    public func updateNSView(_ scrollableTextView: NSViewType, context: NSViewRepresentableContext<Self>) {
        let currentText = scrollableTextView.text
        let currentFont = (currentText.length == 0)
            ? nil
            : scrollableTextView.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        let textChanged = currentText.string != text
        let fontChanged = currentFont?.pointSize != fontSize

        if textChanged || fontChanged {
            scrollableTextView.text = text.toNSAttributedString(
                shouldHighlight: shouldHighlight,
                fontSize: fontSize
            )
        }
    }
}

// MARK: -

/// A scrollable text view.
/// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextUILayer/Tasks/TextInScrollView.html
@objc public final class ScrollableNSTextView: NSScrollView {

    private final class TextView: NSTextView, NSTextFinderClient {}

    private let textView: TextView
    private let textFinder = NSTextFinder()

    private var eventMonitor: Any?

    // MARK: - Life Cycle

    override init(frame frameRect: NSRect) {
        textView = TextView(frame: NSRect(origin: .zero, size: frameRect.size))

        super.init(frame: frameRect)

        // Setup scroll view
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalRuler = false
        autoresizingMask = [.width, .height]

        // Set up text view
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainerInset = .init(width: 8, height: 16)

        textView.textContainer!.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer!.widthTracksTextView = true

        // Set up find bar
        findBarPosition = .aboveContent
        textFinder.isIncrementalSearchingEnabled = true
        textFinder.incrementalSearchingShouldDimContentView = true
        textFinder.findBarContainer = self
        textFinder.client = textView

        enableKeyboardShortcuts()

        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        disableKeyboardShortcuts()
    }

    // MARK: - Public Methods

    var text: NSAttributedString {
        get {
            textView.attributedString()
        }
        set {
            if isFindBarVisible {
                // The text is changing while the find bar is still visible. Prepare the find bar for the text change.
                textFinder.cancelFindIndicator()
                textFinder.noteClientStringWillChange()

                // Re-trigger the find bar to search the new text.
                // This needs to occur after the textView has laid out the new text.
                RunLoop.main.schedule(showFindBar)
            }

            textView.string = ""
            textView.textStorage?.append(newValue)
        }
    }

    var font: NSFont? {
        get { textView.font }
        set { textView.font = newValue }
    }

    var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    // MARK: - NSView

    public override func layout() {
        super.layout()
        findBarView?.frame.size.width = bounds.size.width
    }

    // MARK: - Find Commands

    private func showFindBar() {
        textFinder.performAction(.showFindInterface)
    }

    private func findNextMatch() {
        textFinder.performAction(.nextMatch)
    }

    private func findPreviousMatch() {
        textFinder.performAction(.previousMatch)
    }

    // MARK: - Private Methods

    private func enableKeyboardShortcuts() {
        disableKeyboardShortcuts()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  isTextViewFirstResponder || isFindBarFirstResponder
            else {
                return event
            }

            switch event.characters {
            case "f":
                showFindBar()
                return nil

            case "g":
                if event.modifierFlags.contains(.shift) {
                    findPreviousMatch()
                } else {
                    findNextMatch()
                }
                return nil

            default:
                return event
            }
        }
    }

    private func disableKeyboardShortcuts() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private var isTextViewFirstResponder: Bool {
        textView.window?.firstResponder == textView
    }

    private var isFindBarFirstResponder: Bool {
        findBarView?.isAnySubviewFirstResponder ?? false
    }
}

// MARK: -

private extension NSView {

    var isAnySubviewFirstResponder: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }
        if firstResponder == self {
            return true
        }
        return subviews.first(where: \.isAnySubviewFirstResponder) != nil
    }

}
