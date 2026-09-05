import Combine
import EchoPluginAPI
import SwiftUI

public final class NavigationDesktopPlugin: DesktopPlugin {
    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)

    private let viewModel: NavigationViewModel

    public init() {
        let connectionSubject = CurrentValueSubject<PluginConnection?, Never>(nil)
        self.viewModel = NavigationViewModel(connection: connectionSubject)
    }

    public func makeView() -> AnyView {
        AnyView(NavigationView(viewModel: self.viewModel))
    }

    public func onConnect(_ connection: PluginConnection) {
        viewModel.connect(connection: connection)
    }

    public func onDisconnect() {
        viewModel.disconnect()
    }
}
