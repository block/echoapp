import AppKit
import SwiftUI

struct ActivityIndicator: NSViewRepresentable {

    typealias NSViewType = NSProgressIndicator

    let controlSize: NSControl.ControlSize
    let appearance: NSAppearance?
    let isAnimating = true

    init(controlSize: NSControl.ControlSize = .regular, appearance: NSAppearance? = nil) {
        self.controlSize = controlSize
        self.appearance = appearance
    }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSProgressIndicator {
        let nsView = NSProgressIndicator()
        nsView.style = .spinning
        return nsView
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: NSViewRepresentableContext<Self>) {
        nsView.controlSize = controlSize
        nsView.appearance = appearance

        if isAnimating {
            nsView.startAnimation(nil)
        } else {
            nsView.stopAnimation(nil)
        }
    }
}
