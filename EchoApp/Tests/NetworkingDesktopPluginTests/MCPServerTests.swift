import AppKit
import XCTest
import ComposableArchitecture
import EchoMCP
import EchoPluginAPI
@testable import NetworkingDesktopPlugin

private struct NoOpAppStateArchiver: AppStateArchiver {
    func archiveAppState(_ state: AppState) {}
    func unarchiveAppState() -> AppState? { nil }
}

@MainActor
final class MCPServerTests: XCTestCase {

    private func makeTestEnvironment() -> AppEnvironment {
        // Use a no-op pasteboard and archiver to avoid crashes in headless test environment
        AppEnvironment(
            appStateArchiver: NoOpAppStateArchiver(),
            pasteboard: .init(name: NSPasteboard.Name("MCPServerTests-\(UUID().uuidString)")),
            urlOpener: { _ in }
        )
    }

    private func makeStore(exchanges: [Exchange] = []) -> Store<AppState, AppAction> {
        var state = AppState()
        for exchange in exchanges {
            state.exchanges.append(exchange)
        }
        return Store(initialState: state) {
            AppReducer(environment: makeTestEnvironment())
        }
    }

    private func makeExchange(
        url: String = "https://api.example.com/payments",
        method: String = "GET",
        status: Int? = 200
    ) -> Exchange {
        let reqID = UUID().uuidString
        let request = EchoPluginAPI.Request(
            id: reqID,
            url: URL(string: url)!,
            httpMethod: method,
            headers: [:],
            timestamp: Date(),
            humanReadableBody: "",
            rawBody: nil
        )
        if let status {
            let response = HumanReadableResponse(requestID: reqID, headers: [:], body: "{}", statusCode: status)
            return Exchange(request: request, state: .finalizedResponse(response, selectedPolicy: .proxy))
        } else {
            return Exchange(request: request, state: .waitingForClientProvidedResponse)
        }
    }

    // MARK: - Device tests (MCPServer)

    func testListDevicesWhenNoDeviceConnected() async {
        let server = MCPServer(port: 0)
        let devices = await server.listDevices()
        XCTAssertTrue(devices.isEmpty)
    }

    func testListDevicesWhenDeviceConnected() async {
        let server = MCPServer(port: 0)
        await server.setSession(DeviceSession(id: "test-session-1"))
        let devices = await server.listDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0]["id"] as? String, "test-session-1")
    }

    func testSessionSetAndCleared() async {
        let server = MCPServer(port: 0)

        let before = await server.listDevices()
        XCTAssertTrue(before.isEmpty)

        await server.setSession(DeviceSession(id: "device-abc"))
        let after = await server.listDevices()
        XCTAssertEqual(after.count, 1)

        await server.setSession(nil)
        let cleared = await server.listDevices()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testConfigFileWrittenOnStart() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-written-\(UUID().uuidString).json")
        let server = MCPServer(port: 34199, configFileURL: configURL)
        try server.startForTesting()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["port"] as? Int, 34199)

        server.stop()
    }

    func testConfigFileRemovedOnStop() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-removed-\(UUID().uuidString).json")
        let server = MCPServer(port: 34198, configFileURL: configURL)
        try server.startForTesting()
        server.stop()

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    // MARK: - Exchange tests (NetworkingMCPToolProvider)

    func testListExchangesReturnsAll() async {
        let store = makeStore(exchanges: [
            makeExchange(url: "https://api.example.com/payments"),
            makeExchange(url: "https://api.example.com/catalog")
        ])
        let provider = NetworkingMCPToolProvider(store: store)

        let result = await provider.listExchanges(urlFilter: nil, method: nil, statusCode: nil, lastSeconds: nil, since: nil, limit: 50, offset: 0)
        XCTAssertEqual(result.total, 2)
    }

    func testListExchangesFiltersByURL() async {
        let store = makeStore(exchanges: [
            makeExchange(url: "https://api.example.com/payments"),
            makeExchange(url: "https://api.example.com/catalog")
        ])
        let provider = NetworkingMCPToolProvider(store: store)

        let result = await provider.listExchanges(urlFilter: "payments", method: nil, statusCode: nil, lastSeconds: nil, since: nil, limit: 50, offset: 0)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.exchanges[0]["url"] as? String, "https://api.example.com/payments")
    }

    func testListExchangesFiltersByLastSeconds() async {
        let oldRequest = EchoPluginAPI.Request(
            id: UUID().uuidString,
            url: URL(string: "https://api.example.com/old")!,
            httpMethod: "GET",
            headers: [:],
            timestamp: Date(timeIntervalSinceNow: -120),
            humanReadableBody: "",
            rawBody: nil
        )
        let oldExchange = Exchange(request: oldRequest, state: .waitingForClientProvidedResponse)
        let recentExchange = makeExchange(url: "https://api.example.com/recent")
        let store = makeStore(exchanges: [oldExchange, recentExchange])
        let provider = NetworkingMCPToolProvider(store: store)

        let result = await provider.listExchanges(urlFilter: nil, method: nil, statusCode: nil, lastSeconds: 30, since: nil, limit: 50, offset: 0)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.exchanges[0]["url"] as? String, "https://api.example.com/recent")
    }

    func testListExchangesPaginates() async {
        let exchanges = (0..<5).map { makeExchange(url: "https://api.example.com/item/\($0)") }
        let store = makeStore(exchanges: exchanges)
        let provider = NetworkingMCPToolProvider(store: store)

        let result = await provider.listExchanges(urlFilter: nil, method: nil, statusCode: nil, lastSeconds: nil, since: nil, limit: 2, offset: 2)
        XCTAssertEqual(result.total, 5)
        XCTAssertEqual(result.exchanges.count, 2)
    }

    func testGetExchangeReturnsDetail() async {
        let exchange = makeExchange(url: "https://api.example.com/payments", status: 201)
        let provider = NetworkingMCPToolProvider(store: makeStore(exchanges: [exchange]))

        let detail = await provider.getExchange(id: exchange.id)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?["id"] as? String, exchange.id.uuidString)
    }

    func testGetExchangeReturnsNilForUnknownID() async {
        let provider = NetworkingMCPToolProvider(store: makeStore())
        let detail = await provider.getExchange(id: UUID())
        XCTAssertNil(detail)
    }

    func testClearExchangesSendsAction() async throws {
        let exchange = makeExchange()
        let store = makeStore(exchanges: [exchange])
        let provider = NetworkingMCPToolProvider(store: store)

        await provider.clearExchanges()

        // Poll until cleared (avoids flaky fixed-duration sleep under CI load)
        let deadline = Date().addingTimeInterval(2)
        var result = await provider.listExchanges(urlFilter: nil, method: nil, statusCode: nil, lastSeconds: nil, since: nil, limit: 50, offset: 0)
        while result.total != 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
            result = await provider.listExchanges(urlFilter: nil, method: nil, statusCode: nil, lastSeconds: nil, since: nil, limit: 50, offset: 0)
        }
        XCTAssertEqual(result.total, 0)
    }
}
