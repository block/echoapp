import Foundation

/// Owns the active client connection and broadcasts replaying state changes.
///
/// Vapor/NIO invokes WebSocket callbacks off the main actor. This registry is
/// the single synchronization point between those callbacks and the UI/session
/// layer.
final class ConnectionRegistry: @unchecked Sendable {

    private enum Admission {
        case anyIdentifier
        case awaitingIdentifier
        case identifier(String)
    }

    // MARK: - Private Properties

    private let lock = NSLock()
    private let eventQueue = DispatchQueue(label: "echo.connection-registry.events")
    private var currentValue: (any ClientServerConnection)?
    private var admission = Admission.anyIdentifier
    private var continuations: [UUID: AsyncStream<(any ClientServerConnection)?>.Continuation] = [:]

    // MARK: - Life Cycle

    deinit {
        lock.lock()
        let currentContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        currentContinuations.forEach { $0.finish() }
    }

    // MARK: - Public Properties

    var current: (any ClientServerConnection)? {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    var stream: AsyncStream<(any ClientServerConnection)?> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let currentConnection = currentValue
            eventQueue.async {
                continuation.yield(currentConnection)
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

    func beginExpectingConnection() {
        lock.withLock {
            admission = .awaitingIdentifier
        }
    }

    func expectConnection(identifier: String?) {
        lock.withLock {
            admission = identifier.map(Admission.identifier) ?? .anyIdentifier
        }
    }

    func acceptsConnection(identifier: String) -> Bool {
        lock.withLock {
            switch admission {
            case .anyIdentifier:
                true
            case .awaitingIdentifier:
                false
            case let .identifier(expectedIdentifier):
                expectedIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
            }
        }
    }

    @discardableResult
    func activate(_ connection: any ClientServerConnection) -> (any ClientServerConnection)? {
        lock.lock()
        let previousConnection = currentValue
        currentValue = connection
        let currentContinuations = Array(continuations.values)
        var events: [(any ClientServerConnection)?] = []
        if previousConnection != nil {
            events.append(nil)
        }
        events.append(connection)
        emit(events, to: currentContinuations)
        lock.unlock()

        return previousConnection
    }

    @discardableResult
    func clearActiveConnection() -> (any ClientServerConnection)? {
        lock.lock()
        let previousConnection = currentValue
        currentValue = nil
        let currentContinuations = Array(continuations.values)
        if previousConnection != nil {
            emit([nil], to: currentContinuations)
        }
        lock.unlock()

        return previousConnection
    }

    @discardableResult
    func clearIfActive(connectionID: UUID) -> (any ClientServerConnection)? {
        lock.lock()
        guard currentValue?.id == connectionID else {
            lock.unlock()
            return nil
        }

        let previousConnection = currentValue
        currentValue = nil
        let currentContinuations = Array(continuations.values)
        emit([nil], to: currentContinuations)
        lock.unlock()

        return previousConnection
    }

    // MARK: - Private Methods

    private func emit(
        _ events: [(any ClientServerConnection)?],
        to continuations: [AsyncStream<(any ClientServerConnection)?>.Continuation]
    ) {
        eventQueue.async {
            for event in events {
                continuations.forEach { $0.yield(event) }
            }
        }
    }
}
