import XCTest
@testable import DebugMenuPluginAPI

/// Pin the wire format of the Debug Menu plugin Codable models.
///
/// These tests exist to catch silent JSON-shape drift between the desktop CLI
/// (`echoapp`) and the on-device producers (iOS and Android client apps) that
/// emit and consume these payloads. A reshape of any model's `CodingKeys`,
/// enum case names, or associated value labels here will surface as a test
/// failure and force a deliberate coordinated update across all clients.
final class EchoDebugMenuWireFormatTests: XCTestCase {

    // MARK: - Item Types

    func testToggleItemTypeRoundTrip() throws {
        let original = EchoDebugMenuItemType.toggle(isOn: true)
        let json = try jsonObject(from: original)
        XCTAssertEqual(json, ["toggle": ["isOn": true]])
        let decoded = try decode(EchoDebugMenuItemType.self, from: json)
        XCTAssertEqual(decoded, original)
    }

    func testPickerItemTypeRoundTrip() throws {
        let original = EchoDebugMenuItemType.picker(options: ["a", "b", "c"], selectedIndex: 1)
        let json = try jsonObject(from: original)
        XCTAssertEqual(json, ["picker": ["options": ["a", "b", "c"], "selectedIndex": 1]])
        let decoded = try decode(EchoDebugMenuItemType.self, from: json)
        XCTAssertEqual(decoded, original)
    }

    func testActionItemTypeRoundTrip() throws {
        let original = EchoDebugMenuItemType.action
        let json = try jsonObject(from: original)
        // The Codable synthesis emits `{"action": {}}` for cases with no associated
        // values. This is the contract — both producers and the CLI rely on it.
        XCTAssertEqual(json, ["action": [:]])
        let decoded = try decode(EchoDebugMenuItemType.self, from: json)
        XCTAssertEqual(decoded, original)
    }

    func testTextInputItemTypeRoundTrip() throws {
        let original = EchoDebugMenuItemType.textInput(value: "hello", placeholder: "type here")
        let json = try jsonObject(from: original)
        XCTAssertEqual(json, ["textInput": ["value": "hello", "placeholder": "type here"]])
        let decoded = try decode(EchoDebugMenuItemType.self, from: json)
        XCTAssertEqual(decoded, original)
    }

    func testTextInputWithNilPlaceholderRoundTrip() throws {
        let original = EchoDebugMenuItemType.textInput(value: "", placeholder: nil)
        let decoded = try decode(EchoDebugMenuItemType.self, from: try jsonObject(from: original))
        XCTAssertEqual(decoded, original)
    }

    func testInfoItemTypeRoundTrip() throws {
        let original = EchoDebugMenuItemType.info(value: "Build 1234")
        let json = try jsonObject(from: original)
        XCTAssertEqual(json, ["info": ["value": "Build 1234"]])
        let decoded = try decode(EchoDebugMenuItemType.self, from: json)
        XCTAssertEqual(decoded, original)
    }

