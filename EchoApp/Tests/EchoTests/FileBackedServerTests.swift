@testable import Echo

import Combine
import EchoConnection
import XCTest

final class FileBackedServerTests: XCTestCase {

    private var tempDir: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBackedServerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_incomingPluginPayloads_replaysExistingPayloadsWhenSubscriberAttaches() throws {
        try writeJSONL(
            plugin: "network",
            lines: [
                ["plugin_id": "network", "data": ["url": "https://example.com"]],
            ]
        )

        let connection = FileBackedConnection(sessionDirectoryURL: tempDir, deviceName: "iPhone")
        let received = expectation(description: "received existing payload")

        var payloads: [PluginPayload] = []
        connection.incomingPluginPayloads
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected failure: \(error)")
                    }
                },
                receiveValue: { payload in
                    payloads.append(payload)
                    received.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [received], timeout: 1)
        XCTAssertEqual(payloads.map(\.pluginID), ["network"])

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payloads[0].data) as? [String: Any])
        XCTAssertEqual(object["url"] as? String, "https://example.com")
    }

    func test_incomingPluginPayloads_replaysScalarJSONFragments() throws {
        try writeJSONL(
            plugin: "logging",
            lines: [
                ["plugin_id": "logging", "data": "plain text"],
                ["plugin_id": "logging", "data": 42],
                ["plugin_id": "logging", "data": true],
            ]
        )

        let connection = FileBackedConnection(sessionDirectoryURL: tempDir, deviceName: "iPhone")
        let received = expectation(description: "received scalar payloads")
        received.expectedFulfillmentCount = 3

        var payloads: [PluginPayload] = []
        connection.incomingPluginPayloads
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Unexpected failure: \(error)")
                    }
                },
                receiveValue: { payload in
                    payloads.append(payload)
                    received.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [received], timeout: 1)
        XCTAssertEqual(payloads.count, 3)

        let decodedValues = try payloads.map {
            try JSONSerialization.jsonObject(with: $0.data, options: [.fragmentsAllowed])
        }
        XCTAssertEqual(decodedValues[0] as? String, "plain text")
        XCTAssertEqual(decodedValues[1] as? Int, 42)
        XCTAssertEqual(decodedValues[2] as? Bool, true)
    }

    private func writeJSONL(plugin: String, lines: [[String: Any]]) throws {
        let fileURL = tempDir.appendingPathComponent("\(plugin).jsonl")
        var data = Data()

        for line in lines {
            data.append(try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]))
            data.append(contentsOf: "\n".utf8)
        }

        try data.write(to: fileURL)
    }
}
