import Combine
import EchoPluginAPI
import EchoConnection
import Foundation

// MARK: -

public final class EchoClient: NSObject, URLSessionWebSocketDelegate {

    // MARK: - Public Types

    public enum Error: Swift.Error {
        /// Expected to receive a ``ConnectionRequest``, but got something else instead
        case notAConnectionRequest(payload: Data)
    }

    /// How the client is configured to connect to the Echo server.
    public enum ConnectionMode: Equatable {
        /// The client uses Bonjour to discover the Echo server automatically.
        case bonjour

        /// The client connects directly to the given URL.
        case manual(url: URL)
    }

    // MARK: - Public Properties

    @MainActor
    public static let shared = EchoClient()

    // Default plugins

    public let appInfoPlugin = AppInfoPlugin()
    public let networkingPlugin = NetworkingPlugin()

    /// Publishes the URL of the Echo server the client is currently connected to, or `nil` if not connected.
    public var connectedURLPublisher: AnyPublisher<URL?, Never> {
        connectedURLSubject.eraseToAnyPublisher()
    }

    /// Emits errors encountered while attempting to connect to the Echo server.
    public var connectionErrors: AnyPublisher<Swift.Error, Never> {
        connectionErrorsSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let clientIdentifier: String
    private let deviceIdentifier: DeviceIdentifier
    private let bonjourAdvertiser: BonjourAdvertiser
    private var urlSession: URLSessionProtocol!
    private let connectionErrorsSubject = PassthroughSubject<Swift.Error, Never>()
    private let connectedURLSubject = CurrentValueSubject<URL?, Never>(nil)
    private let userDefaults: UserDefaults

    static let connectionModeURLKey = "EchoClient.manualConnectionURL"

    /// Tracks how the client is configured to connect to the Echo server.
    /// Defaults to `.bonjour`. Persisted across launches.
    private(set) var connectionMode: ConnectionMode = .bonjour

    // MARK: - Private Properties (State)

    private var plugins: [ClientPlugin] = [] {
        didSet {
            sendLatestClientInfoPayload()
        }
    }

    enum State {
        case idle

        /// The client is advertising over Bonjour, waiting for a ``ConnectionRequest`` from Echo`
        case advertising(Task<Void, Never>)

        /// The client is in the process of establishing a websocket connection with Echo
        case connecting(webSocketTask: URLSessionWebSocketTaskProtocol)

        /// The client is connected to Echo via the associated websocket.
        case connected(
            webSocketTask: URLSessionWebSocketTaskProtocol,
            incomingPayloads: PassthroughSubject<PluginPayload, Never>
        )
    }

    private(set) var state: State = .idle {
        didSet {
            log("State changed from \(oldValue) to \(state)")
            connectedURLSubject.send(connectedURL)
        }
    }

    /// Used for direct connections to work around a macOS 15.4.1 simulator bug.
    /// This is stored separately from the `state` since it's a temporary workaround (Apple has indicated they will fix this).
    private var directConnectionWebSocketTask: URLSessionWebSocketTaskProtocol?

    // MARK: - Life Cycle

    /**
     Initializes a new EchoClient instance.
     
     - Parameters:
       - clientIdentifier: Unique identifier for this client instance, used for routing and identification.
         Defaults to a random UUID string.
       - deviceIdentifier: Identifier for the physical device. Used for service discovery and connection pairing.
         Defaults to the current device identifier.
       - bonjourAdvertiserFactory: Factory function that creates a BonjourAdvertiser for network discovery.
         Takes the client identifier and device identifier as parameters.
         Defaults to creating a RealBonjourAdvertiser with "_echoclient._tcp" service type.
       - urlSessionFactory: Factory function that creates a URLSession for WebSocket connections.
         Takes a URLSessionWebSocketDelegate as parameter.
         Defaults to creating a URLSession with default configuration.
       - plugins: Array of client plugins to register with this Echo client instance.
         Defaults to an empty array.
     */
    @MainActor
    public init(
        clientIdentifier: String = UUID().uuidString,
        deviceIdentifier: DeviceIdentifier = .current,
        bonjourAdvertiserFactory: (String, DeviceIdentifier) -> BonjourAdvertiser = { clientIdentifier, deviceIdentifier in
            RealBonjourAdvertiser(
                clientIdentifier: clientIdentifier,
                serviceName: deviceIdentifier.value,
                serviceType: "_echoclient._tcp"
            )
        },
        urlSessionFactory: @escaping (URLSessionWebSocketDelegate) -> URLSessionProtocol = { delegate in
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            return session
        },
        userDefaults: UserDefaults = .standard,
        plugins: [ClientPlugin] = []
    ) {
        self.clientIdentifier = clientIdentifier
        self.deviceIdentifier = deviceIdentifier
        self.bonjourAdvertiser = bonjourAdvertiserFactory(clientIdentifier, deviceIdentifier)
        self.userDefaults = userDefaults
        super.init()
        self.urlSession = urlSessionFactory(self)

        // Restore persisted connection mode
        if let urlString = userDefaults.string(forKey: Self.connectionModeURLKey),
           let url = URL(string: urlString) {
            self.connectionMode = .manual(url: url)
        }

        plugins.forEach(addPlugin)
    }

    // MARK: - Public Methods

    /// `true` if the client is currently connected to an EchoApp.app server
    public var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// The URL of the Echo server the client is currently connected to, or `nil` if not connected.
    public var connectedURL: URL? {
        if case let .connected(webSocketTask, _) = state {
            return webSocketTask.currentRequest?.url
        }
        return nil
    }

    public func plugin(with id: PluginIdentifier) -> ClientPlugin? {
        plugins.first(where: { $0.id == id })
    }

    @MainActor
    public func addPlugin(_ plugin: ClientPlugin) {
        if plugins.map(\.id).contains(plugin.id) {
            log("Plugin with id \(plugin.id) already registered! The old one will be replaced")
            plugins = plugins.filter { $0.id != plugin.id }
        }
        
        plugins.append(plugin)

        // If we're already connected to Echo, wire up the downstream connection for the plugin.
        // Otherwise the plugin's connection will get set up later, once we connect to Echo.
        if case let .connected(webSocketTask, incomingPayloadsPublisher) = state {
            setupConnection(
                for: plugin,
                webSocketTask: webSocketTask,
                incomingPayloadsPublisher: incomingPayloadsPublisher
            )
        }
    }

    @MainActor
    public func removePlugin(_ plugin: ClientPlugin) {
        plugins.removeAll {
            if $0.id == plugin.id {
                plugin.onDisconnect()
                return true
            }
            return false
        }
    }

    /// Start the Echo client using the given connection mode.
    ///
    /// - If a `mode` is provided, the client switches to that mode (and persists the choice).
    /// - If `mode` is `nil`, the client uses the previously persisted mode (defaults to `.bonjour`).
    ///
    /// Safe to call from any state — the client will stop any existing connection first.
    @MainActor
    public func start(mode: ConnectionMode? = nil) {
        stop()

        if let mode {
            connectionMode = mode
        }

        // Persist the connection mode
        switch connectionMode {
        case .bonjour:
            userDefaults.removeObject(forKey: Self.connectionModeURLKey)
        case .manual(let url):
            userDefaults.set(url.absoluteString, forKey: Self.connectionModeURLKey)
        }

        switch connectionMode {
        case .bonjour:
            startBonjourAdvertising()
        case .manual(let url):
            let webSocketTask = connectToWebSocket(url: url)
            state = .connecting(webSocketTask: webSocketTask)
        }
    }

    /// Connect directly to an Echo server at the given URL, bypassing Bonjour discovery.
    @MainActor
    public func connect(to url: URL) {
        start(mode: .manual(url: url))
    }

    // MARK: - Private Methods

    private func startBonjourAdvertising() {
        let advertisingTask = Task {
            do {
                log("Waiting for server url...")
                let data = try await bonjourAdvertiser.receiveConnectionData()
                guard let connectionRequest = try? JSONDecoder().decode(ConnectionRequest.self, from: data) else {
                    throw Error.notAConnectionRequest(payload: data)
                }
                guard !Task.isCancelled else { return }
                handle(connectionRequest)
            }
            catch {
                log("Error while establishing connection: \(error)")
            }
        }
        state = .advertising(advertisingTask)
    }

    func handle(_ error: Swift.Error) {
        log("Error: \(error)")
        // TODO: - should we stop the client when an error occurs?
        // TODO: - should we inspect the different types of errors that can occur here?
    }

    func handle(_ connectionRequest: ConnectionRequest) {
        guard case .advertising = state else {
            log("Not advertising, ignoring connection request")
            return
        }
        let webSocketTask = connectToWebSocket(url: connectionRequest.serverURL)
        state = .connecting(webSocketTask: webSocketTask)
    }

    private func connectToWebSocket(url: URL) -> URLSessionWebSocketTaskProtocol {
        log("Connecting to Echo at \(url)...")

        var webSocketRequest = URLRequest(url: url)
        webSocketRequest.setValue(
            deviceIdentifier.value,
            forHTTPHeaderField: EchoHTTPHeaders.deviceIdentifier
        )
        webSocketRequest.setValue(
            deviceIdentifier.value,
            forHTTPHeaderField: EchoHTTPHeaders.deviceName
        )
        webSocketRequest.setValue(
            Bundle.main.bundleIdentifier,
            forHTTPHeaderField: EchoHTTPHeaders.appIdentifier
        )
        let webSocketTask = urlSession.makeWebSocketTask(for: webSocketRequest)
        webSocketTask.resume()
        return webSocketTask
    }

    @MainActor
    private func setupConnection(
        for plugin: ClientPlugin,
        webSocketTask: URLSessionWebSocketTaskProtocol,
        incomingPayloadsPublisher: PassthroughSubject<PluginPayload, Never>
    ) {
        let connection = PluginConnection(
            incomingMessages: incomingPayloadsPublisher
                .filter { $0.pluginID == plugin.id }
                .filter { self.notifyPluginForLifecycleEvent(data: $0.data, plugin: plugin) }
                .map { PluginMessage(command: $0.command, data: $0.data) }
                .eraseToAnyPublisher(),
            send: { [weak self, weak webSocketTask] message in
                Task {
                    do {
                        let payload = PluginPayload(pluginID: plugin.id, data: message.data, command: message.command)
                        let encodedPayload = try JSONEncoder().encode(payload)
                        try await webSocketTask?.send(.data(encodedPayload))
                    } catch {
                        self?.handle(error)
                    }
                }
            }
        )
        plugin.onConnect(connection)
    }

    /// If the data sent over is a ClientPluginLifecycleEvent, notify the plugin and return false to filter the message.
    @MainActor
    private func notifyPluginForLifecycleEvent(data: Data, plugin: ClientPlugin) -> Bool {
        guard let event = try? JSONDecoder().decode(ClientPluginLifecycleEvent.self, from: data) else { return true }

        switch event {
        case .active:
            plugin.onDesktopPluginActive()
        case .inactive:
            plugin.onDesktopPluginInactive()
        }

        return false
    }

    /// Sends a ``ClientInfoPayload`` to Echo if its connected
    private func sendLatestClientInfoPayload() {
        guard case let .connected(webSocketTask, _) = state else {
            return
        }
        let payload = ClientInfoPayload(clientPluginIDs: plugins.map(\.id))
        Task { [weak self] in
            do {
                let encodedPayload = try JSONEncoder().encode(payload)
                try await webSocketTask.send(.data(encodedPayload))
            } catch {
                self?.handle(error)
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        _urlSession(session, webSocketTask: webSocketTask, didOpenWithProtocol: `protocol`)
    }

    // internal for testing.
    // this method mirrors the `URLSessionWebSocketDelegate` method above, but it uses
    // protocols instead of concrete Foundation types to enable mocking in tests.
    internal func _urlSession(
        _ session: URLSessionProtocol,
        webSocketTask: URLSessionWebSocketTaskProtocol,
        didOpenWithProtocol protocol: String?
    ) {
        // Now that we're connected (either via Bonjour or direct-connect),
        // clean up the (potentially duplicate) reference to the direct connection.
        self.directConnectionWebSocketTask = nil

        let incomingPayloadsPublisher = PassthroughSubject<PluginPayload, Never>()
        state = .connected(webSocketTask: webSocketTask, incomingPayloads: incomingPayloadsPublisher)
        log("Connected to Echo at \(webSocketTask.currentRequest?.url?.absoluteString ?? "<nil>")")

        sendLatestClientInfoPayload()

        // Extract payloads received from the websocket
        webSocketTask.continuallyReceive { [weak self, weak incomingPayloadsPublisher] result in
            switch result {
            case let .success(message):
                guard let payload = try? JSONDecoder().decode(PluginPayload.self, from: message.data) else {
                    fatalError("Unexpected payload received from Echo: \(message.data)")
                }
                incomingPayloadsPublisher?.send(payload)

            case .failure:
                guard let client = self else { return }
                Task { @MainActor in
                    client.restart()
                }
            }
        }

        // Set up downstream connections for all currently-installed plugins
        Task { @MainActor in
            for plugin in plugins {
                setupConnection(
                    for: plugin,
                    webSocketTask: webSocketTask,
                    incomingPayloadsPublisher: incomingPayloadsPublisher
                )
            }
        }
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Swift.Error)?
    ) {
        guard let error else { return }
        _urlSessionTaskDidComplete(with: error)
    }

    // internal for testing.
    internal func _urlSessionTaskDidComplete(with error: Swift.Error) {
        log("Connection error: \(error)")
        connectionErrorsSubject.send(error)

        Task { @MainActor in
            if case .connecting = self.state {
                self.state = .idle
            }
        }
    }

    /// Restart the client using the current connection mode.
    @MainActor
    public func restart() {
        start()
    }

    @MainActor
    public func stop() {
        switch state {
        case .idle:
            break

        case let .advertising(advertisingTask):
            log("Stopped advertising")
            advertisingTask.cancel()

        case let .connecting(webSocketTask):
            log("Canceled in-flight connection attempt")
            webSocketTask.cancel()

        case let .connected(webSocketTask, _):
            log("Connection closed")
            for plugin in plugins {
                plugin.onDisconnect()
            }
            webSocketTask.cancel()
        }
        state = .idle
    }

}

// MARK: -

fileprivate func log(_ message: String) {
    print("[EchoClient] \(message)")
}

// MARK: -


