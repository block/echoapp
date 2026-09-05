import AppKit
import Combine
import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public final class AnalyticsDesktopPlugin: DesktopPlugin {

    // MARK: - Plugin

    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)

    let viewModel: EchoTableViewModel

    // Rows cache used by AnalyticsMCPToolProvider (EchoTableViewModel.rows is internal in EchoPluginUI)
    var rows: [EchoTableRow] = []
    private var rowsCancellable: AnyCancellable?

    public init() {

        self.viewModel = .init(
            configuration: .init(
                customColumnConfiguration: [
                    EchoColumnKey(id: "Time", width: 100),
                    EchoColumnKey(id: "Source", width: 80, isFilterable: true),
                    EchoColumnKey(id: "Event", width: 300, isFilterable: true),
                    EchoColumnKey(id: "Raw Message", isHidden: true),
                    EchoColumnKey(id: "Properties", isHidden: true),
                ],
                maxRowCount: 2000,
                detailViewTitleKey: "Event",
                itemLabel: "event"
            ),
            pluginId: metadata.id
        )
    }

    public func makeView() -> AnyView {
        AnyView(
            EchoTableView(
                viewModel: viewModel,
                inspectorFooter: { _ in
                    EmptyView()
                }
            )
            .id(metadata.id)
        )
    }

    public func onConnect(_ connection: PluginConnection) {
        self.viewModel.connect(connection: connection)
        rowsCancellable = connection.receiveEchoTableRows()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] row in
                guard let self else { return }
                self.rows.append(row)
                if self.rows.count > 2000 { self.rows.removeFirst(self.rows.count - 2000) }
            }
    }

    public func onDisconnect() {
        self.viewModel.disconnect()
        rowsCancellable = nil
        rows = []
    }
}

extension AnalyticsDesktopPlugin: DeepLinkHandler {
    public func handleDeepLink(path: String, queryItems: [URLQueryItem]) -> Bool {
        switch path {
            // "echo://plugin/com.echo.plugin.analytics/search?query=AppNavigate"
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
