@testable import Echo

import EchoConnection
import XCTest

final class SessionFileCacheTests: XCTestCase {

    private var tempDir: URL!
    private var cache: SessionFileCache!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionFileCacheTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = SessionFileCache(baseURL: tempDir, maxSessions: 3)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Session Lifecycle

    func test_startSession_createsDirectoryAndMetadata() async throws {
        let sessionID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let sessionDir = tempDir.appendingPathComponent(sessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.path))

        let metadataURL = sessionDir.appendingPathComponent("session.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))

        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(SessionFileCache.SessionMetadata.self, from: data)
        XCTAssertEqual(metadata.deviceName, "iPhone 15")
        XCTAssertEqual(metadata.deviceType, "ios")
        XCTAssertNil(metadata.endedAt)
        XCTAssertEqual(metadata.plugins, [])
    }

    func test_startSession_createsCurrentSymlink() async throws {
        let sessionID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let symlinkURL = tempDir.appendingPathComponent("current")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlinkURL.path)
        XCTAssertTrue(destination.contains(sessionID))
    }

    func test_startSession_sanitizesDeviceName() async throws {
        let sessionID = try await cache.startSession(deviceName: "My Device/Pro", deviceType: "ios")

        XCTAssertTrue(sessionID.contains("My-Device-Pro"))
        XCTAssertFalse(sessionID.contains(" "))
        XCTAssertFalse(sessionID.contains("/"))
    }

    func test_endSession_updatesMetadataWithEndedAtAndPlugins() async throws {
        let sessionID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let payload = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: ["url": "https://example.com"])
        )
        try await cache.append(payload: payload)
        try await cache.endSession()

        let metadataURL = tempDir.appendingPathComponent(sessionID).appendingPathComponent("session.json")
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(SessionFileCache.SessionMetadata.self, from: data)
        XCTAssertNotNil(metadata.endedAt)
        XCTAssertEqual(metadata.plugins, ["network"])
    }

    func test_endSession_removesCurrentSymlink() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")
        try await cache.endSession()

        let symlinkURL = tempDir.appendingPathComponent("current")
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkURL.path))
    }

    func test_startSession_closesExistingSession() async throws {
        let firstID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")
        let secondID = try await cache.startSession(deviceName: "Pixel 8", deviceType: "android")

        XCTAssertNotEqual(firstID, secondID)

        // First session should have endedAt set
        let firstMetadataURL = tempDir.appendingPathComponent(firstID).appendingPathComponent("session.json")
        let data = try Data(contentsOf: firstMetadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(SessionFileCache.SessionMetadata.self, from: data)
        XCTAssertNotNil(metadata.endedAt)

        // Current symlink should point to second session
        let destination = try FileManager.default.destinationOfSymbolicLink(
            atPath: tempDir.appendingPathComponent("current").path
        )
        XCTAssertTrue(destination.contains(secondID))
    }

    // MARK: - Writing & Reading Payloads

    func test_append_writesJSONLToCorrectFile() async throws {
        let sessionID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let payload = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: [
                "url": "https://api.example.com/v1/users",
                "method": "POST",
                "status_code": 200,
            ])
        )
        try await cache.append(payload: payload)

        let fileURL = tempDir
            .appendingPathComponent(sessionID)
            .appendingPathComponent("network.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)

        let parsed = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        XCTAssertNotNil(parsed["timestamp"])
        XCTAssertEqual(parsed["plugin_id"] as? String, "network")

        let data = parsed["data"] as! [String: Any]
        XCTAssertEqual(data["url"] as? String, "https://api.example.com/v1/users")
        XCTAssertEqual(data["method"] as? String, "POST")
        XCTAssertEqual(data["status_code"] as? Int, 200)
    }

    func test_append_multiplePayloadsAppendToSameFile() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        for i in 0..<5 {
            let payload = PluginPayload(
                pluginID: "com.echo.plugin.network",
                data: try JSONSerialization.data(withJSONObject: ["request_number": i])
            )
            try await cache.append(payload: payload)
        }

        let lines = try await cache.readLines(plugin: "com.echo.plugin.network")
        XCTAssertEqual(lines.count, 5)

        // Verify each line is valid JSON
        for (i, line) in lines.enumerated() {
            let parsed = try JSONSerialization.jsonObject(with: line) as! [String: Any]
            let data = parsed["data"] as! [String: Any]
            XCTAssertEqual(data["request_number"] as? Int, i)
        }
    }

    func test_append_differentPluginsWriteToDifferentFiles() async throws {
        let sessionID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let networkPayload = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: ["url": "https://example.com"])
        )
        let analyticsPayload = PluginPayload(
            pluginID: "com.echo.plugin.analytics",
            data: try JSONSerialization.data(withJSONObject: ["event": "screen_view"])
        )
        try await cache.append(payload: networkPayload)
        try await cache.append(payload: analyticsPayload)

        let sessionDir = tempDir.appendingPathComponent(sessionID)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionDir.appendingPathComponent("network.jsonl").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionDir.appendingPathComponent("analytics.jsonl").path
        ))

        let networkLines = try await cache.readLines(plugin: "com.echo.plugin.network")
        let analyticsLines = try await cache.readLines(plugin: "com.echo.plugin.analytics")
        XCTAssertEqual(networkLines.count, 1)
        XCTAssertEqual(analyticsLines.count, 1)
    }

    func test_append_preservesCommandField() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let payload = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: ["url": "https://example.com"]),
            command: "response_received"
        )
        try await cache.append(payload: payload)

        let lines = try await cache.readLines(plugin: "com.echo.plugin.network")
        let parsed = try JSONSerialization.jsonObject(with: lines[0]) as! [String: Any]
        XCTAssertEqual(parsed["command"] as? String, "response_received")
    }

    func test_append_handlesNonJSONData() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let payload = PluginPayload(
            pluginID: "com.echo.plugin.logging",
            data: "plain text log message".data(using: .utf8)!
        )
        try await cache.append(payload: payload)

        let lines = try await cache.readLines(plugin: "com.echo.plugin.logging")
        XCTAssertEqual(lines.count, 1)

        let parsed = try JSONSerialization.jsonObject(with: lines[0]) as! [String: Any]
        XCTAssertEqual(parsed["data"] as? String, "plain text log message")
    }

    func test_append_withNoActiveSession_doesNothing() async throws {
        let payload = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: ["url": "https://example.com"])
        )
        try await cache.append(payload: payload)

        // No crash, no files written
        let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents?.isEmpty ?? true)
    }

    // MARK: - Reading Data

    func test_readLines_returnsEmptyForUnknownPlugin() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")

        let lines = try await cache.readLines(plugin: "com.echo.plugin.nonexistent")
        XCTAssertTrue(lines.isEmpty)
    }

    func test_readLines_fromSpecificSession() async throws {
        let firstID = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")
        let payload1 = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: ["session": "first"])
        )
        try await cache.append(payload: payload1)

        _ = try await cache.startSession(deviceName: "Pixel 8", deviceType: "android")
        let payload2 = PluginPayload(
            pluginID: "com.echo.plugin.network",
            data: try JSONSerialization.data(withJSONObject: ["session": "second"])
        )
        try await cache.append(payload: payload2)

        // Read from the first session explicitly
        let firstSessionLines = try await cache.readLines(plugin: "com.echo.plugin.network", sessionID: firstID)
        XCTAssertEqual(firstSessionLines.count, 1)
        let parsed = try JSONSerialization.jsonObject(with: firstSessionLines[0]) as! [String: Any]
        let data = parsed["data"] as! [String: Any]
        XCTAssertEqual(data["session"] as? String, "first")
    }

    // MARK: - Session Listing

    func test_listSessions_returnsSortedNewestFirst() async throws {
        _ = try await cache.startSession(deviceName: "Device-A", deviceType: "ios")
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1s to get different timestamps
        _ = try await cache.startSession(deviceName: "Device-B", deviceType: "android")

        let sessions = await cache.listSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions[0].startedAt >= sessions[1].startedAt)
        XCTAssertTrue(sessions[0].deviceName == "Device-B")
    }

    func test_listSessions_returnsEmptyWhenNoSessions() async {
        let sessions = await cache.listSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    // MARK: - Session Purging

    func test_purgeOldSessions_respectsMaxSessionsLimit() async throws {
        // maxSessions is 3 for test cache
        for i in 0..<5 {
            _ = try await cache.startSession(deviceName: "Device-\(i)", deviceType: "ios")
            // Need distinct timestamps in directory names
            try await Task.sleep(nanoseconds: 1_100_000_000)
        }

        let sessions = await cache.listSessions()
        XCTAssertLessThanOrEqual(sessions.count, 3)
    }

    // MARK: - Plugin ID Sanitization

    func test_sanitizePluginID_stripsCommonPrefix() {
        XCTAssertEqual(SessionFileCache.sanitizePluginID("com.echo.plugin.network"), "network")
        XCTAssertEqual(SessionFileCache.sanitizePluginID("com.echo.plugin.analytics"), "analytics")
        XCTAssertEqual(SessionFileCache.sanitizePluginID("com.echo.plugin.keyvaluestore"), "keyvaluestore")
    }

    func test_sanitizePluginID_preservesSimpleIDs() {
        XCTAssertEqual(SessionFileCache.sanitizePluginID("networking"), "networking")
        XCTAssertEqual(SessionFileCache.sanitizePluginID("analytics"), "analytics")
    }

    // MARK: - Session Properties

    func test_activeSessionID_returnsCurrentSessionID() async throws {
        let id = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")
        let activeID = await cache.activeSessionID
        XCTAssertEqual(activeID, id)
    }

    func test_activeSessionID_nilWhenNoSession() async {
        let activeID = await cache.activeSessionID
        XCTAssertNil(activeID)
    }

    func test_currentSessionPath_returnsPathWhenActive() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")
        let path = await cache.currentSessionPath
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.contains("iPhone-15"))
    }

    func test_currentSessionPath_nilAfterEnd() async throws {
        _ = try await cache.startSession(deviceName: "iPhone 15", deviceType: "ios")
        try await cache.endSession()
        let path = await cache.currentSessionPath
        XCTAssertNil(path)
    }

    // MARK: - End-to-End: Simulated Device Session

    func test_endToEnd_simulatedDeviceSession() async throws {
        // Simulate a device connecting and sending various plugin data
        _ = try await cache.startSession(deviceName: "iPhone 15 Pro", deviceType: "ios")

        // Simulate networking payloads
        let networkPayloads: [[String: Any]] = [
            ["url": "https://api.example.com/v1/customers", "method": "GET", "status_code": 200],
            ["url": "https://api.example.com/v1/transfers", "method": "POST", "status_code": 201],
            ["url": "https://api.example.com/v1/auth", "method": "POST", "status_code": 401],
        ]
        for networkData in networkPayloads {
            let payload = PluginPayload(
                pluginID: "com.echo.plugin.network",
                data: try JSONSerialization.data(withJSONObject: networkData)
            )
            try await cache.append(payload: payload)
        }

        // Simulate analytics payloads
        let analyticsPayloads: [[String: Any]] = [
            ["event": "screen_view", "screen": "home"],
            ["event": "button_tap", "button": "send_money"],
        ]
        for analyticsData in analyticsPayloads {
            let payload = PluginPayload(
                pluginID: "com.echo.plugin.analytics",
                data: try JSONSerialization.data(withJSONObject: analyticsData)
            )
            try await cache.append(payload: payload)
        }

        // Verify network data
        let networkLines = try await cache.readLines(plugin: "com.echo.plugin.network")
        XCTAssertEqual(networkLines.count, 3)

        // Verify we can grep-like filter for error responses
        let errorLines = try networkLines.filter { line in
            let parsed = try JSONSerialization.jsonObject(with: line) as! [String: Any]
            let data = parsed["data"] as! [String: Any]
            return (data["status_code"] as? Int ?? 0) >= 400
        }
        XCTAssertEqual(errorLines.count, 1)

        // Verify analytics data
        let analyticsLines = try await cache.readLines(plugin: "com.echo.plugin.analytics")
        XCTAssertEqual(analyticsLines.count, 2)

        // End session and verify metadata
        try await cache.endSession()

        let sessions = await cache.listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].deviceName, "iPhone 15 Pro")
        XCTAssertNotNil(sessions[0].endedAt)
        XCTAssertTrue(sessions[0].plugins.contains("network"))
        XCTAssertTrue(sessions[0].plugins.contains("analytics"))
    }
}
