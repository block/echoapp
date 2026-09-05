import Combine
import Foundation
import os

import EchoConnection

// MARK: - RecordedPayloadLine

private struct RecordedPayloadLine: Codable {
    let plugin_id: String
    let data: AnyCodable
    let command: String?
    let timestamp: String?

    func toPluginPayload() -> PluginPayload? {
        guard let jsonData = data.toJSONData() else { return nil }
        return PluginPayload(pluginID: plugin_id, data: jsonData, command: command)
    }
}

/// Type-erased Codable wrapper that preserves the original JSON structure.
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        fatalError("AnyCodable encoding is not supported")
    }

    func toJSONData() -> Data? {
        if JSONSerialization.isValidJSONObject(value) {
            return try? JSONSerialization.data(withJSONObject: value)
        }
        if JSONSerialization.isValidJSONObject(["value": value]) {
            return try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        if value is NSNull {
            return try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        return nil
    }
}

// MARK: - RecordedPayloadLoader

private enum RecordedPayloadLoader {
    static func jsonlFiles(in sessionDirectoryURL: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func decodePayload(from lineData: Data) -> PluginPayload? {
        let decoder = JSONDecoder()
        if let recorded = try? decoder.decode(RecordedPayloadLine.self, from: lineData) {
            return recorded.toPluginPayload()
        }
        return nil
    }

    static func loadExistingPayloads(
        in sessionDirectoryURL: URL,
        fileOffsets: inout [String: UInt64]
    ) -> [PluginPayload] {
        var payloads: [PluginPayload] = []
        for fileURL in jsonlFiles(in: sessionDirectoryURL) {
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let key = fileURL.lastPathComponent
            fileOffsets[key] = UInt64(data.count)

            let lines = data.split(separator: UInt8(ascii: "\n"))
            for line in lines {
                if let payload = decodePayload(from: Data(line)) {
                    payloads.append(payload)
                }
            }
        }
        return payloads
    }

    static func loadNewPayloads(
        from fileURL: URL,
        startingAt currentOffset: UInt64
    ) -> (payloads: [PluginPayload], offset: UInt64)? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()

        if fileSize < currentOffset {
            fileHandle.seek(toFileOffset: 0)
        } else if fileSize == currentOffset {
            return nil
        } else {
            fileHandle.seek(toFileOffset: currentOffset)
        }

        let newData = fileHandle.readDataToEndOfFile()
        guard !newData.isEmpty else { return nil }

        let lines = newData.split(separator: UInt8(ascii: "\n"))
        let payloads = lines.compactMap { decodePayload(from: Data($0)) }
        return (payloads, fileHandle.offsetInFile)
    }
}

// MARK: - FileBackedConnection

final class FileBackedConnection: ClientServerConnection {

    // MARK: - Private Properties

    private let logger = Logger.echoLogger(category: "FileBackedConnection")
    private let sessionDirectoryURL: URL
    private let payloadsSubject = PassthroughSubject<PluginPayload, Error>()
    private let queue = DispatchQueue(label: "echo.file-backed-connection", qos: .utility)
    private let payloadEventQueue = DispatchQueue(label: "echo.file-backed-connection.payloads")
    private let connectedClientRegistry: ConnectedClientRegistry
    private let finishLock = NSLock()
    private var fileOffsets: [String: UInt64]
    private var pollingTask: Task<Void, Never>?
    private var hasFinished = false

    // MARK: - Public Properties

    let id = UUID()

    var connectedClientUpdates: AsyncStream<ConnectedClient> {
        connectedClientRegistry.stream
    }

    var currentConnectedClient: ConnectedClient {
        connectedClientRegistry.current
    }

    let incomingPluginPayloads: AnyPublisher<PluginPayload, Error>

    // MARK: - Life Cycle

    init(sessionDirectoryURL: URL, deviceName: String) {
        self.sessionDirectoryURL = sessionDirectoryURL
        self.connectedClientRegistry = ConnectedClientRegistry(initialValue: ConnectedClient(
            deviceIdentifier: DeviceIdentifier(value: "file-backed-\(deviceName)"),
            deviceName: deviceName,
            appIdentifier: "echoapp"
        ))

        var initialOffsets: [String: UInt64] = [:]
        let existingPayloads = RecordedPayloadLoader.loadExistingPayloads(
            in: sessionDirectoryURL,
            fileOffsets: &initialOffsets
        )
        self.fileOffsets = initialOffsets
        self.incomingPluginPayloads = Publishers.Merge(
            existingPayloads.publisher.setFailureType(to: Error.self),
            payloadsSubject
        )
            .eraseToAnyPublisher()

        startPolling()
    }

    deinit {
        pollingTask?.cancel()
        finish()
    }

    // MARK: - Public Methods

    func send(_ payload: PluginPayload) throws {
        // No-op: file-backed connections are read-only
    }

    func close() async {
        pollingTask?.cancel()
        pollingTask = nil
        finish()
    }

    // MARK: - Private Methods

    private func jsonlFiles() -> [URL] {
        RecordedPayloadLoader.jsonlFiles(in: sessionDirectoryURL)
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.pollForNewData()
            }
        }
    }

    private func pollForNewData() {
        queue.sync { [weak self] in
            guard let self else { return }
            for fileURL in self.jsonlFiles() {
                let key = fileURL.lastPathComponent
                let currentOffset = self.fileOffsets[key] ?? 0

                if let result = RecordedPayloadLoader.loadNewPayloads(from: fileURL, startingAt: currentOffset) {
                    self.fileOffsets[key] = result.offset
                    result.payloads.forEach { self.sendIncomingPayload($0) }
                }
            }
        }
    }

    func finish() {
        finishLock.lock()
        guard !hasFinished else {
            finishLock.unlock()
            return
        }
        hasFinished = true
        payloadEventQueue.async { [payloadsSubject] in
            payloadsSubject.send(completion: .finished)
        }
        finishLock.unlock()
    }

    private func sendIncomingPayload(_ payload: PluginPayload) {
        finishLock.lock()
        guard !hasFinished else {
            finishLock.unlock()
            return
        }

        payloadEventQueue.async { [payloadsSubject] in
            payloadsSubject.send(payload)
        }
        finishLock.unlock()
    }
}

