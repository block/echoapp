import Combine
import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public final class KeyValueStoreDesktopPlugin: DesktopPlugin {
    
    // MARK: - DesktopPlugin
    
    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)
    
    private let viewModel = KeyValueStoreViewModel()
    
    public init() {}
    
    public func makeView() -> AnyView {
        AnyView(KeyValueStoreView(viewModel: viewModel))
    }
    
    public func onConnect(_ connection: PluginConnection) {
        viewModel.setupConnection(connection)
        viewModel.requestSnapshot()
    }
    
    public func onDisconnect() {
        viewModel.disconnect()
    }
}
