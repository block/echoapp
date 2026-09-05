import Foundation
import os

import EchoConnection
import EchoPluginAPI
import Logging
import Vapor

protocol Server {
    var webSocketURL: URL { get }
    var connectionUpdates: AsyncStream<(any ClientServerConnection)?> { get }
    var currentConnection: (any ClientServerConnection)? { get }

    func start() throws
    func closeCurrentConnection() async
    func beginExpectingConnection()
    func expectConnection(identifier: String?)
}

private var isLoggingInitialized = false
private let loggingInitLock = NSLock()

final class RealServer: Server {
    private let app: Vapor.Application
    private let logger = Logger.echoLogger(category: "Server")
    private let port: Int
    private let maxFrameSize = WebSocketMaxFrameSize(integerLiteral: Int(UInt32.max))
    private let connectionRegistry = ConnectionRegistry()

    var connectionUpdates: AsyncStream<(any ClientServerConnection)?> {
        connectionRegistry.stream
    }

    var currentConnection: (any ClientServerConnection)? {
        connectionRegistry.current
    }

    var webSocketURL: URL {
        // Use a real IP address that clients can connect to, not the bind address
        let advertisedIP = getPreferredIPAddress() ?? "127.0.0.1"
        let port = app.http.server.configuration.port
        return URL(string: "ws://\(advertisedIP):\(port)/channel")!
    }

    init(port: Int = 34143) {
        self.port = port
        var env = Environment(name: "Echo", arguments: [Bundle.main.executableURL!.absoluteString])
        
        loggingInitLock.lock()
        if !isLoggingInitialized {
            try! LoggingSystem.bootstrap(from: &env)
            isLoggingInitialized = true
        }
        loggingInitLock.unlock()
        
        app = Application(env)
        // Bind to all network interfaces so the server is accessible from anywhere
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = port
        app.http.server.configuration.requestDecompression = .enabled(limit: .none)
        app.http.server.configuration.responseCompression = .enabled(initialByteBufferCapacity: 4096)

        app.webSocket("channel", maxFrameSize: maxFrameSize) { [weak self] req, ws in
            guard let self else { return }

            // Native Echo clients provide identifiers in headers.
            var clientDeviceIdentifier: DeviceIdentifier?
            var appIdentifier: String?

            if let headerDeviceId = req.headers.first(name: EchoHTTPHeaders.deviceIdentifier) {
                clientDeviceIdentifier = DeviceIdentifier(value: headerDeviceId)
                appIdentifier = req.headers.first(name: EchoHTTPHeaders.appIdentifier) ?? "<unknown app>"
            } else {
                // Fallback to query parameters (web clients)
                let urlComponents = URLComponents(string: req.url.string)
                if let queryDeviceId = urlComponents?.queryItems?.first(where: { $0.name == "deviceId" })?.value {
                    clientDeviceIdentifier = DeviceIdentifier(value: queryDeviceId)
                }

                if let queryAppId = urlComponents?.queryItems?.first(where: { $0.name == "appId" })?.value {
                    appIdentifier = queryAppId
                }
            }

            guard let deviceId = clientDeviceIdentifier else {
                self.logger.warning("Missing device identifier (from headers or query params). Ignoring connection.")
                return
            }

            guard connectionRegistry.acceptsConnection(identifier: deviceId.value) else {
                self.logger.warning("Rejecting unexpected client connection: \(deviceId.value)")
                Task { try? await ws.close(code: .policyViolation) }
                return
            }

            let deviceName = req.headers.first(name: EchoHTTPHeaders.deviceName)
            let appId = appIdentifier ?? "<unknown app>"
            let connectionKey = "\(deviceId.value):\(appId)"
            
            let newConnection = RealClientServerConnection(
                connectedClient: .init(deviceIdentifier: deviceId, deviceName: deviceName, appIdentifier: appId),
                webSocket: ws
            )

            // Activate the replacement before publishing lifecycle updates. Consumers
            // validate each update against `currentConnection` before changing plugin state.
            if let existingConnection = connectionRegistry.activate(newConnection) {
                logger.warning("Replacing existing connection for \(connectionKey)")
                Task { await existingConnection.close() }
            }

            logger.info("Client connected: \(connectionKey)")

            ws.onClose.whenComplete { [weak self, weak newConnection, connectionID = newConnection.id] _ in
                guard let self else { return }
                newConnection?.finish()
                
                // Only clear if this exact WebSocket is still the current one.
                // Reconnects usually reuse the same device/app identifiers, so
                // identifier comparison is not strong enough here.
                connectionRegistry.clearIfActive(connectionID: connectionID)
                
                logger.info("Client disconnected: \(connectionKey)")
            }
        }
    }

    func start() throws {
        try app.start()
    }

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
}

func getPreferredIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        var candidateAddresses: [String: String] = [:]

        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            guard let socketAddress = interface.ifa_addr else { continue }
            let addrFamily = socketAddress.pointee.sa_family

            // Check for IPv4
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Ignore loopback
                if name == "lo0" { continue }

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    candidateAddresses[name] = ip
                }
            }
        }
        freeifaddrs(ifaddr)

        // Prefer en0 (Wi-Fi), then any 'en*' interface, then fallback
        if let en0 = candidateAddresses["en0"] {
            address = en0
        } else if let enMatch = candidateAddresses.first(where: { $0.key.hasPrefix("en") }) {
            address = enMatch.value
        } else if let first = candidateAddresses.values.first {
            address = first
        }
    }
    return address
}
