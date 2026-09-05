import AppKit
import Combine
import ComposableArchitecture
import EchoMCP
import EchoPluginAPI
import MCP
import SwiftUI

public final class NetworkingDesktopPlugin: DesktopPlugin {

    // MARK: - Public properties

    public let metadata = try! DesktopPluginMetadata.loadFromPlist(in: Bundle.module)

    // MARK: - Private Properties

    let store = Store(initialState: AppState()) {
        AppReducer(environment: AppEnvironment())
    }
    private let connection: CurrentValueSubject<PluginConnection?, Never> = .init(nil)
    private var notificationTokens: [NSObjectProtocol] = []

    private lazy var server = Server(store: store, connection: connection)
    private lazy var mcpProvider = NetworkingMCPToolProvider(store: store)

    // MARK: - Life Cycle

    public required init() {
        server.start()
        store.send(.lifecycle(.appDidFinishLaunching))

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main,
                using: { [store] _ in
                    store.send(.lifecycle(.appWillTerminate))
                }
            )
        )
    }

    // MARK: - DesktopPlugin

    public func makeView() -> AnyView {
        AnyView(
            MainView(store: store)
        )
    }

    public func onConnect(_ connection: EchoPluginAPI.PluginConnection) {
        self.connection.value = connection
    }

    public func onDisconnect() {
        self.connection.value = nil
    }
}

// MARK: - MCPToolProvider

extension NetworkingDesktopPlugin: MCPToolProvider {
    public var mcpTools: [Tool] { mcpProvider.mcpTools }

    public func handle(toolName: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        try await mcpProvider.handle(toolName: toolName, arguments: arguments)
    }
}

// MARK: - DeepLinkHandler

extension NetworkingDesktopPlugin: DeepLinkHandler {
    public func handleDeepLink(path: String, queryItems: [URLQueryItem]) -> Bool {
        switch path {
            // "echo://plugin/com.echo.plugin.network/search?query='get-app-config'"
        case "search":
            guard let query = queryItems.unquotedValue(forKey: "query") else {
                return false
            }
            store.send(.ui(.setSearchText(query)))
            return true
        default:
            return false
        }
    }
}
