@testable import EchoClient

import Combine
import ConcurrencyExtras
import EchoConnection
import EchoPluginAPI
import XCTest

final class EchoClientTests: XCTestCase {

    // MARK: - Tests - addPlugin

    @MainActor
    func test_addPlugin() {
        let client = EchoClient()
        let plugin = FakeClientPlugin(id: "id")

        client.addPlugin(plugin)

        XCTAssertNotNil(client.plugin(with: "id"))
        XCTAssertEqual(plugin.onConnectCalls.count, 0)
    }

    @MainActor
    func test_addPlugin_overwritesExistingPluginWithSameID() {
        let original = FakeClientPlugin(id: "id")
        let client = EchoClient(plugins: [original])

        XCTAssert(client.plugin(with: "id") as? AnyObject === original)

        let new = FakeClientPlugin(id: "id")
        client.addPlugin(new)

        XCTAssert(client.plugin(with: "id") as? AnyObject === new)
    }

    @MainActor
    func test_addPlugin_whenAlreadyConnectedToEcho() async throws {
        let tester = try await EchoClientTester(initialState: .connected)

        let plugin = FakeClientPlugin()
        XCTAssertEqual(plugin.onConnectCalls.count, 0)

        tester.client.addPlugin(plugin)
        XCTAssertEqual(plugin.onConnectCalls.count, 1)
    }

    @MainActor
    func test_directsMessagesToPluginsByID() async throws {
        let pluginA = FakeClientPlugin(id: "A")
        let pluginB = FakeClientPlugin(id: "B")

        let tester = try await EchoClientTester(
            plugins: [pluginA, pluginB],
            initialState: .connected
        )

        let connectionA = try XCTUnwrap(pluginA.onConnectCalls.first)
        let connectionB = try XCTUnwrap(pluginB.onConnectCalls.first)

        var cancellables: [AnyCancellable] = []
        let expectationA = self.expectation(description: "A received message")
        let expectationB = self.expectation(description: "B received message")

        // Listen for distinct messages sent to each plugin
        connectionA.receive(String.self).sink { message in
            XCTAssertEqual(message, "Message for A")
            expectationA.fulfill()
        }.store(in: &cancellables)

        connectionB.receive(String.self).sink { message in
            XCTAssertEqual(message, "Message for B")
            expectationB.fulfill()
        }.store(in: &cancellables)

        // Get the underlying web socket. We'll send payloads over this socket and
        // ensure they get directed to the correct plugin.
        guard case let .connected(webSocketTask, _) = tester.client.state else {
            XCTFail("Expected client.state == .connected")
            return
        }
        let testWebSocketTask = try XCTUnwrap(webSocketTask as? FakeWebSocketTask)

        let encoder = JSONEncoder()

        // Send the payloads for each plugin:
        let messageA = PluginPayload(pluginID: "A", data: try encoder.encode("Message for A"))
        XCTAssertEqual(testWebSocketTask.receiveCalls.count, 1)
        testWebSocketTask.receiveCalls.first?(.success(.data(try encoder.encode(messageA))))

        let messageB = PluginPayload(pluginID: "B", data: try encoder.encode("Message for B"))
        XCTAssertEqual(testWebSocketTask.receiveCalls.count, 2)
        testWebSocketTask.receiveCalls.last?(.success(.data(try encoder.encode(messageB))))

        await fulfillment(of: [expectationA, expectationB], timeout: 1)
    }

    // MARK: - Tests - removePlugin

    @MainActor
    func test_removePlugin() {
        let pluginA = FakeClientPlugin(id: "A")
        let pluginB = FakeClientPlugin(id: "B")
        let client = EchoClient(plugins: [pluginA, pluginB])

        XCTAssertNotNil(client.plugin(with: pluginA.id))
        XCTAssertNotNil(client.plugin(with: pluginB.id))

        XCTAssertEqual(pluginA.onDisconnectCallCount, 0)
        XCTAssertEqual(pluginB.onDisconnectCallCount, 0)

        client.removePlugin(pluginA)

        XCTAssertEqual(pluginA.onDisconnectCallCount, 1)
        XCTAssertNil(client.plugin(with: pluginA.id))

        XCTAssertEqual(pluginB.onDisconnectCallCount, 0)
        XCTAssertNotNil(client.plugin(with: pluginB.id))
    }

