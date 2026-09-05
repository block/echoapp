import SwiftUI

/// Presents a window
public protocol WindowPresenter {
    func presentWindow()
}

/// Presents a view in a new window
public final class DefaultWindowPresenter<V: View>: WindowPresenter {
    private let title: String
    private let viewFactory: () -> V

    /// Weak reference to the currently presented window, or nil if no window is presented.
    public weak var window: NSWindow?

    public init(
        title: String,
        viewFactory: @escaping () -> V
    ) {
        self.title = title
        self.viewFactory = viewFactory
    }

    public func presentWindow() {
        guard window == nil else {
            // Window already presented. Do nothing.
            return
        }

        let newWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = title
        newWindow.setFrameAutosaveName(.init(title))
        newWindow.contentView = NSHostingView(rootView: viewFactory())
        newWindow.center()

        // No need to release when closed since we aren't strongly retaining the window.
        // Our weak reference will allow the window to deallocate normally when closed.
        newWindow.isReleasedWhenClosed = false

        newWindow.makeKeyAndOrderFront(nil)

        self.window = newWindow
    }

}
