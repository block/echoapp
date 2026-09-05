import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public final class CrashReportingDesktopPlugin: DesktopPlugin {

    // MARK: - DesktopPlugin

    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)

    private let viewModel = CrashReportingViewModel()

    public init() {}

    public func makeView() -> AnyView {
        AnyView(CrashReportingView(viewModel: viewModel))
    }

    public func onConnect(_ connection: PluginConnection) {
        // Subscribe synchronously so reports replayed right after `onConnect` (imported archives)
        // aren't dropped before the subscription is installed.
        viewModel.connect(connection: connection)
    }

    public func onDisconnect() {
        viewModel.disconnect()
    }
}
