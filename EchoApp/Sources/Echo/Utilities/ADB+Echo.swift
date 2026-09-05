@preconcurrency import EchoConnection
import Foundation
import Network
import os

protocol AndroidTunnelConnection: AnyObject, Sendable {
    var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)? { get set }

    func send(
        content: Data?,
        contentContext: NWConnection.ContentContext,
        isComplete: Bool,
        completion: NWConnection.SendCompletion
    )
    func start(queue: DispatchQueue)
    func cancel()
}

extension NWConnection: AndroidTunnelConnection {}

final class AndroidTunnel: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    private let closeAction: @Sendable () -> Void

    init(closeAction: @escaping @Sendable () -> Void) {
        self.closeAction = closeAction
    }

    deinit { close() }

    func close() {
        guard state.withLock({ closed in
            defer { closed = true }
            guard !closed else { return false }
            return true
        }) else { return }
        closeAction()
    }
}

final class ADBForwardLease: @unchecked Sendable {
    let port: UInt16

    private let state = OSAllocatedUnfairLock(initialState: false)
    private let releaseAction: @Sendable () -> Void

    init(port: UInt16, releaseAction: @escaping @Sendable () -> Void) {
        self.port = port
        self.releaseAction = releaseAction
    }

    deinit {
        release()
    }

    func release() {
        let shouldRelease = state.withLock { released in
            guard !released else { return false }
            released = true
            return true
        }
        if shouldRelease {
            releaseAction()
        }
    }
}

/// Echo-specific extensions to ADB
extension ADB {

    /// Returns ADB devices that expose echo-android's abstract unix domain socket.
    /// Device socket probes run concurrently and have independent deadlines so one
    /// unhealthy device cannot hide every healthy device.
    func echoEnabledDevices(
        deviceListTimeout: TimeInterval = 5,
        socketProbeTimeout: TimeInterval = 3
    ) async throws -> [Device] {
        let discoveredDevices = try await withTimeout(seconds: deviceListTimeout) {
            try await self.devices()
        }
        guard !discoveredDevices.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: ADBDeviceProbeResult.self) { group in
            for (index, device) in discoveredDevices.enumerated() {
                group.addTask {
                    do {
                        let (socket, connectionIdentifier) = try await withTimeout(seconds: socketProbeTimeout) {
                            let socket = try await self.findEchoServerUnixDomainSocket(for: device)
                            let connectionIdentifier: String? = if socket == "@echo-server" {
                                try await self.androidDeviceIdentifier(for: device)
                            } else {
                                nil
                            }
                            return (socket, connectionIdentifier)
                        }
                        return ADBDeviceProbeResult(
                            index: index,
                            device: device,
                            unixDomainSocket: socket,
                            connectionIdentifier: connectionIdentifier,
                            errorDescription: nil
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        let description = (error as? ADBError)?.completeErrorDescription
                            ?? error.localizedDescription
                        return ADBDeviceProbeResult(
                            index: index,
                            device: device,
                            unixDomainSocket: nil,
                            connectionIdentifier: nil,
                            errorDescription: "\(device.name): \(description)"
                        )
                    }
                }
            }

            var results: [ADBDeviceProbeResult] = []
            for try await result in group {
                results.append(result)
            }

            let failures = results.compactMap(\.errorDescription)
            let enabledDevices = results
                .sorted(by: { $0.index < $1.index })
                .compactMap { result -> Device? in
                    guard let socket = result.unixDomainSocket else { return nil }
                    var device = result.device
                    if socket.hasPrefix("@echo-server-") {
                        device.androidId = String(socket.trimmingPrefix("@echo-server-"))
                    }
                    device.connectionIdentifier = result.connectionIdentifier
                    return device
                }

            if enabledDevices.isEmpty, !failures.isEmpty {
                throw ADBError.adbDiscoveryFailed(
                    underlyingError: failures.joined(separator: "\n")
                )
            }
            if !failures.isEmpty {
                logger.warning(
                    "ADB discovery completed with \(failures.count, privacy: .public) device probe failure(s)"
                )
            }
            return enabledDevices
        }
    }

    func device(matchingBonjourServiceName serviceName: String) async throws -> Device? {
        let device = try await echoEnabledDevices().first(where: {
            $0.matchesBonjourAndroidServiceName(serviceName)
        })
        if let device {
            logger.info(
                "Matched Bonjour Android service \(serviceName, privacy: .public) to ADB device \(device.name, privacy: .public)"
            )
        } else {
            logger.info(
                "No ADB device matched Bonjour Android service \(serviceName, privacy: .public)"
            )
        }
        return device
    }

