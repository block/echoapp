import EchoConnection
import Foundation
import Network

// MARK: - ADBDiscovery

/// Lightweight ADB device discovery for the CLI.
/// Mirrors the Echo app's ADB discovery logic without depending on the Echo target.
enum ADBDiscovery {

    static let defaultPaths = [
        "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
        "/opt/homebrew/bin/adb",
    ]

    static let emulatorHost = "127.0.0.1"

    private static let adbTimeout: TimeInterval = 5

    /// Locate the adb binary on disk.
    static func locateADB() -> String? {
        // Check $ANDROID_HOME first
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            let path = "\(androidHome)/platform-tools/adb"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        for path in defaultPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Discover Android devices with Echo enabled via `adb`.
    static func discoverDevices(adbPath: String) -> [DiscoveredDevice] {
        guard let rawDevices = try? runADB(adbPath, "devices", "-l") else { return [] }

        let adbDevices = parseDeviceList(rawDevices)
        return adbDevices.compactMap { device -> DiscoveredDevice? in
            // Check if device has the echo-server unix domain socket
            guard let socketInfo = try? runADB(adbPath, "-s", device.serial, "shell", "ss", "-xl"),
                  let echoSocket = findEchoSocket(in: socketInfo) else {
                return nil
            }

            let displayName = device.model ?? device.product ?? device.serial
            return DiscoveredDevice(
                name: device.serial,
                displayName: displayName,
                endpoint: NWEndpoint.hostPort(
                    host: .init(emulatorHost),
                    port: .init(rawValue: 0)!
                ),
                isAndroid: true,
                adbSerial: device.serial,
                echoSocket: echoSocket
            )
        }
    }

    /// Set up port forwarding for an ADB device's echo-server socket.
    /// Uses dynamic port allocation (`tcp:0`) to support multiple devices.
    /// Returns the assigned local port.
    static func portForward(adbPath: String, serial: String, socket: String) throws -> UInt16 {
        let output = try runADB(adbPath, "-s", serial, "forward", "tcp:0", "localabstract:\(socket)")
        guard let port = UInt16(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "ADB", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse forwarded port from adb output: \(output)"])
        }
        return port
    }

    /// Remove a port forwarding rule.
    static func removePortForward(adbPath: String, serial: String, port: UInt16) {
        try? runADB(adbPath, "-s", serial, "forward", "--remove", "tcp:\(port)")
    }

    /// Send a connection request to an ADB device via the forwarded port,
    /// then bridge the ADB tunnel to the local WebSocket server.
    static func sendConnectionRequest(_ request: ConnectionRequest, adbPath: String, serial: String, socket: String, serverURL: URL) throws {
        let forwardedPort = try portForward(adbPath: adbPath, serial: serial, socket: socket)

        let connection = NWConnection(
            host: .init(emulatorHost),
            port: .init(rawValue: forwardedPort)!,
            using: .tcp
        )
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: Error?

        var payload = try JSONEncoder().encode(request)
        payload.append(contentsOf: "\n".utf8) // newline for Android's readLine()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: payload,
                    contentContext: .defaultMessage,
                    isComplete: false,
                    completion: .contentProcessed { error in
                        if let error {
                            sendError = error
                            connection.cancel()
                        }
                        semaphore.signal()
                    }
                )
            case let .failed(error):
                sendError = error
                connection.cancel()
                semaphore.signal()
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .init(label: "echoapp.adb-connect", qos: .userInitiated))

        let result = semaphore.wait(timeout: .now() + 10)
        if result == .timedOut {
            connection.cancel()
            throw NSError(domain: "ADB", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out connecting to Android device on port \(forwardedPort)"])
        }

        if let error = sendError {
            throw error
        }

        // Bridge the ADB-forwarded connection to the local WebSocket server
        guard let host = serverURL.host, let port = serverURL.port,
              let nwPort = NWEndpoint.Port(rawValue: UInt16(exactly: port)!) else {
            throw NSError(domain: "ADB", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server URL: \(serverURL)"])
        }
        bridgeConnection(connection, host: host, port: nwPort)
    }

    /// Bidirectional forwarding between the ADB-forwarded connection and the local WebSocket server.
    private static func bridgeConnection(_ androidConnection: NWConnection, host: String, port: NWEndpoint.Port) {
        let localConnection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )

        func pipe(from: NWConnection, to: NWConnection) {
            from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    to.send(content: data, completion: .contentProcessed { sendError in
                        if sendError == nil {
                            pipe(from: from, to: to)
                        } else {
                            from.cancel()
                            to.cancel()
                        }
                    })
                } else if error != nil || isComplete {
                    from.cancel()
                    to.cancel()
                } else {
                    pipe(from: from, to: to)
                }
            }
        }

        localConnection.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .ready:
                pipe(from: androidConnection, to: localConnection)
                pipe(from: localConnection, to: androidConnection)
            case .failed, .cancelled:
                androidConnection.cancel()
                localConnection.cancel()
            case .setup, .preparing, .waiting:
                break
            @unknown default:
                break
            }
        }
        localConnection.start(queue: DispatchQueue(label: "echoapp.adb-bridge", qos: .background))
    }

    // MARK: - Private

    private struct ADBDevice {
        let serial: String
        let product: String?
        let model: String?
    }

    private static func parseDeviceList(_ output: String) -> [ADBDevice] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.lowercased().contains("list of devices"),
                  trimmed.contains(" device ") else {
                return nil
            }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let serial = parts.first else { return nil }

            var attrs: [String: String] = [:]
            for token in parts.dropFirst() {
                let kv = token.split(separator: ":", maxSplits: 1).map(String.init)
                if kv.count == 2 { attrs[kv[0]] = kv[1] }
            }

            return ADBDevice(
                serial: serial,
                product: attrs["product"]?.replacingOccurrences(of: "_", with: " "),
                model: attrs["model"]?.replacingOccurrences(of: "_", with: " ")
            )
        }
    }

    private static func findEchoSocket(in ssOutput: String) -> String? {
        for line in ssOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if let socket = fields.first(where: { $0.contains("@echo-server") }) {
                var name = String(socket)
                if name.hasPrefix("@") { name = String(name.dropFirst()) }
                return name
            }
        }
        return nil
    }

    @discardableResult
    private static func runADB(_ adbPath: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Kill if still running after timeout
        if process.isRunning {
            process.terminate()
            throw NSError(domain: "ADB", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "adb \(arguments.joined(separator: " ")) timed out"])
        }

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ADB", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "adb \(arguments.joined(separator: " ")) failed"])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
