import Combine
import Foundation

public struct PluginConnection {
    private let _send: (PluginMessage) -> Void

    /// Retained for ABI compatibility with plugins. Prefer ``incomingPluginMessages``
    public let incomingMessages: AnyPublisher<Data, Never>
    public let incomingPluginMessages: AnyPublisher<PluginMessage, Never>

    public init(
        incomingMessages: AnyPublisher<PluginMessage, Never>,
        send: @escaping (PluginMessage) -> Void
    ) {
        self.incomingPluginMessages = incomingMessages
        self.incomingMessages = incomingPluginMessages.map(\.data).eraseToAnyPublisher()
        self._send = send
    }

    /// Send opaque data over the connection
    public func send(_ outgoingMessage: PluginMessage) {
        _send(outgoingMessage)
    }
}

// MARK: -

extension PluginConnection {

    /// Convenience to send raw `Data` with no `command` set
    public func send(_ data: Data) {
        send(PluginMessage(command: nil, data: data))
    }

    /// Convenience method to send a `Codable` object
    public func send<T: Codable>(_ codable: T) throws {
        let encoded = try encoder.encode(codable)
        send(encoded)
    }

    /// Convenience method to send a `Codable` object with the given command
    public func send<T: Codable>(_ codable: T, command: String) throws {
        let encoded = try encoder.encode(codable)
        send(PluginMessage(command: command, data: encoded))
    }

    /// Convenience method to send an ``Event``
    public func sendEvent(name: String, metadata: [String: String], id: String = UUID().uuidString) {
        try! send(Event(id: id, name: name, metadata: metadata))
    }

    /// Convenience method to receive all ``Event``s sent over the connection
    public func receiveEvents() -> AnyPublisher<Event, Never> {
        receive(Event.self)
    }

    /// Convenience method to send an ``EchoTableRow``
    public func sendEchoTableRow(columnItems: [String: String], id: String = UUID().uuidString) {
        try! send(EchoTableRow(id: id, columnItems: columnItems))
    }

    /// Convenience method to receive all ``EchoTableRow``s sent over the connection
    public func receiveEchoTableRows() -> AnyPublisher<EchoTableRow, Never> {
        receive(EchoTableRow.self)
    }

    /// Convenience method to receive all events that can be decoded to `T`
    public func receive<T: Codable>(_ type: T.Type) -> AnyPublisher<T, Never> {
        return incomingMessages
            .decode(type: type, decoder: decoder)
            .catch { error in
                Empty()
            }
            .eraseToAnyPublisher()
    }

    /// Convenience method to receive all events that can be decoded to `T` when `command` matches
    /// the given value
    public func receive<T: Codable>(_ type: T.Type, command: String) -> AnyPublisher<T, Never> {
        return incomingPluginMessages
            .filter { $0.command == command }
            .map { $0.data }
            .decode(type: type, decoder: decoder)
            .catch { error in
                Empty()
            }
            .eraseToAnyPublisher()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()

        // Encode dates as unix timestamps in milliseconds
        // We're not using the built-in `millisecondsSince1970`
        // strategy since it encodes with milliseconds after the decimal point.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let timestamp = Int(date.timeIntervalSince1970 * 1_000)
            try container.encode(timestamp)
        }
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

}
