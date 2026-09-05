import Foundation
import XCTest

@testable import EchoCLI

final class ClearCommandTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func test_activeWriter_prefersCurrentPIDFile() throws {
        try writePID(100, filename: "echoapp.pid")
        try writePID(200, filename: "echo-cli.pid")

        let writer = CLIWriterPIDFile.activeWriter(in: temporaryDirectory) { _ in true }

        XCTAssertEqual(writer?.pid, 100)
        XCTAssertEqual(writer?.url.lastPathComponent, "echoapp.pid")
    }

    func test_activeWriter_fallsBackToLegacyPIDFileWhenCurrentPIDIsUnrelated() throws {
        try writePID(100, filename: "echoapp.pid")
        try writePID(200, filename: "echo-cli.pid")

        let writer = CLIWriterPIDFile.activeWriter(in: temporaryDirectory) { $0 == 200 }

        XCTAssertEqual(writer?.pid, 200)
        XCTAssertEqual(writer?.url.lastPathComponent, "echo-cli.pid")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("echoapp.pid").path
            )
        )
    }

    private func writePID(_ pid: Int32, filename: String) throws {
        try String(pid).write(
            to: temporaryDirectory.appendingPathComponent(filename),
            atomically: true,
            encoding: .utf8
        )
    }
}
