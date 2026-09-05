import Combine
import Foundation
import os

import EchoConnection
import Vapor

protocol ClientServerConnection: AnyObject {
    var id: UUID { get }

    func send(_ payload: PluginPayload) throws
    func close() async
    func finish()

    /// Contains information about the currently connected client
    var connectedClientUpdates: AsyncStream<ConnectedClient> { get }

    var currentConnectedClient: ConnectedClient { get }

    /// Payloads received from the connected client
    var incomingPluginPayloads: AnyPublisher<PluginPayload, Error> { get }
}

/// A live connection between the Server and a Client
final class RealClientServerConnection: ClientServerConnection {

    // MARK: - Private Properties

    /// Used to transfer data between client-server
    private let webSocket: WebSocket
    private let logger = Logger.echoLogger(category: "ClientServerConnection")
    private let connectedClientRegistry: ConnectedClientRegistry
    private let incomingPluginPayloadsSubject = PassthroughSubject<PluginPayload, Error>()
    private let payloadEventQueue = DispatchQueue(label: "echo.client-server-connection.payloads")
    private let finishLock = NSLock()
    private var hasFinished = false

    // MARK: - Public Properties

    let id = UUID()

    var connectedClientUpdates: AsyncStream<ConnectedClient> {
        connectedClientRegistry.stream
    }

    var currentConnectedClient: ConnectedClient {
        connectedClientRegistry.current
    }

    /// Contains all ``PluginPayload``s coming from the client
    let incomingPluginPayloads: AnyPublisher<PluginPayload, Error>

    // MARK: - Life Cycle

    init(
        connectedClient: ConnectedClient,
        webSocket: WebSocket
    ) {
        self.webSocket = webSocket
        self.connectedClientRegistry = ConnectedClientRegistry(initialValue: connectedClient)
        self.incomingPluginPayloads = incomingPluginPayloadsSubject
            .buffer(size: Int.max, prefetch: .keepFull, whenFull: .dropOldest)
            .eraseToAnyPublisher()

        webSocket.onBinary { [weak self] _, byteBuffer in
            guard let self else { return }
            if let pluginPayload = try? JSONDecoder().decode(PluginPayload.self, from: byteBuffer) {
                sendIncomingPayload(pluginPayload)
                return
            }
            if let clientInfoPayload = try? JSONDecoder().decode(ClientInfoPayload.self, from: byteBuffer) {
                var updatedClient = connectedClientRegistry.current
                updatedClient.clientInfo = clientInfoPayload
                connectedClientRegistry.update(updatedClient)
                return
            }
            logger.warning("Unknown message received: \(byteBuffer)")
        }
    }

    deinit {
        finish()
    }

    // MARK: - Public Methods

    /// Send a payload to the client
    func send(_ payload: PluginPayload) throws {
        var buffer = ByteBuffer()
        try JSONEncoder().encode(payload, into: &buffer)
        webSocket.send(buffer)
    }

    /// Close this connection
    func close() async {
        try? await webSocket.close(code: .normalClosure)
        finish()
    }

    func finish() {
        finishLock.lock()
        guard !hasFinished else {
            finishLock.unlock()
            return
        }
        hasFinished = true
        payloadEventQueue.async { [incomingPluginPayloadsSubject] in
            incomingPluginPayloadsSubject.send(completion: .finished)
        }
        finishLock.unlock()
    }

    // MARK: - Private Methods

    private func sendIncomingPayload(_ payload: PluginPayload) {
        finishLock.lock()
        guard !hasFinished else {
            finishLock.unlock()
            return
        }

        payloadEventQueue.async { [incomingPluginPayloadsSubject] in
            incomingPluginPayloadsSubject.send(payload)
        }
        finishLock.unlock()
    }
}
