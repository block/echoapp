@testable import Echo

import Foundation

final class TestServer: Server {
    private let connectionRegistry = ConnectionRegistry()

    var webSocketURL: URL {
        URL(string: "ws://localhost:8080")!
    }

    var connectionUpdates: AsyncStream<(any ClientServerConnection)?> {
        connectionRegistry.stream
    }

    var currentConnection: (any ClientServerConnection)? {
        connectionRegistry.current
    }

    func start() throws {}

    func closeCurrentConnection() async {
        guard let connection = connectionRegistry.clearActiveConnection() else { return }
        await connection.close()
    }

    func expectConnection(identifier: String?) {
        connectionRegistry.expectConnection(identifier: identifier)
    }

    func beginExpectingConnection() {
        connectionRegistry.beginExpectingConnection()
    }
    
    init(clientServerConnection: any ClientServerConnection) {
        connectionRegistry.activate(clientServerConnection)
    }

    func setConnection(_ connection: (any ClientServerConnection)?) {
        if let connection {
            connectionRegistry.activate(connection)
        } else {
            connectionRegistry.clearActiveConnection()
        }
    }
}