    @MainActor
    func test_removePlugin_noOpsForUnknownPlugin() {
        let plugin = FakeClientPlugin()
        let client = EchoClient(plugins: [])

        client.removePlugin(plugin)
        XCTAssertEqual(plugin.onDisconnectCallCount, 0)
    }

    // MARK: - Tests - State Transitions

    @MainActor
    func test_stateTransitions_happyPath() async throws {
        let plugin = FakeClientPlugin()
        let tester = try await EchoClientTester(
            plugins: [plugin],
            initialState: .idle
        )

        await tester.transitionClientStateToAdvertising()
        try await tester.transitionClientStateToConnecting()

        XCTAssertEqual(plugin.onConnectCalls.count, 0)
        await tester.transitionClientStateToConnected()
        XCTAssertEqual(plugin.onConnectCalls.count, 1)
    }

    // MARK: - Tests - connect(to:)

    @MainActor
    func test_connectTo_fromIdle() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://localhost:8080")!

        tester.client.connect(to: url)

        guard case let .connecting(webSocketTask) = tester.client.state else {
            XCTFail("Expected client.state == .connecting")
            return
        }
        let testWebSocketTask = try XCTUnwrap(webSocketTask as? FakeWebSocketTask)
        XCTAssertEqual(testWebSocketTask.currentRequest?.url, url)
        XCTAssertEqual(testWebSocketTask.resumeCallCount, 1)
    }

    @MainActor
    func test_connectTo_whileAdvertising() async throws {
        let tester = try await EchoClientTester(initialState: .advertising)
        XCTAssert(tester.client.state.isAdvertising)

        let url = URL(string: "ws://localhost:8080")!
        tester.client.connect(to: url)

        guard case let .connecting(webSocketTask) = tester.client.state else {
            XCTFail("Expected client.state == .connecting")
            return
        }
        let testWebSocketTask = try XCTUnwrap(webSocketTask as? FakeWebSocketTask)
        XCTAssertEqual(testWebSocketTask.currentRequest?.url, url)
    }

    @MainActor
    func test_connectTo_fullConnection() async throws {
        let plugin = FakeClientPlugin()
        let tester = try await EchoClientTester(
            plugins: [plugin],
            initialState: .idle
        )

        let url = URL(string: "ws://localhost:8080")!
        tester.client.connect(to: url)

        XCTAssertEqual(plugin.onConnectCalls.count, 0)
        await tester.transitionClientStateToConnected()
        XCTAssertEqual(plugin.onConnectCalls.count, 1)
    }

    // MARK: - Tests - connectionMode

    @MainActor
    func test_connectionMode_defaultsToBonjour() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        XCTAssertEqual(tester.client.connectionMode, .bonjour)
    }

    @MainActor
    func test_connectionMode_persistsAfterStop() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://localhost:8080")!

        tester.client.connect(to: url)
        XCTAssertEqual(tester.client.connectionMode, .manual(url: url))

        // Mode is a configuration — it persists across stop so the next start() reconnects
        tester.client.stop()
        XCTAssertEqual(tester.client.connectionMode, .manual(url: url))
    }

    @MainActor
    func test_start_switchesMode() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://localhost:8080")!

        // Switch to manual
        tester.client.start(mode: .manual(url: url))
        XCTAssertEqual(tester.client.connectionMode, .manual(url: url))
        XCTAssert(tester.client.state.isConnecting)

        // Switch back to bonjour
        tester.client.start(mode: .bonjour)
        XCTAssertEqual(tester.client.connectionMode, .bonjour)
        XCTAssert(tester.client.state.isAdvertising)
    }

    @MainActor
    func test_restart_resumesManualConnection() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://localhost:8080")!
        tester.client.connect(to: url)
        await tester.transitionClientStateToConnected()

        // Simulate restart (e.g. connection drop)
        tester.client.restart()

        // Should be reconnecting to the same URL, not advertising via Bonjour
        XCTAssertEqual(tester.client.connectionMode, .manual(url: url))
        guard case let .connecting(webSocketTask) = tester.client.state else {
            XCTFail("Expected client.state == .connecting")
            return
        }
        let testWebSocketTask = try XCTUnwrap(webSocketTask as? FakeWebSocketTask)
        XCTAssertEqual(testWebSocketTask.currentRequest?.url, url)
    }

    @MainActor
    func test_restart_resumesBonjourDiscovery() async throws {
        let tester = try await EchoClientTester(initialState: .connected)

        tester.client.restart()

        XCTAssertEqual(tester.client.connectionMode, .bonjour)
        XCTAssert(tester.client.state.isAdvertising)
    }

    @MainActor
    func test_connectionMode_persistsAcrossInstances() async throws {
        let defaults = makeTestDefaults()
        let url = URL(string: "ws://192.168.1.50:8080")!

        // Set manual mode → new client should restore it
        let tester1 = try await EchoClientTester(initialState: .idle, userDefaults: defaults)
        tester1.client.connect(to: url)

        let tester2 = try await EchoClientTester(initialState: .idle, userDefaults: defaults)
        XCTAssertEqual(tester2.client.connectionMode, .manual(url: url))

        // Switch back to bonjour → new client should restore bonjour
        tester2.client.start(mode: .bonjour)

        let tester3 = try await EchoClientTester(initialState: .idle, userDefaults: defaults)
        XCTAssertEqual(tester3.client.connectionMode, .bonjour)
    }

    // MARK: - Tests - connectedURL

    @MainActor
    func test_connectedURL_lifecycle() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://192.168.1.50:8080")!

        // nil when idle
        XCTAssertNil(tester.client.connectedURL)

        tester.client.connect(to: url)
        await tester.transitionClientStateToConnected()

        // populated when connected
        XCTAssertEqual(tester.client.connectedURL, url)

        tester.client.stop()

        // nil again after disconnect
        XCTAssertNil(tester.client.connectedURL)
    }

    @MainActor
    func test_connectedURLPublisher_emitsChanges() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://192.168.1.50:8080")!

        var emittedURLs: [URL?] = []
        var cancellables: [AnyCancellable] = []
        tester.client.connectedURLPublisher.sink { url in
            emittedURLs.append(url)
        }.store(in: &cancellables)

        tester.client.connect(to: url)
        await tester.transitionClientStateToConnected()
        tester.client.stop()

        // Verify the URL appeared in the stream and ends with nil after stop
        XCTAssert(emittedURLs.contains(url), "Expected connected URL to appear in publisher stream")
        XCTAssertEqual(emittedURLs.last, .some(nil), "Expected last emitted value to be nil after stop")
    }

    // MARK: - Tests - connectionErrors

    @MainActor
    func test_connectionError_emitsOnPublisher() async throws {
        let tester = try await EchoClientTester(initialState: .idle)
        let url = URL(string: "ws://localhost:8080")!
        tester.client.connect(to: url)

        var cancellables: [AnyCancellable] = []
        let expectation = self.expectation(description: "Received connection error")
        var receivedError: Swift.Error?

        tester.client.connectionErrors.sink { error in
            receivedError = error
            expectation.fulfill()
        }.store(in: &cancellables)

        let testError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
        tester.client._urlSessionTaskDidComplete(with: testError)

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual((receivedError as? NSError)?.domain, "test")
    }

    @MainActor
    func test_connectionError_transitionsToIdle() async throws {
        try await withMainSerialExecutor {
            let tester = try await EchoClientTester(initialState: .idle)
            let url = URL(string: "ws://localhost:8080")!
            tester.client.connect(to: url)
            XCTAssert(tester.client.state.isConnecting)

            let testError = NSError(domain: "test", code: -1)
            tester.client._urlSessionTaskDidComplete(with: testError)

            // Let the executor schedule the internal Task that transitions state
            await Task.yield()

            XCTAssert(tester.client.state.isIdle)
        }
    }
}

