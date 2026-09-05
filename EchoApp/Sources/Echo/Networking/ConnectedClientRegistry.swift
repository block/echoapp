import Foundation

import EchoConnection

/// Owns the latest client metadata for a single connection and replays updates
/// to each observer.
final class ConnectedClientRegistry: @unchecked Sendable {

    // MARK: - Private Properties

    private let lock = NSLock()
    private let eventQueue = DispatchQueue(label: "echo.connected-client-registry.events")
    private var currentValue: ConnectedClient
    private var continuations: [UUID: AsyncStream<ConnectedClient>.Continuation] = [:]

    // MARK: - Life Cycle

    init(initialValue: ConnectedClient) {
        currentValue = initialValue
    }

    deinit {
        lock.lock()
        let currentContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        currentContinuations.forEach { $0.finish() }
    }

    // MARK: - Public Properties

    var current: ConnectedClient {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    var stream: AsyncStream<ConnectedClient> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let currentClient = currentValue
            eventQueue.async {
                continuation.yield(currentClient)
            }
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    // MARK: - Public Methods

    func update(_ connectedClient: ConnectedClient) {
        lock.lock()
        currentValue = connectedClient
        let currentContinuations = Array(continuations.values)
        emit(connectedClient, to: currentContinuations)
        lock.unlock()
    }

    // MARK: - Private Methods

    private func emit(
        _ connectedClient: ConnectedClient,
        to continuations: [AsyncStream<ConnectedClient>.Continuation]
    ) {
        eventQueue.async {
            continuations.forEach { $0.yield(connectedClient) }
        }
    }
}
