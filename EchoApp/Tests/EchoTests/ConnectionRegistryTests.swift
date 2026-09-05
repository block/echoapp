@testable import Echo

import EchoConnection
import XCTest

final class ConnectionRegistryTests: XCTestCase {

    func test_expectedIdentifier_rejectsOnlyMismatchedConnections() {
        let registry = ConnectionRegistry()

        registry.beginExpectingConnection()
        XCTAssertFalse(registry.acceptsConnection(identifier: "expected"))
        registry.expectConnection(identifier: "expected")

        XCTAssertTrue(registry.acceptsConnection(identifier: "expected"))
        XCTAssertTrue(registry.acceptsConnection(identifier: "EXPECTED"))
        XCTAssertFalse(registry.acceptsConnection(identifier: "other"))
        registry.expectConnection(identifier: nil)
        XCTAssertTrue(registry.acceptsConnection(identifier: "other"))
    }

    func test_clearIfActive_ignoresStaleConnectionAfterReplacement() {
        let registry = ConnectionRegistry()
        let firstConnection = TestClientServerConnection(
            client: .init(deviceIdentifier: .init(value: "device"), deviceName: "iPhone", appIdentifier: "app")
        )
        let replacementConnection = TestClientServerConnection(
            client: .init(deviceIdentifier: .init(value: "device"), deviceName: "iPhone", appIdentifier: "app")
        )

        XCTAssertNil(registry.activate(firstConnection))
        XCTAssertEqual(registry.activate(replacementConnection)?.id, firstConnection.id)

        XCTAssertNil(registry.clearIfActive(connectionID: firstConnection.id))
        XCTAssertEqual(registry.current?.id, replacementConnection.id)
    }

    func test_stream_emitsDisconnectBetweenReplacementConnections() async {
        let registry = ConnectionRegistry()
        var iterator = registry.stream.makeAsyncIterator()

        let initialConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertNil(initialConnectionID)

        let firstConnection = TestClientServerConnection()
        registry.activate(firstConnection)
        let firstConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertEqual(firstConnectionID, firstConnection.id)

        let replacementConnection = TestClientServerConnection()
        registry.activate(replacementConnection)
        let disconnectedConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertNil(disconnectedConnectionID)
        let replacementConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertEqual(replacementConnectionID, replacementConnection.id)
    }

    func test_stream_replaysInitialConnectionBeforeSubsequentUpdate() async {
        let registry = ConnectionRegistry()
        let firstConnection = TestClientServerConnection()
        registry.activate(firstConnection)

        var iterator = registry.stream.makeAsyncIterator()
        let replacementConnection = TestClientServerConnection()
        registry.activate(replacementConnection)

        let initialConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertEqual(initialConnectionID, firstConnection.id)

        let disconnectedConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertNil(disconnectedConnectionID)

        let replacementConnectionID = await nextConnectionID(from: &iterator)
        XCTAssertEqual(replacementConnectionID, replacementConnection.id)
    }

    func test_stream_finishesWhenRegistryDeinitializes() async {
        var registry: ConnectionRegistry? = ConnectionRegistry()
        var iterator = registry!.stream.makeAsyncIterator()

        _ = await nextConnectionID(from: &iterator)
        registry = nil

        let nextEvent = await iterator.next()
        if case .some = nextEvent {
            XCTFail("Connection stream yielded after registry deinitialization")
        }
    }

    func test_connectedClientStream_replaysInitialClientBeforeSubsequentUpdate() async {
        let firstClient = ConnectedClient(
            deviceIdentifier: .init(value: "first"),
            deviceName: "iPhone",
            appIdentifier: "app"
        )
        let registry = ConnectedClientRegistry(initialValue: firstClient)

        var iterator = registry.stream.makeAsyncIterator()
        let replacementClient = ConnectedClient(
            deviceIdentifier: .init(value: "replacement"),
            deviceName: "iPhone",
            appIdentifier: "app"
        )
        registry.update(replacementClient)

        let initialClient = await nextConnectedClient(from: &iterator)
        XCTAssertEqual(initialClient?.deviceIdentifier, firstClient.deviceIdentifier)

        let updatedClient = await nextConnectedClient(from: &iterator)
        XCTAssertEqual(updatedClient?.deviceIdentifier, replacementClient.deviceIdentifier)
    }

    func test_connectedClientStream_finishesWhenRegistryDeinitializes() async {
        var registry: ConnectedClientRegistry? = ConnectedClientRegistry(
            initialValue: .init(deviceIdentifier: .init(value: "first"), deviceName: "iPhone", appIdentifier: "app")
        )
        var iterator = registry!.stream.makeAsyncIterator()

        _ = await nextConnectedClient(from: &iterator)
        registry = nil

        let nextEvent = await iterator.next()
        if case .some = nextEvent {
            XCTFail("Connected client stream yielded after registry deinitialization")
        }
    }

    private func nextConnectionID(
        from iterator: inout AsyncStream<(any ClientServerConnection)?>.Iterator
    ) async -> UUID? {
        guard let event = await iterator.next() else {
            XCTFail("Connection stream ended unexpectedly")
            return nil
        }
        return event?.id
    }

    private func nextConnectedClient(
        from iterator: inout AsyncStream<ConnectedClient>.Iterator
    ) async -> ConnectedClient? {
        guard let event = await iterator.next() else {
            XCTFail("Connected client stream ended unexpectedly")
            return nil
        }
        return event
    }
}
