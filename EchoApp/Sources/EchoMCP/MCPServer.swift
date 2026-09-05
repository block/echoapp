import EchoPluginAPI
import Foundation
import Logging
import MCP
import Network
import Vapor

// MARK: - DeviceSession

public struct DeviceSession: Sendable {
    public let id: String
    public let name: String?
    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

// MARK: - MCPServer

/// Plugin-agnostic MCP server.
///
/// Discovers MCPToolProvider conformances from the loaded plugin list at startup.
/// Device management tools (list/connect/disconnect_device) are built-in.
/// All other tools are delegated to registered providers.
///
/// Does NOT call LoggingSystem.bootstrap — Echo's main app handles that once.
public final class MCPServer {

    // MARK: - Static

    public static var configFileURL: URL {
        URL.homeDirectory
            .appending(path: ".config/echo", directoryHint: .isDirectory)
            .appending(path: "mcp.json")
    }

    public static var wrapperScriptDestURL: URL {
        URL.homeDirectory
            .appending(path: ".config/echo", directoryHint: .isDirectory)
            .appending(path: "echo-mcp")
    }

    // MARK: - Private Properties

    private let port: Int
    // Overridable in tests to avoid parallel-test config file collisions
    internal let configFileURL: URL
    private var vaporApp: Application?
    private var mcpSDKServer: MCP.Server?
    private var mcpTask: Task<Void, Never>?
    private var currentTransport: StatefulHTTPServerTransport?
    @MainActor private var currentSession: DeviceSession?

    // Provider registry — populated at start(plugins:)
    private var providers: [any MCPToolProvider] = []

    // Device discovery
    @MainActor private var bonjourBrowser: NWBrowser?
    @MainActor private var bonjourResults: Set<NWBrowser.Result> = []

    // Set by SessionViewModel to forward connect requests into the main app
    @MainActor public var connectDeviceHandler: (@MainActor @Sendable (String) -> Bool)?

    // MARK: - Life Cycle

    public init(port: Int = 34001, configFileURL: URL? = nil) {
        self.port = port
        self.configFileURL = configFileURL ?? MCPServer.configFileURL
    }

    /// Starts the MCP server, auto-discovering MCPToolProvider conformances from plugins.
    public func start(plugins: [any DesktopPlugin] = []) throws {
        providers = plugins.compactMap { $0 as? any MCPToolProvider }
        try startInternal(environment: .production, bindToPort: true)
    }

    /// For tests: sets up routes without binding to a network port.
    public func startForTesting(plugins: [any DesktopPlugin] = []) throws {
        providers = plugins.compactMap { $0 as? any MCPToolProvider }
        try startInternal(environment: .testing, bindToPort: false)
    }

    public func stop() {
        mcpTask?.cancel()
        mcpTask = nil
        let server = mcpSDKServer
        Task { await server?.stop() }
        mcpSDKServer = nil
        currentTransport = nil
        vaporApp?.shutdown()
        vaporApp = nil
        Task { @MainActor in self.stopBonjourDiscovery() }
        removeConfigFile()
    }

    @MainActor
    public func setSession(_ session: DeviceSession?) {
        currentSession = session
    }

    // MARK: - Internal helpers (exposed for testing)

    @MainActor
    public func listDevices(adbDevices: [[String: Any]] = []) -> [[String: Any]] {
        var devices: [[String: Any]] = []
        let connectedId = currentSession?.id

        // Connected device
        if let session = currentSession {
            var device: [String: Any] = ["id": session.id, "status": "connected"]
            if let name = session.name { device["name"] = name }
            devices.append(device)
        }

        // Bonjour-discovered available devices
        for result in bonjourResults {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            if name == connectedId { continue }

            let isAndroid = name.hasSuffix(":android_emulator")
            var displayName = isAndroid
                ? (name.components(separatedBy: ":").first ?? name)
                : name
            if case let .bonjour(txtRecord) = result.metadata,
               let txtName = txtRecord["device_name"] {
                displayName = txtName
            }

            devices.append([
                "id": name,
                "name": displayName,
                "status": "available",
                "type": isAndroid ? "android" : "ios",
            ])
        }

        // ADB devices not already represented in Bonjour results
        let bonjourIds = Set(bonjourResults.compactMap { result -> String? in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            return name
        })
        for adb in adbDevices {
            let adbId = adb["id"] as? String ?? ""
            guard adbId != connectedId else { continue }
            let alreadyShown = bonjourIds.contains { $0.hasPrefix(adbId) }
            if !alreadyShown { devices.append(adb) }
        }

        return devices
    }