@MainActor
private final class EchoClientTester {
    let bonjourAdvertiser: FakeBonjourAdvertiser
    let client: EchoClient
    let session: FakeURLSession

    /// A mirror of `EchoClient.state` without associated values to improve ergonomics in tests
    enum ClientState: Int, Equatable {
        case idle
        case advertising
        case connecting
        case connected
    }

    init(
        bonjourAdvertiser: FakeBonjourAdvertiser = .init(),
        plugins: [ClientPlugin] = [],
        initialState: ClientState,
        session: FakeURLSession = .init(),
        userDefaults: UserDefaults = makeTestDefaults()
    ) async throws {
        self.bonjourAdvertiser = bonjourAdvertiser
        self.client = .init(
            bonjourAdvertiserFactory: { _, _ in bonjourAdvertiser },
            urlSessionFactory: { _ in session },
            userDefaults: userDefaults,
            plugins: plugins
        )
        self.session = session

        switch initialState {
        case .idle:
            break

        case .advertising:
            await transitionClientStateToAdvertising()

        case .connecting:
            await transitionClientStateToAdvertising()
            try await transitionClientStateToConnecting()

        case .connected:
            await transitionClientStateToAdvertising()
            try await transitionClientStateToConnecting()
            await transitionClientStateToConnected()
        }
    }

