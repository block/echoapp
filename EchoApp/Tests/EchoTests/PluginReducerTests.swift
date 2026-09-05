@testable import Echo

import EchoConnection
import EchoPluginAPI
import XCTest

final class SessionViewModelTests: XCTestCase {

    @MainActor
    func test_selectPluginSendsInactiveAndActiveLifecycleEvents() async throws {
        let pluginA = LoadedPlugin(framework: nil, plugin: TestDesktopPlugin(id: "A"))
        let pluginB = LoadedPlugin(framework: nil, plugin: TestDesktopPlugin(id: "B"))

        let clientServerConnection = TestClientServerConnection()
        let pluginManager = DesktopPluginManager(pluginFrameworks: [])
        let server = TestServer(clientServerConnection: clientServerConnection)
        let environment = SessionEnvironment(
            server: server,
            pluginManager: pluginManager
        )

        var initialState = SessionState(
            id: UUID(),
            port: 34143,
            pluginManager: pluginManager
        )
        initialState.loadedPlugins = [pluginA, pluginB]
        initialState.selectedPlugin = .init(pluginA, id: pluginA.id)

        let viewModel = SessionViewModel(
            initialState: initialState,
            environment: environment,
            onDebugPayload: { _ in }
        )

        viewModel.selectPlugin(pluginB.id)

        XCTAssertEqual(clientServerConnection.sentPayloads.count, 2)

        XCTAssertEqual(clientServerConnection.sentPayloads.first?.pluginID, pluginA.id)
        XCTAssertEqual(
            clientServerConnection.sentPayloads.first?.data,
            try JSONEncoder().encode(ClientPluginLifecycleEvent.inactive)
        )

        XCTAssertEqual(clientServerConnection.sentPayloads.last?.pluginID, pluginB.id)
        XCTAssertEqual(
            clientServerConnection.sentPayloads.last?.data,
            try JSONEncoder().encode(ClientPluginLifecycleEvent.active)
        )

        XCTAssertEqual(viewModel.selectedPlugin?.id, pluginB.id)
    }
}
