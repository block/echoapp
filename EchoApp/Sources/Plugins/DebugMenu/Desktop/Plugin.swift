import Combine
import DebugMenuPluginAPI
import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public final class DebugMenuDesktopPlugin: DesktopPlugin {

    // MARK: - DesktopPlugin

    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)

    let viewModel = DebugMenuViewModel()

    public init() {}

    public func makeView() -> AnyView {
        AnyView(DebugMenuView(viewModel: viewModel))
    }

    public func onConnect(_ connection: PluginConnection) {
        Task { @MainActor in
            viewModel.setupConnection(connection)
            viewModel.requestSnapshot()
        }
    }

    public func onDisconnect() {
        Task { @MainActor in
            viewModel.disconnect()
        }
    }
}