// MARK: - FileBackedServer

final class FileBackedServer: Server {

    // MARK: - Private Properties

    private let logger = Logger.echoLogger(category: "FileBackedServer")
    private let sessionDirectoryURL: URL
    private let deviceName: String
    private let connectionRegistry = ConnectionRegistry()

    // MARK: - Public Properties

    var connectionUpdates: AsyncStream<(any ClientServerConnection)?> {
        connectionRegistry.stream
    }

    var currentConnection: (any ClientServerConnection)? {
        connectionRegistry.current
    }

    var webSocketURL: URL {
        URL(string: "file://localhost/echoapp")!
    }

    // MARK: - Life Cycle

    init(sessionDirectoryURL: URL, deviceName: String) {
        self.sessionDirectoryURL = sessionDirectoryURL
        self.deviceName = deviceName
    }

    // MARK: - Public Methods

    func start() throws {
        guard FileManager.default.fileExists(atPath: self.sessionDirectoryURL.path) else {
            logger.error("Session directory not found at \(self.sessionDirectoryURL.path)")
            throw FileBackedServerError.sessionDirectoryNotFound(self.sessionDirectoryURL)
        }

        let fileBackedConnection = FileBackedConnection(
            sessionDirectoryURL: self.sessionDirectoryURL,
            deviceName: self.deviceName
        )
        if let previousConnection = connectionRegistry.activate(fileBackedConnection) {
            Task { await previousConnection.close() }
        }
        logger.info("Started file-backed server from \(self.sessionDirectoryURL.path)")
    }

    func closeCurrentConnection() async {
        guard let connection = connectionRegistry.clearActiveConnection() else { return }
        await connection.close()
    }

    func expectConnection(identifier: String?) {}
    func beginExpectingConnection() {}
}

// MARK: - FileBackedServerError

enum FileBackedServerError: Error {
    case sessionDirectoryNotFound(URL)
}
