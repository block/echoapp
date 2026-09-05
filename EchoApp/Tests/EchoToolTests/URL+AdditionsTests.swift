
@testable import EchoTool

import XCTest

final class URL_AdditionsTests: XCTestCase {

    func test_expressibleByArgument_supportsAbsolutePaths() {
        XCTAssertEqual(URL(argument: "/foo/bar").path, "/foo/bar")
    }

    func test_expressibleByArgument_supportsRelativePaths() {
        let currentDirectory = FileManager.default.currentDirectoryPath
        XCTAssertEqual(URL(argument: "foo/bar").path, "\(currentDirectory)/foo/bar")
    }

    func test_expressibleByArgument_expandsTilde() {
        let url = URL(argument: "~/foo")
        XCTAssertEqual(url.pathComponents.first, "/")
        XCTAssertEqual(url.pathComponents.last, "foo")
    }

}