    func testSubsectionItemTypeRoundTrip() throws {
        let nested = EchoDebugMenuSection(
            id: "nested",
            title: "Nested",
            icon: nil,
            items: [
                EchoDebugMenuItem(
                    id: "child",
                    title: "Child",
                    subtitle: nil,
                    type: .toggle(isOn: false),
                ),
            ],
        )
        let original = EchoDebugMenuItemType.subsection(nested)
        let decoded = try decode(EchoDebugMenuItemType.self, from: try jsonObject(from: original))
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Item description -> "description" coding key

    func testItemDescriptionKeyIsDescriptionOnWire() throws {
        let item = EchoDebugMenuItem(
            id: "alpha",
            alias: "a1",
            title: "Alpha",
            subtitle: nil,
            itemDescription: "what this does",
            type: .toggle(isOn: false),
            tags: ["debug"],
        )
        let json = try jsonObject(from: item)
        XCTAssertEqual(json["description"] as? String, "what this does")
        XCTAssertNil(json["itemDescription"], "Swift property name must not appear on the wire.")
    }

    // MARK: - Snapshot schema versioning

    func testSnapshotEncodesCurrentSchemaVersion() throws {
        let snapshot = EchoDebugMenuSnapshot(
            sections: [],
            timestamp: Date(timeIntervalSince1970: 1_000),
        )
        let json = try jsonObject(from: snapshot)
        XCTAssertEqual(json["schemaVersion"] as? Int, EchoDebugMenuSnapshot.currentSchemaVersion)
    }

    func testSnapshotMissingSchemaVersionDecodesAsZero() throws {
        let payload: [String: Any] = [
            "sections": [],
            "timestamp": 1_000.0,
        ]
        let decoded = try decode(EchoDebugMenuSnapshot.self, from: payload)
        XCTAssertEqual(decoded.schemaVersion, 0, "Pre-versioned snapshots must default to 0.")
    }

    func testSnapshotPreservesSchemaVersionOnDecode() throws {
        let payload: [String: Any] = [
            "schemaVersion": 42,
            "sections": [],
            "timestamp": 1_000.0,
        ]
        let decoded = try decode(EchoDebugMenuSnapshot.self, from: payload)
        XCTAssertEqual(decoded.schemaVersion, 42)
    }

    // MARK: - Events

    func testUpdateSnapshotEventUsesUnderscoreZeroKey() throws {
        let snapshot = EchoDebugMenuSnapshot(
            sections: [],
            timestamp: Date(timeIntervalSince1970: 1_000),
        )
        let event = EchoDebugMenuClientEvent.updateSnapshot(_0: snapshot)
        let json = try jsonObject(from: event)
        let outer = try XCTUnwrap(json["updateSnapshot"] as? [String: Any])
        XCTAssertNotNil(outer["_0"], "Single unnamed associated value must encode under `_0`.")
    }

    func testActionCompletedEventRoundTrip() throws {
        let event = EchoDebugMenuClientEvent.actionCompleted(
            itemId: "X",
            success: false,
            message: "boom",
        )
        let decoded = try decode(EchoDebugMenuClientEvent.self, from: try jsonObject(from: event))
        XCTAssertEqual(decoded, event)
    }

    func testItemUpdatedEventRoundTrip() throws {
        let event = EchoDebugMenuClientEvent.itemUpdated(itemId: "X", newType: .toggle(isOn: true))
        let decoded = try decode(EchoDebugMenuClientEvent.self, from: try jsonObject(from: event))
        XCTAssertEqual(decoded, event)
    }

    func testErrorEventRoundTrip() throws {
        let event = EchoDebugMenuClientEvent.error(message: "broken")
        let decoded = try decode(EchoDebugMenuClientEvent.self, from: try jsonObject(from: event))
        XCTAssertEqual(decoded, event)
    }

    func testDesktopEventsRoundTrip() throws {
        let cases: [EchoDebugMenuDesktopEvent] = [
            .requestSnapshot,
            .setToggle(itemId: "id1", isOn: true),
            .selectOption(itemId: "id2", selectedIndex: 3),
            .executeAction(itemId: "id3"),
            .setTextValue(itemId: "id4", value: "v"),
        ]
        for original in cases {
            let decoded = try decode(EchoDebugMenuDesktopEvent.self, from: try jsonObject(from: original))
            XCTAssertEqual(decoded, original, "Round-trip failed for case: \(original)")
        }
    }

    // MARK: - Helpers

    private func jsonObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

// MARK: - Equality helpers for [String: Any]

private func XCTAssertEqual(
    _ lhs: [String: Any]?,
    _ rhs: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    guard let lhs else {
        XCTFail("Expected non-nil dict", file: file, line: line)
        return
    }
    XCTAssertTrue(
        NSDictionary(dictionary: lhs).isEqual(to: rhs),
        "Dicts differ:\n  lhs: \(lhs)\n  rhs: \(rhs)",
        file: file,
        line: line,
    )
}
