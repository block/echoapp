import AppKit
import SwiftUI

// Custom NSPanel subclass to act as a floating panel
class FloatingPanel<Content: View>: NSPanel {
    @Binding var isPresented: Bool

    init(view: @escaping () -> Content, contentRect: NSRect, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .resizable,
                .closable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior.insert(.fullScreenAuxiliary)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = true

        // Hide window buttons
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        animationBehavior = .default
        contentView = NSHostingView(rootView: view().ignoresSafeArea())
    }

    override func resignMain() {
        super.resignMain()
        close()
    }

    override func close() {
        super.close()
        isPresented = false
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}

struct FloatingPanelModifier<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var contentRect: CGRect = CGRect(x: 0, y: 0, width: 624, height: 512)
    @ViewBuilder let view: () -> PanelContent
    @State var panel: FloatingPanel<PanelContent>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                panel = FloatingPanel(
                    view: view,
                    contentRect: contentRect,
                    isPresented: $isPresented
                )
                panel?.center()
                panel?.backgroundColor = .clear
                if isPresented { present() }
            }
            .onDisappear {
                panel?.close()
                panel = nil
            }
            .onChange(of: isPresented) { oldValue, newValue in
                if newValue { present() }
                else { panel?.close() }
            }
    }

    private func present() {
        panel?.orderFront(nil)
        panel?.makeKey()
    }
}

extension View {
    func floatingPanel<Content: View>(
        isPresented: Binding<Bool>,
        contentRect: CGRect = CGRect(x: 0, y: 0, width: 624, height: 512),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(
            FloatingPanelModifier(
                isPresented: isPresented,
                contentRect: contentRect,
                view: content
            )
        )
    }
}
