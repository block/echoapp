@testable import Echo

import Combine
import EchoConnection
import Foundation

final class TestClientServerConnection: ClientServerConnection {
    let id = UUID()
    var sentPayloads: [PluginPayload] = []
    private let connectedClientsContinuation: AsyncStream<ConnectedClient>.Continuation
    let connectedClientUpdates: AsyncStream<ConnectedClient>

    var client: ConnectedClient {
        didSet {
            connectedClientsContinuation.yield(client)
        }
    }

    init(
        client: ConnectedClient = .init(deviceIdentifier: .init(value: "test"), deviceName: "test", appIdentifier: "test")
    ) {
        let connectedClients = AsyncStream.makeStream(of: ConnectedClient.self)
        self.connectedClientUpdates = connectedClients.stream
        self.connectedClientsContinuation = connectedClients.continuation
        self.client = client
        self.connectedClientsContinuation.yield(client)
    }

    // MARK: - ClientServerConnection

    var incomingPluginPayloads: AnyPublisher<PluginPayload, Error> {
        Empty().eraseToAnyPublisher()
    }

    var currentConnectedClient: ConnectedClient {
        client
    }

    func send(_ payload: PluginPayload) throws {
        sentPayloads.append(payload)
    }

    func close() async {}

    func finish() {}
}
