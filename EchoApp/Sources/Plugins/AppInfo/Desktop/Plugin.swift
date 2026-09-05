import AppKit
import Combine
import EchoPluginAPI
import SwiftUI

public final class AppInfoDesktopPlugin: DesktopPlugin {

    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)
    
    // MARK: - Private Properties

    private var cancellables: Set<AnyCancellable> = []
    private let viewModel = AppInfoViewModel()

    // MARK: - Plugin

    public init() {}

    public func makeView() -> AnyView {
        AnyView(
            AppInfoView(viewModel: self.viewModel)
        )
    }

    public func onConnect(_ connection: PluginConnection) {
        connection.receive([Entry].self)
            .receive(on: DispatchQueue.main)
            .sink { [viewModel] entries in
                viewModel.entries = entries
            }.store(in: &cancellables)
    }

    public func onDisconnect() {
        cancellables = []
    }

}

extension AppInfoDesktopPlugin: DeepLinkHandler {

    public func handleDeepLink(path: String, queryItems: [URLQueryItem]) -> Bool {
        switch path {
        case "search":
            guard let query = queryItems.unquotedValue(forKey: "query") else {
                return false
            }
            self.viewModel.searchText = query
            return true
        default:
            return false
        }
    }
}
