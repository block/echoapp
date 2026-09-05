import AppKit
import Combine
import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public final class LoggingDesktopPlugin: DesktopPlugin {

    // MARK: - Plugin

    private static let id = "com.echo.plugin.logging"
    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)
    private let viewModel: EchoTableViewModel
    @State private var monitor: Any?

    public init() {
        self.viewModel = .init(
            configuration: .init(
                customColumnConfiguration: [
                    EchoColumnKey(id: "Time", width: 100),
                    EchoColumnKey(id: "Level", width: 50, isFilterable: true),
                    EchoColumnKey(id: "Priority", width: 50, isFilterable: true),
                    EchoColumnKey(id: "Message", width: 300)
                ],
                maxRowCount: 2000,
                detailViewTitleKey: "Message",
                monospacedFont: true,
                itemLabel: "log"
            ),
            pluginId: Self.id
        )
    }

    public func makeView() -> AnyView {
        AnyView(
            EchoTableView(
                viewModel: viewModel
            )
            .id(Self.id)
        )
    }

    public func onConnect(_ connection: PluginConnection) {
        self.viewModel.connect(connection: connection)
    }

    public func onDisconnect() {
        self.viewModel.disconnect()
    }
}

extension LoggingDesktopPlugin: DeepLinkHandler {

    public func handleDeepLink(path: String, queryItems: [URLQueryItem]) -> Bool {
        switch path {
        case "search":
            guard let query = queryItems.unquotedValue(forKey: "query") else {
                return false
            }
            self.viewModel.setSearchText(searchText: query)
            return true
        default:
            return false
        }
    }
}
