import Foundation

final class XcodeSelect {
    enum Error: Swift.Error {
        case failedToFindDeveloperDirectory
    }

    func pathToXcodeApp() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw Error.failedToFindDeveloperDirectory
        }

        // The output points to the `Contents/Developer` subdirectory.
        // Navigate up two levels to the .app directory
        return URL(filePath: output).deletingLastPathComponent().deletingLastPathComponent()
    }

    func pathToXcodeBinary() throws -> URL {
        try pathToXcodeApp().appending(path: "Contents/MacOS/Xcode")
    }
}