    func transitionClientStateToAdvertising() async {
        await withMainSerialExecutor {
            guard case .idle = client.state else {
                XCTFail("Can only transition from .idle state")
                return
            }
            client.start()

            // Let the executor schedule the internal `advertising` Task
            await Task.yield()

            // Let the executor schedule the `withCheckedContinuation` block in `FakeBonjourAdvertiser`
            await Task.yield()

            XCTAssert(client.state.isAdvertising)
        }
    }

    func transitionClientStateToConnecting() async throws {
        try await withMainSerialExecutor {
            guard case .advertising = client.state else {
                XCTFail("Can only transition from .advertising state")
                return
            }
            // Simulate Echo sending a connection request:
            let provideConnectionData = try XCTUnwrap(
                bonjourAdvertiser.receiveConnectionDataCalls.first
            )
            let url = URL(string: "echo://")!
            let connectionRequest = ConnectionRequest(serverURL: url)
            provideConnectionData.resume(returning: try JSONEncoder().encode(connectionRequest))

            // Let the executor schedule the continuation we just resumed
            await Task.yield()

            // State transition: `connecting`
            guard case let .connecting(webSocketTask) = client.state else {
                XCTFail("Expected client.state == .connecting")
                return
            }
            let testWebSocketTask = try XCTUnwrap(webSocketTask as? FakeWebSocketTask)
            XCTAssertEqual(testWebSocketTask.resumeCallCount, 1)
            XCTAssertEqual(testWebSocketTask.currentRequest?.url, url)
        }
    }

    func transitionClientStateToConnected() async {
        await withMainSerialExecutor {
            guard case let .connecting(webSocketTask) = client.state else {
                XCTFail("Can only transition from .connecting state")
                return
            }

            // Simulate Foundation opening the websocket
            client._urlSession(session, webSocketTask: webSocketTask, didOpenWithProtocol: nil)

            // State transition: `connected`
            XCTAssert(client.state.isConnected)

            // Let the executor schedule the Task that sets up downstream plugin connections
            await Task.yield()
        }
    }
}

// MARK: -

private final class FakeClientPlugin: ClientPlugin {
    let id: PluginIdentifier
    let version = "1.0.0"

    init(id: PluginIdentifier = "FakeClientPlugin") {
        self.id = id
    }

    var onConnectCalls: [PluginConnection] = []
    func onConnect(_ connection: PluginConnection) {
        onConnectCalls.append(connection)
    }

    var onDisconnectCallCount = 0
    func onDisconnect() {
        onDisconnectCallCount += 1
    }
}

// MARK: -

private final class FakeBonjourAdvertiser: BonjourAdvertiser {
    var receiveConnectionDataCalls: [CheckedContinuation<Data, Never>] = []

    func receiveConnectionData() async throws -> Data {
        await withCheckedContinuation { continuation in
            self.receiveConnectionDataCalls.append(continuation)
        }
    }
}

// MARK: -

private func makeTestDefaults() -> UserDefaults {
    let suiteName = "EchoClientTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// MARK: -

extension EchoClient.State {
    var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }

    var isAdvertising: Bool {
        if case .advertising = self {
            return true
        }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

