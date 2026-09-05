import EchoPluginAPI
import Foundation
import SwiftUI

final class TestDesktopPlugin: DesktopPlugin {
    let metadata: DesktopPluginMetadata

    convenience init() {
        self.init(id: UUID().uuidString)
    }

    init(id: String) {
        metadata = DesktopPluginMetadata(
            id: id,
            version: "",
            category: .data,
            displayName: "",
            icon: Image(systemName: "circle"),
            description: ""
        )
    }

    func makeView() -> AnyView {
        AnyView(EmptyView())
    }

    func onConnect(_ connection: PluginConnection) {}

    func onDisconnect() {}
}
