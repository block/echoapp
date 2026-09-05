import Foundation
import XCTest

@testable import Echo

final class EchoAppDefaultsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "EchoAppDefaultsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMigrationCopiesLegacyValuesWithoutOverwritingCurrentValues() {
        defaults.set("current", forKey: "preserved")

        EchoAppDefaultsMigration.migrateIfNeeded(
            from: ["preserved": "legacy", "copied": true],
            to: defaults
        )

        XCTAssertEqual(defaults.string(forKey: "preserved"), "current")
        XCTAssertTrue(defaults.bool(forKey: "copied"))
        XCTAssertTrue(defaults.bool(forKey: EchoAppDefaultsMigration.migrationKey))
    }

    func testMigrationRunsOnlyOnce() {
        EchoAppDefaultsMigration.migrateIfNeeded(from: ["value": "first"], to: defaults)
        EchoAppDefaultsMigration.migrateIfNeeded(from: ["value": "second"], to: defaults)

        XCTAssertEqual(defaults.string(forKey: "value"), "first")
    }
}
