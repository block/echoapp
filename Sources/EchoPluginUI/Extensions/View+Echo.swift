import AppKit
import SwiftUI

public extension View {
    func onHotKeyEvent(
        key: String,
        modifierFlags: NSEvent.ModifierFlags,
        action: @escaping () -> Void
    ) -> some View {
        self.modifier(
            KeyEventMonitorModifier(
                key: key,
                modifierFlags: modifierFlags,
                action: action
            )
        )
    }
}

struct KeyEventMonitorModifier: ViewModifier {
    @State private var monitor: Any?

    let key: String
    let modifierFlags: NSEvent.ModifierFlags
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                self.monitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown
                ) { event in
                    if event.modifierFlags.contains(modifierFlags) && event.charactersIgnoringModifiers == key {
                        action()
                        return nil // Prevents the event from being passed to the next responder
                    }
                    return event
                }
            }
            .onDisappear {
                // Remove the key event monitor when the view disappears
                if let monitor = self.monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}