    /// Creates a dynamically allocated host port forward to an echo-android unix socket.
    func dynamicUnixSocketForward(for device: Device) async throws -> ADBForwardLease {
        try await createPortForward(
            for: device,
            remote: "localabstract:\(device.unixDomainSocket)"
        )
    }

    /// Creates a dynamically allocated host port forward to echo-android's TCP listener.
    func dynamicTCPForward(for device: Device) async throws -> ADBForwardLease {
        try await createPortForward(
            for: device,
            remote: "tcp:\(Self.emulatorPort)"
        )
    }

    func send(
        _ connectionRequest: ConnectionRequest,
        to device: Device,
        timeout: TimeInterval = 10,
        onRequestSent: @MainActor @Sendable () -> Void = {}
    ) async throws -> AndroidTunnel {
        let forwardLease = try await dynamicUnixSocketForward(for: device)
        let connection = NWConnection(
            host: .ipv4(.init(Self.emulatorHost)!),
            port: .init(rawValue: forwardLease.port)!,
            using: .tcp
        )

        do {
            try await send(connectionRequest, using: connection, timeout: timeout)
            await onRequestSent()
            return try await bridgeAndroidConnection(
                connection,
                toServerAt: connectionRequest.serverURL,
                timeout: timeout,
                forwardLease: forwardLease
            )
        } catch {
            connection.cancel()
            forwardLease.release()
            throw error
        }
    }

    /// Sends a request over the forwarded Android connection.
    /// - Parameter timeout: Values greater than zero bound the handshake; zero or negative values disable it.
    func send<Connection: AndroidTunnelConnection>(
        _ connectionRequest: ConnectionRequest,
        using connection: Connection,
        timeout: TimeInterval = 10,
        bridgeAndroidConnection: (@Sendable (Connection, URL) -> Void)? = nil
    ) async throws {
        let payload: Data = {
            var payload = try! JSONEncoder().encode(connectionRequest)
            payload.append(0x0A) // newline to allow readLine() on Android to return
            return payload
        }()
        let serverURL = connectionRequest.serverURL
        let operationState = ConnectionRequestOperationState<Void>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operationState.setContinuation(continuation)
                operationState.startTimeout(seconds: timeout) {
                    connection.cancel()
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(
                            content: payload,
                            contentContext: .defaultMessage,
                            isComplete: false,
                            completion: .contentProcessed { error in
                                if let error {
                                    connection.cancel()
                                    operationState.resume(.failure(error))
                                } else {
                                    operationState.resume(.success(())) {
                                        bridgeAndroidConnection?(connection, serverURL)
                                    }
                                }
                            }
                        )

                    case let .failed(error):
                        connection.cancel()
                        operationState.resume(.failure(error))

                    case .cancelled:
                        operationState.resume(.failure(CancellationError()))

                    case .setup, .waiting, .preparing:
                        break

                    @unknown default:
                        break
                    }
                }
                connection.start(queue: .init(label: "NWConnection.AndroidUDSTunnel", qos: .background))
            }
        } onCancel: {
            operationState.resume(.failure(CancellationError()))
            connection.cancel()
        }
    }

    // MARK: - Private Methods

    private func createPortForward(for device: Device, remote: String) async throws -> ADBForwardLease {
        let output = try await portForward(device: device, local: "tcp:0", remote: remote)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(output) else {
            throw ADBError.adbCommandFailed(
                command: "-s \(device.name) forward tcp:0 \(remote)",
                underlyingError: "adb returned an invalid dynamic port: \(output)"
            )
        }

        logger.info(
            "Created adb forward for \(device.name, privacy: .public) on local port \(port, privacy: .public)"
        )
        return ADBForwardLease(port: port) { [self] in
            Task {
                do {
                    try await execute(
                        "-s",
                        device.name,
                        "forward",
                        "--remove",
                        "tcp:\(port)"
                    )
                    logger.info(
                        "Removed adb forward for \(device.name, privacy: .public) on port \(port, privacy: .public)"
                    )
                } catch {
                    logger.error(
                        "Failed to remove adb forward for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private func findEchoServerUnixDomainSocket(for device: Device) async throws -> String? {
        try await findUnixDomainSockets(for: device).first(where: { $0.hasPrefix("@echo-server") })
    }
    
    private func bridgeAndroidConnection(
        _ androidConnection: NWConnection,
        toServerAt serverURL: URL,
        timeout: TimeInterval,
        forwardLease: ADBForwardLease
    ) async throws -> AndroidTunnel {
        guard let host = serverURL.host,
              let rawPort = serverURL.port,
              let port = NWEndpoint.Port(rawValue: UInt16(rawPort)) else {
            throw URLError(.badURL)
        }

        let localWebSocketConnection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )
        let operationState = ConnectionRequestOperationState<AndroidTunnel>()
        let tunnel = AndroidTunnel {
            androidConnection.cancel()
            localWebSocketConnection.cancel()
            forwardLease.release()
        }

        func closeConnections(reason: String) {
            logger.info("Closing Android bridge: \(reason, privacy: .public)")
            tunnel.close()
        }

        func pipe(from: NWConnection, to: NWConnection) {
            from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    to.send(content: data, completion: .contentProcessed { sendError in
                        if let sendError {
                            closeConnections(reason: "pipe send failed: \(sendError.localizedDescription)")
                        } else {
                            pipe(from: from, to: to)
                        }
                    })
                } else if let error {
                    closeConnections(reason: "pipe receive failed: \(error.localizedDescription)")
                } else if isComplete {
                    closeConnections(reason: "pipe completed")
                } else {
                    pipe(from: from, to: to)
                }
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operationState.setContinuation(continuation)
                operationState.startTimeout(seconds: timeout) {
                    closeConnections(reason: "bridge readiness timed out")
                }

                localWebSocketConnection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        operationState.resume(.success(tunnel)) {
                            self.logger.info("Android local WebSocket bridge is ready")
                            pipe(from: androidConnection, to: localWebSocketConnection)
                            pipe(from: localWebSocketConnection, to: androidConnection)
                        }

                    case let .failed(error):
                        operationState.resume(.failure(error))
                        closeConnections(reason: "local WebSocket failed: \(error.localizedDescription)")

                    case .cancelled:
                        operationState.resume(.failure(CancellationError()))
                        closeConnections(reason: "local WebSocket cancelled")

                    case .setup, .preparing, .waiting:
                        break

                    @unknown default:
                        break
                    }
                }
                localWebSocketConnection.start(
                    queue: .init(label: "NWConnection.AndroidLocalServerBridge", qos: .background)
                )
            }
        } onCancel: {
            operationState.resume(.failure(CancellationError()))
            closeConnections(reason: "bridge task cancelled")
        }
    }
}

