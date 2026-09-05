import Foundation

/// Run an executable
func execute(_ executablePath: String, arguments: [String]) throws {

    struct Error: LocalizedError {
        let executablePath: String
        let arguments: [String]
        let underlyingError: Swift.Error

        var errorDescription: String? {
            let invocation = "\(executablePath) \(arguments.joined(separator: " "))"
            return "Error running `\(invocation)`: \(underlyingError.localizedDescription)"
        }
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw Error(executablePath: executablePath, arguments: arguments, underlyingError: error)
    }
}
