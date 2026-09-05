import ArgumentParser
import EchoConnection
import Foundation
import Network

struct ConnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect to a device and capture debug data."
    )

    @Flag(name: .long, help: "List available devices and exit.")
    var list: Bool = false

    @Flag(name: .shortAndLong, help: "Interactive mode with device picker and live dashboard.")
    var interactive: Bool = false

    @Argument(help: "Device name or ID to connect to. Omit with --list to discover devices.")
    var device: String?

    @Option(name: .long, help: "Port for the WebSocket server.")
    var port: Int = 34200

    func run() throws {
        if list {
            listDevices()
            return
        }

        // Interactive mode: show device picker if no device specified and stdin is a TTY
        let useInteractive = (interactive || device == nil) && TerminalUI.isInteractive
        if useInteractive && device == nil {
            guard let selected = pickDeviceInteractively() else {
                if TerminalUI.isInteractive {
                    print("No device selected.")
                } else {
                    print("Usage: echoapp connect <device-name>")
                    print("       echoapp connect --list")
                    print("")
                    print("Run with --list first to see available devices.")
                }
                return
            }
            try connectToDevice(selected: selected, showMonitor: useInteractive)
            return
        }

        guard let device else {
            print("Usage: echoapp connect <device-name>")
            print("       echoapp connect --list")
            print("")
            print("Run with --list first to see available devices.")
            return
        }

        try connectToDevice(named: device, showMonitor: interactive)
    }

    // MARK: - List Devices

    private func listDevices() {
        let browser = DeviceBrowser()
        print("Searching for devices (3 seconds)...")

        browser.start()

        // Discover ADB devices in parallel
        var adbDevices: [DiscoveredDevice] = []
        if let adbPath = ADBDiscovery.locateADB() {
            print("  (adb found at \(adbPath))")
            adbDevices = ADBDiscovery.discoverDevices(adbPath: adbPath)
        }

        Thread.sleep(forTimeInterval: 3)
        let bonjourDevices = browser.discoveredDevices

        browser.stop()

        let devices = bonjourDevices + adbDevices

        if devices.isEmpty {
            print("No devices found. Make sure:")
            print("  - Your iOS/Android app has Echo integrated")
            print("  - The device is on the same network (iOS) or connected via USB/ADB (Android)")
            print("  - The app is running")
            return
        }

        print("\nAvailable devices:")
        for device in devices {
            let displayName = device.displayName ?? device.name
            let typeLabel = device.isAndroid ? "android" : "ios"
            print("  \(displayName) [\(typeLabel)] (id: \(device.name))")
        }
    }

    // MARK: - Interactive Device Picker

    private func pickDeviceInteractively() -> DiscoveredDevice? {
        let browser = DeviceBrowser()
        browser.start()

        var adbDevices: [DiscoveredDevice] = []
        if let adbPath = ADBDiscovery.locateADB() {
            adbDevices = ADBDiscovery.discoverDevices(adbPath: adbPath)
        }

        let selected = DevicePicker.pick(browser: browser, adbDevices: adbDevices, timeout: 10)
        browser.stop()
        return selected
    }

    // MARK: - Connect (by name lookup)

    private func connectToDevice(named deviceName: String, showMonitor: Bool) throws {
        // Discover devices via Bonjour and ADB
        let browser = DeviceBrowser()
        browser.start()

        print("Searching for '\(deviceName)'...")

        // Check ADB devices while Bonjour discovery runs
        let adbPath = ADBDiscovery.locateADB()
        var adbDevices: [DiscoveredDevice] = []
        if let adbPath {
            adbDevices = ADBDiscovery.discoverDevices(adbPath: adbPath)
        }

        var targetDevice: DiscoveredDevice?
        let deadline = Date().addingTimeInterval(10)

        // Check ADB results first for an immediate match
        targetDevice = adbDevices.first(where: {
            $0.name.range(of: deviceName, options: .caseInsensitive) != nil ||
            ($0.displayName?.range(of: deviceName, options: .caseInsensitive) != nil)
        })

        // Poll Bonjour if no ADB match
        if targetDevice == nil {
            while Date() < deadline {
                if let match = browser.discoveredDevices.first(where: {
                    $0.name.range(of: deviceName, options: .caseInsensitive) != nil ||
                    ($0.displayName?.range(of: deviceName, options: .caseInsensitive) != nil)
                }) {
                    targetDevice = match
                    break
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        guard let targetDevice else {
            print("Device '\(deviceName)' not found. Available devices:")
            for d in browser.discoveredDevices + adbDevices {
                print("  \(d.displayName ?? d.name)")
            }
            browser.stop()
            throw ExitCode.failure
        }

        browser.stop()
        try connectToDevice(selected: targetDevice, showMonitor: showMonitor)
    }

    // MARK: - Connect (selected device)

    private func connectToDevice(selected targetDevice: DiscoveredDevice, showMonitor: Bool) throws {
        print("Found \(targetDevice.displayName ?? targetDevice.name)")

        // Start WebSocket server, trying subsequent ports if the default is in use
        let server = try startServer(from: port)

        let serverURL = server.webSocketURL
        print("WebSocket server listening on \(serverURL)")

        // Ensure session directory exists before writing PID file
        try FileManager.default.createDirectory(at: SessionDirectory.baseURL, withIntermediateDirectories: true)

        // Write PID file for clear command
        let pidURL = SessionDirectory.baseURL.appendingPathComponent("echoapp.pid")
        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)".write(to: pidURL, atomically: true, encoding: .utf8)

        // Set up JSONL writer
        let writer = CLISessionWriter(baseURL: SessionDirectory.baseURL)
        let deviceType = targetDevice.isAndroid ? "android" : "ios"
        let sessionID = try writer.startSession(
            deviceName: targetDevice.displayName ?? targetDevice.name,
            deviceType: deviceType
        )

        // Set up the monitor view for interactive mode
        let monitor: SessionMonitorView? = showMonitor ? SessionMonitorView(
            deviceName: targetDevice.displayName ?? targetDevice.name,
            deviceType: deviceType,
            sessionID: sessionID,
            sessionPath: writer.sessionPath!
        ) : nil

        if !showMonitor {
            print("Session: \(sessionID)")
            print("Writing to: \(writer.sessionPath!)")
            print("")
        }

        // Registry entry will be written after a successful connection
        let registryEntry = SessionDirectory.registryURL.appendingPathComponent("\(pid).json")

        // Set up networking proxy to handle proxy-mode requests
        let networkingProxy = NetworkingProxy(sendPayload: { [weak server] payload, ws in
            if let ws {
                server?.send(payload, to: ws)
            } else {
                server?.send(payload)
            }
        })

        // Handle incoming payloads
        let lock = NSLock()
        var payloadCount = 0
        server.onPayload = { payload, ws in
            do {
                try writer.append(payload: payload)
                let pluginID = CLISessionWriter.sanitizePluginID(payload.pluginID)

                lock.lock()
                payloadCount += 1
                let count = payloadCount
                lock.unlock()

                if let monitor {
                    monitor.recordPayload(pluginID: pluginID)
                } else {
                    FileHandle.standardError.write(
                        "\r\u{1B}[K\(count) payloads captured (\(pluginID))".data(using: .utf8)!
                    )
                }
            } catch {
                FileHandle.standardError.write(
                    "\nFailed to write payload: \(error)\n".data(using: .utf8)!
                )
            }

            networkingProxy.handleIfProxyRequest(payload, from: ws)
        }

        server.onClientConnected = {
            networkingProxy.reset()
            if let monitor {
                monitor.setStatus(.connected)
            } else {
                print("Device connected! Receiving data...")
            }
        }

        server.onClientInfo = { pluginIDs in
            writer.updateClientPluginIDs(pluginIDs)
        }

        // Shared shutdown logic
        var hasShutDown = false
        func shutdown(reason: String) {
            lock.lock()
            guard !hasShutDown else {
                lock.unlock()
                return
            }
            hasShutDown = true
            let count = payloadCount
            lock.unlock()

            if let monitor {
                monitor.setStatus(.disconnected)
                monitor.stop()
            }

            FileHandle.standardError.write("\n".data(using: .utf8)!)
            print("\(reason) \(count) total payloads captured.")
            writer.endSession()
            try? FileManager.default.removeItem(at: pidURL)
            try? FileManager.default.removeItem(at: registryEntry)
            server.stop()
        }

        server.onClientDisconnected = {
            shutdown(reason: "Device disconnected.")
            Foundation.exit(0)
        }

        // Send connection request to device
        if !showMonitor {
            print("Connecting to \(targetDevice.displayName ?? targetDevice.name)...")
        }

        // Discover ADB path for Android connection
        let adbPath = ADBDiscovery.locateADB()
        if targetDevice.isAndroid, let serial = targetDevice.adbSerial, let socket = targetDevice.echoSocket, let adbPath {
            do {
                try ADBDiscovery.sendConnectionRequest(
                    ConnectionRequest(serverURL: serverURL),
                    adbPath: adbPath,
                    serial: serial,
                    socket: socket,
                    serverURL: serverURL
                )
            } catch {
                print("Failed to connect to Android device: \(error)")
                throw ExitCode.failure
            }
        } else {
            let connected = sendConnectionRequest(to: targetDevice, serverURL: serverURL)
            if !connected {
                print("Failed to connect to device.")
                throw ExitCode.failure
            }
        }
        // Register this CLI session now that the connection succeeded
        try FileManager.default.createDirectory(at: SessionDirectory.registryURL, withIntermediateDirectories: true)
        let registryData = try JSONEncoder().encode(SessionRegistryEntry(
            pid: pid,
            port: server.serverPort,
            sessionDir: writer.sessionPath!,
        ))
        try registryData.write(to: registryEntry)

        if showMonitor {
            monitor?.start()
        } else {
            print("Connection request sent. Waiting for data...")
            print("Press Ctrl+C to stop.\n")
        }

        // Use a dedicated queue for signal handlers since the main thread is
        // blocked by waitUntilShutdown().
        let signalQueue = DispatchQueue(label: "echoapp.signals")

        // Handle SIGUSR1 to clear session data
        signal(SIGUSR1, SIG_IGN)
        let clearSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: signalQueue)
        clearSource.setEventHandler {
            writer.clear()
            lock.lock()
            payloadCount = 0
            lock.unlock()
            if let monitor {
                monitor.resetStats()
            } else {
                FileHandle.standardError.write(
                    "\r\u{1B}[KSession data cleared.\n".data(using: .utf8)!
                )
            }
        }
        clearSource.resume()

        // Handle Ctrl+C
        signal(SIGINT, SIG_IGN)
        let shutdownSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        shutdownSource.setEventHandler {
            shutdown(reason: "Interrupted.")
            Foundation.exit(0)
        }
        shutdownSource.resume()

        // Block until the server is shut down (via disconnect or Ctrl+C handlers).
        try server.waitUntilShutdown()
    }

    private func startServer(from basePort: Int, maxAttempts: Int = 10) throws -> CLIServer {
        var currentPort = basePort
        for attempt in 0..<maxAttempts {
            let candidate = CLIServer(port: currentPort)
            do {
                try candidate.start()
                return candidate
            } catch {
                let nsError = error as NSError
                let isAddressInUse = (nsError.domain == NSPOSIXErrorDomain && nsError.code == 48)
                    || (nsError.domain == "NWError" && "\(error)".contains("Address already in use"))
                if isAddressInUse && attempt < maxAttempts - 1 {
                    if attempt == 0 {
                        FileHandle.standardError.write(
                            "Port \(currentPort) in use, trying next...\n".data(using: .utf8)!
                        )
                    }
                    currentPort += 1
                    continue
                }
                throw error
            }
        }
        // Unreachable: the loop always returns or throws
        throw CLIServerError.allPortsInUse(basePort: basePort, attempts: maxAttempts)
    }

    private func sendConnectionRequest(to device: DiscoveredDevice, serverURL: URL) -> Bool {
        let request = ConnectionRequest(serverURL: serverURL)
        guard let encoded = try? JSONEncoder().encode(request) else {
            print("Failed to encode connection request")
            return false
        }

        let connection = NWConnection(to: device.endpoint, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var didFail = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: encoded,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            print("Failed to send connection request: \(error)")
                            didFail = true
                        }
                        semaphore.signal()
                    }
                )
            case let .failed(error):
                connection.cancel()
                print("Connection failed: \(error)")
                didFail = true
                semaphore.signal()
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .init(label: "echoapp.connect", qos: .userInitiated))
        semaphore.wait()
        return !didFail
    }
}

