import EchoConnection
import Foundation
import Logging
import Vapor

// MARK: - CLIServer

final class CLIServer: @unchecked Sendable {
    let serverPort: Int
    private var app: Application?
    private let maxFrameSize = WebSocketMaxFrameSize(integerLiteral: 16 * 1024 * 1024)
    private var activeWebSocket: WebSocket?
    private let wsLock = NSLock()

    var onPayload: ((PluginPayload, WebSocket) -> Void)?
    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?
    /// Fired when the connected client sends a `ClientInfoPayload` advertising
    /// which `ClientPlugin`s it has loaded. Persisted by the session writer so
    /// plugin-aware CLI subcommands can distinguish "plugin not implemented"
    /// from "implemented but no data yet."
    var onClientInfo: (([String]) -> Void)?

    var webSocketURL: URL {
        let ip = getPreferredIP() ?? "127.0.0.1"
        return URL(string: "ws://\(ip):\(serverPort)/channel")!
    }

    init(port: Int) {
        self.serverPort = port
    }

    func start() throws {
        var env = Environment(name: "echoapp", arguments: ["echoapp"])
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = serverPort
        app.http.server.configuration.requestDecompression = .enabled(limit: .none)
        app.http.server.configuration.responseCompression = .enabled(initialByteBufferCapacity: 4096)

        // Suppress Vapor's noisy console output
        app.logger.logLevel = .error

        app.on(.POST, "api", "send") { [weak self] req -> Response in
            guard let self else { return Response(status: .serviceUnavailable) }
            // The WebSocket channel must bind to 0.0.0.0 so devices on the LAN
            // can connect, but `/api/send` is only meant for the local CLI.
            // Reject non-loopback callers so a peer on the same Wi-Fi can't
            // forward arbitrary plugin payloads to the device.
            guard self.isLoopback(req.remoteAddress?.ipAddress) else {
                return Response(status: .forbidden)
            }
            let payload = try req.content.decode(PluginPayload.self)
            guard self.send(payload) else {
                // No connected device — surface the no-op as a 503 so the CLI
                // can stop printing "set to ON" when nothing was forwarded.
                return Response(status: .serviceUnavailable)
            }
            return Response(status: .ok)
        }

        app.webSocket("channel", maxFrameSize: maxFrameSize) { [weak self] _, ws in
            guard let self else { return }
            self.wsLock.lock()
            self.activeWebSocket = ws
            self.wsLock.unlock()
            self.onClientConnected?()

            ws.onBinary { [weak self] ws, byteBuffer in
                guard let self else { return }
                if let payload = try? JSONDecoder().decode(PluginPayload.self, from: byteBuffer) {
                    self.onPayload?(payload, ws)
                    return
                }
                if let info = try? JSONDecoder().decode(ClientInfoPayload.self, from: byteBuffer) {
                    self.onClientInfo?(info.clientPluginIDs)
                    return
                }
            }

            ws.onClose.whenComplete { [weak self] _ in
                guard let self else { return }
                self.wsLock.lock()
                let wasActive = self.activeWebSocket === ws
                if wasActive {
                    self.activeWebSocket = nil
                }
                self.wsLock.unlock()
                // Only fire disconnect for the active socket -- stale socket
                // closes during reconnect overlap should not trigger shutdown.
                if wasActive {
                    self.onClientDisconnected?()
                }
            }
        }

        self.app = app
        try app.start()
    }

    /// Block the calling thread until the server is shut down.
    func waitUntilShutdown() throws {
        try app?.running?.onStop.wait()
    }

    /// Returns true if the payload was forwarded to a live WebSocket, false
    /// when no device is connected (or the socket closed mid-send) so callers
    /// can surface the no-op. The intermediate `sendTo` re-checks `isClosed`
    /// inside the lock to close the small window between our initial guard and
    /// the actual `ws.send(...)` call.
    @discardableResult
    func send(_ payload: PluginPayload) -> Bool {
        wsLock.lock()
        let ws = activeWebSocket
        wsLock.unlock()

        guard let ws else { return false }
        return sendTo(ws, payload: payload)
    }

    @discardableResult
    func send(_ payload: PluginPayload, to ws: WebSocket) -> Bool {
        guard !ws.isClosed else {
            FileHandle.standardError.write(
                "Dropping payload for closed WebSocket (not rerouting to new client)\n".data(using: .utf8)!
            )
            return false
        }
        return sendTo(ws, payload: payload)
    }

    @discardableResult
    private func sendTo(_ ws: WebSocket, payload: PluginPayload) -> Bool {
        // Re-check `isClosed` under the lock to close the small window where
        // the socket can transition to closed between the caller's guard and
        // `ws.send(...)`. We still can't strictly prove the byte made it onto
        // the wire (Vapor's `send` is fire-and-forget), but this stops us from
        // reporting success when the socket is observably already gone.
        wsLock.lock()
        let isLive = !ws.isClosed
        wsLock.unlock()
        guard isLive else { return false }
        do {
            let data = try JSONEncoder().encode(payload)
            ws.send(raw: data, opcode: .binary)
            return true
        } catch {
            FileHandle.standardError.write(
                "Failed to send payload: \(error)\n".data(using: .utf8)!
            )
            return false
        }
    }

    func stop() {
        app?.shutdown()
        app = nil
    }

    private func isLoopback(_ ip: String?) -> Bool {
        guard let ip else { return false }
        return ip == "127.0.0.1" || ip == "::1" || ip.hasPrefix("::ffff:127.")
    }

    private func getPreferredIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        var candidates: [String: String] = [:]
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "lo0" { continue }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    candidates[name] = String(cString: hostname)
                }
            }
        }

        return candidates["en0"]
            ?? candidates.first(where: { $0.key.hasPrefix("en") })?.value
            ?? candidates.values.first
    }
}
