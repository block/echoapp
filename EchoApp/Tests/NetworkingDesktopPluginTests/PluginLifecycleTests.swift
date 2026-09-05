import AppKit
import XCTest
import EchoMCP
@testable import NetworkingDesktopPlugin

final class PluginLifecycleTests: XCTestCase {
    func testMCPServerStartsAndStops() throws {
        let server = MCPServer(port: 34197)
        XCTAssertNoThrow(try server.startForTesting())
        server.stop()
    }
}
