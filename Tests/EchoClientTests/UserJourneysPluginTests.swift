@testable import EchoClient

import Foundation
import XCTest

final class UserJourneysPluginTests: XCTestCase {

    // MARK: - Tests - EventType

    func test_eventType_tagRemoved_roundTripsWithTagRemovedDiscriminator() throws {
        let data = try JSONEncoder().encode(UserJourneysPlugin.Event.EventType.tagRemoved)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["type": "tagRemoved"])
        XCTAssertEqual(
            try JSONDecoder().decode(UserJourneysPlugin.Event.EventType.self, from: data),
            .tagRemoved
        )
    }
}