    // MARK: - Private

    private func startInternal(environment: Environment, bindToPort: Bool) throws {
        resetTransport()

        let app = Application(environment)
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = port

        let handler: (Vapor.Request) async throws -> Vapor.Response = { [weak self] req in
            guard let self else { throw Abort(.internalServerError) }
            return try await self.bridge(req)
        }
        app.on(.POST, "mcp", use: handler)
        app.on(.GET, "mcp", use: handler)
        app.on(.DELETE, "mcp", use: handler)

        vaporApp = app
        if bindToPort { try app.start() }
        writeConfigFile()
        Task { @MainActor in self.startBonjourDiscovery() }
    }

    private func bridge(_ req: Vapor.Request) async throws -> Vapor.Response {
        let isInitialize = req.method == .POST && req.headers.first(name: "Mcp-Session-Id") == nil
        if isInitialize { resetTransport() }

        guard let transport = currentTransport else { throw Abort(.serviceUnavailable) }
        let headers = Dictionary(req.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 })
        let body = req.body.data.map { Data(buffer: $0) }
        let mcpReq = MCP.HTTPRequest(method: req.method.rawValue, headers: headers, body: body)
        let mcpResp = await transport.handleRequest(mcpReq)
        if req.method == .DELETE { resetTransport() }

        switch mcpResp {
        case .accepted(let h):
            return vaporResponse(status: .accepted, extraHeaders: h, body: nil)
        case .ok(let h):
            return vaporResponse(status: .ok, extraHeaders: h, body: nil)
        case .data(let data, let h):
            return vaporResponse(status: .ok, extraHeaders: h, body: data)
        case .error(let code, _, _, _):
            let body = mcpResp.bodyData
            let extraHeaders = mcpResp.headers.isEmpty ? nil : mcpResp.headers
            return vaporResponse(status: .init(statusCode: code), extraHeaders: extraHeaders, body: body)
        case .stream(let stream, let h):
            let response = Vapor.Response(status: .ok)
            response.headers.add(name: "Content-Type", value: "text/event-stream")
            response.headers.add(name: "Cache-Control", value: "no-cache")
            h.forEach { response.headers.replaceOrAdd(name: $0.key, value: $0.value) }
            response.body = .init(stream: { writer in
                Task {
                    do {
                        for try await chunk in stream {
                            _ = try await writer.write(.buffer(.init(data: chunk)))
                        }
                        _ = try await writer.write(.end)
                    } catch {
                        _ = try? await writer.write(.error(error))
                    }
                }
            })
            return response
        }
    }

    private func vaporResponse(status: HTTPResponseStatus, extraHeaders: [String: String]?, body: Data?) -> Vapor.Response {
        var response = body.map { Vapor.Response(status: status, body: .init(data: $0)) } ?? Vapor.Response(status: status)
        extraHeaders?.forEach { response.headers.replaceOrAdd(name: $0.key, value: $0.value) }
        return response
    }

    /// Recreates the MCP transport and server, re-registering all tools.
    private func resetTransport() {
        mcpTask?.cancel()
        mcpTask = nil
        let transport = StatefulHTTPServerTransport()
        currentTransport = transport
        let server = MCP.Server(
            name: "echo",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        mcpSDKServer = server
        let snapshot = providers
        mcpTask = Task { [weak self, weak server] in
            guard let self, let server else { return }
            await self.registerTools(on: server, providers: snapshot)
            try? await server.start(transport: transport)
        }
    }

    private func registerTools(on server: MCP.Server, providers: [any MCPToolProvider]) async {
        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard let self else { return .init(tools: []) }
            var tools = self.builtInTools()
            for provider in providers { tools.append(contentsOf: provider.mcpTools) }
            return .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params async throws in
            guard let self else { return .init(content: [.text("Server unavailable")], isError: true) }
            return try await self.dispatch(params, providers: providers)
        }
    }

