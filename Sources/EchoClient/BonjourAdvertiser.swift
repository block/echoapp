import Foundation
import Network
import EchoConnection

public protocol BonjourAdvertiser {
    /// Starts advertising and waits for data to be received.
    func receiveConnectionData() async throws -> Data
}

public final class RealBonjourAdvertiser: BonjourAdvertiser {
    private let clientIdentifier: String
    private let bundleId: String
    private let serviceName: String
    private let serviceType: String

    public init(
        clientIdentifier: String,
        bundleId: String? = nil,
        serviceName: String = DeviceIdentifier.current.value,
        serviceType: String
    ) {
        self.clientIdentifier = clientIdentifier
        self.bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        self.serviceName = serviceName
        self.serviceType = serviceType
    }

    public func receiveConnectionData() async throws -> Data {
        try await receiveConnection().receiveData()
    }

    /// Start advertising and wait for a connection.
    /// Note: advertising stops after a connection is created.
    private func receiveConnection() async throws -> NWConnection {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2 // TODO: - do we need these options?

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = true // TODO: - do we need this?

        let listener: NWListener
        do {
            let txtRecord = NWTXTRecord(
                [
                    "device_name": serviceName,
                    "app_identifier": clientIdentifier,
                    "bundle_id": bundleId,
                ]
            )
            listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: serviceName, type: serviceType, txtRecord: txtRecord)
        } catch {
            fatalError("Failed to construct NWListener. Reason: \(error)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [unowned listener] newState in
                guard case let .failed(error) = newState else { return }
                listener.cancel()
                continuation.resume(throwing: error)
            }
            listener.newConnectionLimit = 1
            listener.newConnectionHandler = { [unowned listener] connection in
                listener.cancel()
                continuation.resume(returning: connection)
            }
            listener.start(queue: .main)
        }
    }
}

extension NWConnection {

    func receiveData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            self.stateUpdateHandler = { [unowned self] state in
                guard case let .failed(error) = state else { return }
                self.cancel()
                continuation.resume(throwing: error)
            }

            // TODO: - receive complete instead
            self.receive(
                minimumIncompleteLength: 1,
                maximumLength: 100) { [unowned self] data, contentContext, isComplete, error in
                    print("NWConnection received data: \(String(describing: data))")
                    guard let data else { return }
                    self.cancel()
                    continuation.resume(returning: data)
                }
            self.start(queue: .main)
        }
    }

}