private struct ADBDeviceProbeResult: Sendable {
    let index: Int
    let device: ADB.Device
    let unixDomainSocket: String?
    let connectionIdentifier: String?
    let errorDescription: String?
}

final class ConnectionRequestOperationState<Value: Sendable>: @unchecked Sendable {
    private struct State {
        var didResume = false
        var continuation: CheckedContinuation<Value, Error>?
        var timeoutTask: Task<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setContinuation(_ continuation: CheckedContinuation<Value, Error>) {
        let shouldResumeImmediately = state.withLock { state in
            guard !state.didResume else { return true }
            state.continuation = continuation
            return false
        }
        if shouldResumeImmediately {
            continuation.resume(throwing: CancellationError())
        }
    }

    func startTimeout(seconds: TimeInterval, onTimeout: @escaping @Sendable () -> Void) {
        guard seconds > 0 else { return }
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                return
            }
            resume(.failure(ConnectionRequestTimeoutError(seconds: seconds))) {
                onTimeout()
            }
        }

        let shouldCancel = state.withLock { state in
            guard !state.didResume else { return true }
            state.timeoutTask = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    @discardableResult
    func resume(
        _ result: Result<Value, Error>,
        onWin: () -> Void = {}
    ) -> Bool {
        let (didResume, continuation, timeoutTask) = state.withLock { state in
            guard !state.didResume else {
                return (
                    false,
                    nil as CheckedContinuation<Value, Error>?,
                    nil as Task<Void, Never>?
                )
            }
            state.didResume = true
            let continuation = state.continuation
            let timeoutTask = state.timeoutTask
            state.continuation = nil
            state.timeoutTask = nil
            return (true, continuation, timeoutTask)
        }

        timeoutTask?.cancel()
        guard didResume else { return false }
        onWin()
        continuation?.resume(with: result)
        return didResume
    }
}

extension ADB.Device {

    func matchesBonjourAndroidServiceName(_ serviceName: String) -> Bool {
        name.caseInsensitiveCompare(serviceName) == .orderedSame
        || androidId?.caseInsensitiveCompare(serviceName) == .orderedSame
        || connectionIdentifier?.caseInsensitiveCompare(serviceName) == .orderedSame
    }
}