    private func builtInTools() -> [Tool] {
        [
            Tool(
                name: "list_devices",
                description: "Lists devices. Shows the currently connected device (status: connected) and any available devices discovered via Bonjour or ADB (status: available).",
                inputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "connect_device",
                description: "Connects to an available device. Use the 'id' from list_devices output.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Device ID from list_devices")]),
                    ]),
                    "required": .array([.string("id")])
                ])
            ),
            Tool(
                name: "disconnect_device",
                description: "Clears the currently connected device from the Echo MCP session. Use this to reset the session if the device appears stale or disconnected.",
                inputSchema: .object(["type": .string("object")])
            ),
        ]
    }

    private func dispatch(_ params: CallTool.Parameters, providers: [any MCPToolProvider]) async throws -> CallTool.Result {
        switch params.name {
        case "list_devices":
            let adbDevices = await fetchADBDevices()
            let devices = await MainActor.run { self.listDevices(adbDevices: adbDevices) }
            if devices.isEmpty {
                return .init(content: [.text("No devices found. Open EchoApp.app, connect a device, or ensure adb is available for Android.")], isError: false)
            }
            let json = try JSONSerialization.data(withJSONObject: devices, options: [.prettyPrinted])
            return .init(content: [.text(String(data: json, encoding: .utf8) ?? "[]")], isError: false)

        case "connect_device":
            guard let id = params.arguments?["id"]?.stringValue else {
                return .init(content: [.text("Missing required 'id' parameter.")], isError: true)
            }
            let handler = await MainActor.run { self.connectDeviceHandler }
            guard let handler else {
                return .init(content: [.text("Connect is unavailable — Echo is still initializing.")], isError: true)
            }
            let success = await MainActor.run { handler(id) }
            if success {
                return .init(content: [.text("Connection request sent to '\(id)'. Use list_devices to confirm when connected.")], isError: false)
            } else {
                return .init(content: [.text("No available device with id '\(id)'. Use list_devices to see available devices.")], isError: false)
            }

        case "disconnect_device":
            let hadSession = await MainActor.run {
                let had = self.currentSession != nil
                if had { self.setSession(nil) }
                return had
            }
            if hadSession {
                return .init(content: [.text("Device disconnected from Echo MCP session.")], isError: false)
            } else {
                return .init(content: [.text("No device is currently connected.")], isError: false)
            }

        default:
            for provider in providers {
                if provider.mcpTools.contains(where: { $0.name == params.name }) {
                    return try await provider.handle(toolName: params.name, arguments: params.arguments)
                }
            }
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }
    }

    // MARK: - Device Discovery

    @MainActor
    private func startBonjourDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_echoclient._tcp", domain: nil),
            using: parameters
        )
        bonjourBrowser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.bonjourResults = results
            }
        }
        browser.start(queue: .main)
    }

    @MainActor
    private func stopBonjourDiscovery() {
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        bonjourResults = []
    }

    private func fetchADBDevices() async -> [[String: Any]] {
        let knownPaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
        ]
        guard let adbPath = knownPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return []
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = adbPath
            process.arguments = ["devices", "-l"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: Self.parseADBOutput(output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private static func parseADBOutput(_ output: String) -> [[String: Any]] {
        output.split(separator: "\n").compactMap { line -> [String: Any]? in
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.lowercased().contains("list of devices"),
                  trimmed.contains(" device ") else { return nil }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let name = parts.first else { return nil }

            var attrs: [String: String] = [:]
            for token in parts.dropFirst() {
                let kv = token.split(separator: ":", maxSplits: 1).map(String.init)
                if kv.count == 2 { attrs[kv[0]] = kv[1] }
            }

            let model = attrs["model"]?.replacingOccurrences(of: "_", with: " ")
            return ["id": name, "name": model ?? name, "status": "available", "type": "android"]
        }
    }

    // MARK: - Config file

    private func writeConfigFile() {
        do {
            try FileManager.default.createDirectory(at: configFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload: [String: Any] = ["port": port, "url": "http://127.0.0.1:\(port)/mcp"]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: configFileURL)
        } catch {
            print("[MCPServer] Failed to write config file: \(error)")
        }
        copyWrapperScript()
    }

    private func copyWrapperScript() {
        guard let src = Bundle.module.resourceURL?.appendingPathComponent("echo-mcp") else {
            print("[MCPServer] echo-mcp resource not found in bundle")
            return
        }
        let dest = MCPServer.wrapperScriptDestURL
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        } catch {
            print("[MCPServer] Failed to copy echo-mcp wrapper: \(error)")
        }
    }

    private func removeConfigFile() {
        try? FileManager.default.removeItem(at: configFileURL)
        try? FileManager.default.removeItem(at: MCPServer.wrapperScriptDestURL)
    }
}
