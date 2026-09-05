import EchoConnection
import Foundation
import Network
import os

/// Represents a Bonjour service discovered on the local network.
struct BonjourService: Equatable {
    private static let logger = Logger.echoLogger(category: "BonjourService")
    var endpoint: NWEndpoint
    var name: String
    var displayName: String?
    var adbProvider: () -> ADB?
}

// MARK: -

extension BonjourService {

    var isAndroidEmulator: Bool {
        // Network.framework resolves native Bonjour clients as service endpoints.
        // echo-android's emulator advertisement arrives as a host/port endpoint.
        if case .hostPort = endpoint { return true }
        return false
    }

    func send(
        _ connectionRequest: ConnectionRequest,
        timeout: TimeInterval = 10,
        onRequestSent: @MainActor @Sendable () -> Void = {},
        onResolvedDeviceIdentifier: @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> AndroidTunnel? {
        if isAndroidEmulator, let adb = adbProvider() {
            Self.logger.info(
                "Resolving the ADB device for Android emulator \(name, privacy: .public)"
            )
            let matchingDevice: ADB.Device?
            do {
                matchingDevice = try await adb.device(matchingBonjourServiceName: name)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.logger.warning(
                    "Unable to resolve Android service by identity; checking the legacy single-device path: \(error.localizedDescription, privacy: .public)"
                )
                matchingDevice = nil
            }

            if let matchingDevice {
                // Once a specific device is selected, failures must propagate. Falling back after
                // sending could deliver the same connection request more than once.
                await onResolvedDeviceIdentifier(matchingDevice.androidIdOrName)
                return try await adb.send(
                    connectionRequest,
                    to: matchingDevice,
                    timeout: timeout,
                    onRequestSent: onRequestSent
                )
            }

            // Older echo-android clients may not expose the identity-bearing unix
            // socket. Retain compatibility only when the target is unambiguous.
            let devices = try await adb.devices()
            guard devices.count == 1, let device = devices.first else {
                let reason = devices.isEmpty
                    ? "No ADB devices are connected."
                    : "Unable to match Bonjour service '\(name)' to one of \(devices.count) ADB devices. Disconnect other emulators and retry."
                throw ADBError.adbDiscoveryFailed(
                    underlyingError: reason
                )
            }

            await onResolvedDeviceIdentifier(name)
            let forwardLease = try await adb.dynamicTCPForward(for: device)
            defer { forwardLease.release() }
            let forwardedEndpoint = NWEndpoint.hostPort(
                host: .init(ADB.emulatorHost),
                port: .init(rawValue: forwardLease.port)!
            )
            try await send(connectionRequest, to: forwardedEndpoint, timeout: timeout)
            await onRequestSent()
            return nil
        }

        await onResolvedDeviceIdentifier(name)
        try await send(connectionRequest, to: endpoint, timeout: timeout)
        await onRequestSent()
        return nil
    }

    private func send(
        _ connectionRequest: ConnectionRequest,
        to targetEndpoint: NWEndpoint,
        timeout: TimeInterval
    ) async throws {
        let connection = NWConnection(to: targetEndpoint, using: .tcp)
        let sendState = ConnectionRequestOperationState<Void>()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sendState.setContinuation(continuation)

                sendState.startTimeout(seconds: timeout) {
                    connection.cancel()
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let encodedRequest = try! JSONEncoder().encode(connectionRequest)
                        connection.send(
                            content: encodedRequest,
                            contentContext: .defaultMessage,
                            isComplete: true,
                            completion: .contentProcessed({ error in
                                connection.cancel()
                                sendState.resume(error.map(Result.failure) ?? .success(()))
                            })
                        )

                    case let .failed(error):
                        connection.cancel()
                        sendState.resume(.failure(error))

                    case .cancelled:
                        sendState.resume(.failure(CancellationError()))

                    case .setup, .waiting, .preparing:
                        break

                    @unknown default:
                        break
                    }
                }
                connection.start(queue: .init(label: "NWConnection.sendEchoConnectionRequest", qos: .background))
            }
        } onCancel: {
            sendState.resume(.failure(CancellationError()))
            connection.cancel()
        }
    }
}

// MARK: -

extension BonjourService {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.endpoint == rhs.endpoint
        && lhs.name == rhs.name
    }
}