// MARK: - DiscoveredDevice

struct DiscoveredDevice {
    let name: String
    let displayName: String?
    let endpoint: NWEndpoint
    let isAndroid: Bool
    var adbSerial: String?
    var echoSocket: String?
}

// MARK: - DeviceBrowser

final class DeviceBrowser: @unchecked Sendable {
    private var browser: NWBrowser?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "echoapp.browser", qos: .userInitiated)
    private var _discoveredDevices: [DiscoveredDevice] = []

    var discoveredDevices: [DiscoveredDevice] {
        lock.lock()
        defer { lock.unlock() }
        return _discoveredDevices
    }

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_echoclient._tcp", domain: nil),
            using: parameters
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let devices = results.compactMap { result -> DiscoveredDevice? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }

                let isAndroid = name.hasSuffix(":android_emulator")
                var displayName: String?
                if case let .bonjour(txtRecord) = result.metadata {
                    displayName = txtRecord["device_name"]
                }
                if displayName == nil && isAndroid {
                    displayName = name.components(separatedBy: ":").first
                }

                var endpoint = result.endpoint
                if isAndroid {
                    endpoint = NWEndpoint.hostPort(
                        host: .init("10.0.2.2"),
                        port: .init(rawValue: 34143)!
                    )
                }

                return DiscoveredDevice(
                    name: name,
                    displayName: displayName,
                    endpoint: endpoint,
                    isAndroid: isAndroid
                )
            }
            self.lock.lock()
            self._discoveredDevices = devices
            self.lock.unlock()
        }

        browser.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

// MARK: - CLIServerError

enum CLIServerError: Error {
    case allPortsInUse(basePort: Int, attempts: Int)
}
