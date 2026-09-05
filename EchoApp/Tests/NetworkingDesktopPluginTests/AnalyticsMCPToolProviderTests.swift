import MCP
import XCTest
import EchoPluginAPI
@testable import AnalyticsDesktopPlugin

@MainActor
final class AnalyticsMCPToolProviderTests: XCTestCase {

    private func makeRow(event: String, time: String? = nil, source: String = "TestSource", properties: String = "{}") -> EchoTableRow {
        var items: [String: String] = [
            "Event": event,
            "Source": source,
            "Properties": properties,
        ]
        if let time { items["Time"] = time }
        return EchoTableRow(columnItems: items)
    }

    private func makeProvider(rows: [EchoTableRow]) -> AnalyticsMCPToolProvider {
        AnalyticsMCPToolProvider(rowsProvider: { rows })
    }

    // MARK: - list_analytics_events

    func testListEventsReturnsSummaryFields() async throws {
        let row = makeRow(event: "AppLaunch", time: "2024-01-01 10:00:00")
        let provider = makeProvider(rows: [row])

        let result = try await provider.handle(toolName: "list_analytics_events", arguments: nil)
        XCTAssertFalse(result.isError ?? false)

        let text = result.content.compactMap { if case .text(let t, _, _) = $0 { return t } else { return nil } }.first!
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["event"] as? String, "AppLaunch")
        XCTAssertNil(events[0]["Properties"])
    }

    func testListEventsFiltersByEventName() async throws {
        let rows = [
            makeRow(event: "AppLaunch"),
            makeRow(event: "ButtonTap"),
            makeRow(event: "AppLaunch"),
        ]
        let provider = makeProvider(rows: rows)

        let result = try await provider.handle(
            toolName: "list_analytics_events",
            arguments: ["event_name": .string("ButtonTap")]
        )
        let text = result.content.compactMap { if case .text(let t, _, _) = $0 { return t } else { return nil } }.first!
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["total"] as? Int, 1)
    }

    func testListEventsPaginates() async throws {
        let rows = (0..<10).map { makeRow(event: "Event\($0)") }
        let provider = makeProvider(rows: rows)

        let result = try await provider.handle(
            toolName: "list_analytics_events",
            arguments: ["limit": .int(3), "offset": .int(5)]
        )
        let text = result.content.compactMap { if case .text(let t, _, _) = $0 { return t } else { return nil } }.first!
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["total"] as? Int, 10)
        XCTAssertEqual((json["events"] as? [[String: Any]])?.count, 3)
    }

    // MARK: - get_analytics_events

    func testGetEventsIncludesAllColumns() async throws {
        let row = makeRow(event: "Purchase", time: "2024-01-01 10:00:00", properties: "{\"amount\": 100}")
        let provider = makeProvider(rows: [row])

        let result = try await provider.handle(toolName: "get_analytics_events", arguments: nil)
        let text = result.content.compactMap { if case .text(let t, _, _) = $0 { return t } else { return nil } }.first!
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        XCTAssertEqual(events.count, 1)
        XCTAssertNotNil(events[0]["Properties"])
        XCTAssertNotNil(events[0]["Event"])
    }

    func testGetEventsFiltersByLastSeconds() async throws {
        // Row with a very old timestamp should be excluded
        let oldTime = "2020-01-01 00:00:00"
        let now = DateFormatter()
        now.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let recentTime = now.string(from: Date())

        let rows = [
            makeRow(event: "OldEvent", time: oldTime),
            makeRow(event: "RecentEvent", time: recentTime),
        ]
        let provider = makeProvider(rows: rows)

        let result = try await provider.handle(
            toolName: "get_analytics_events",
            arguments: ["last_seconds": .int(60)]
        )
        let text = result.content.compactMap { if case .text(let t, _, _) = $0 { return t } else { return nil } }.first!
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["Event"] as? String, "RecentEvent")
    }

    // MARK: - Unknown tool

    func testUnknownToolReturnsError() async throws {
        let provider = makeProvider(rows: [])
        let result = try await provider.handle(toolName: "nonexistent_tool", arguments: nil)
        XCTAssertEqual(result.isError, true)
    }
}
