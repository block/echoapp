import XCTest

@testable import Echo

final class AnalyticsErrorTypeTests: XCTestCase {

    func test_connectionErrorType_preservesADBErrorCaseWithoutUnderlyingDetails() {
        XCTAssertEqual(
            AnalyticsErrorType.connectionErrorType(ADBError.adbNotFound),
            "Echo.ADBError.adbNotFound"
        )
        XCTAssertEqual(
            AnalyticsErrorType.connectionErrorType(
                ADBError.adbDiscoveryFailed(underlyingError: "sensitive device detail")
            ),
            "Echo.ADBError.adbDiscoveryFailed"
        )
        XCTAssertEqual(
            AnalyticsErrorType.connectionErrorType(
                ADBError.adbCommandFailed(
                    command: "sensitive command",
                    underlyingError: "sensitive output"
                )
            ),
            "Echo.ADBError.adbCommandFailed"
        )
    }
}
