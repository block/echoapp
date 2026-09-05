import Foundation
import os

/// A wrapper around the Android `adb` platform tool
final class ADB: Sendable {
    private static let autolocatedShared = ADB.autolocate()

    static var sharedProvider: () -> ADB? = { autolocatedShared }

    static let defaultPath = "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"

    static let knownADBPaths = [
        defaultPath,
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
    ]

    static let emulatorHost = "127.0.0.1"
    static let emulatorPort: UInt16 = 42633

    /// A device discovered using `adb devices`
    struct Device: Equatable, Sendable {
        let name: String
        let product: String?
        let model: String?
        let deviceType: String
        let transportId: String
                
        // Eventually this should be non-optional. Optional for temporary backwards compatibility
        var androidId: String? = nil
        var connectionIdentifier: String? = nil
        
        var androidIdOrName: String {
            connectionIdentifier ?? androidId ?? name
        }
        
        var unixDomainSocket: String {
            if let androidId {
                "echo-server-\(androidId)"
            } else {
                "echo-server"
            }
        }
    }


    let path: String
    let logger = Logger.echoLogger(category: "ADB")

    init?(path: String) {
        if !FileManager.default.isExecutableFile(atPath: path) {
            return nil
        }
        self.path = path
    }

    static func autolocate() -> ADB? {
        for path in adbSearchPaths() {
            if let adb = ADB(path: path) {
                adb.logger.info("Using adb executable at \(path, privacy: .public)")
                return adb
            }
        }
        return nil
    }

    static func adbSearchPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        whichADB: () -> String? = { ADB.which("adb") }
    ) -> [String] {
        var paths: [String] = []

        if let pathFromWhich = whichADB() {
            paths.append(pathFromWhich)
        }

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let sdkRoot = environment[key], !sdkRoot.isEmpty {
                let expandedSDKRoot = (sdkRoot as NSString).expandingTildeInPath
                paths.append(
                    URL(fileURLWithPath: expandedSDKRoot)
                        .appendingPathComponent("platform-tools/adb")
                        .path
                )
            }
        }

        paths.append(contentsOf: knownADBPaths)
        return paths.uniqued()
    }

    /// Returns the list of devices available via `adb devices -l`
    func devices() async throws -> [Device] {
        let output = try await execute("devices", "-l")

        return output
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.lowercased().contains("list of devices") else {
                    return nil
                }

                // Require " device " to ensure it's a connected device (not offline)
                guard trimmed.contains(" device ") else { return nil }

                // Split on any sequence of whitespace
                let parts = trimmed.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }

                guard let name = parts.first else { return nil }

                var attributes: [String: String] = ["name": name]

                for token in parts.dropFirst() {
                    let keyValue = token.split(separator: ":", maxSplits: 1).map(String.init)
                    if keyValue.count == 2 {
                        attributes[keyValue[0]] = keyValue[1]
                    }
                }

                return Device(
                    name: attributes["name"] ?? "",
                    product: attributes["product"]?.replacingOccurrences(of: "_", with: " "),
                    model: attributes["model"]?.replacingOccurrences(of: "_", with: " "),
                    deviceType: attributes["device"] ?? "",
                    transportId: attributes["transport_id"] ?? ""
                )
            }
    }

    /// Establishs a port forwarding connection between your development machine (host)
    /// and a connected Android device or emulator.
    /// This means that traffic sent to a specific port on your host machine will be redirected
    /// to a specific port on the Android device, and vice versa.
    /// - parameter local: The address (e.g. tcp:9000) on your host machine that you want to forward
    /// - parameter remote: The address (e.g. tcp:9000) on the Android device that you want to connect to.
    @discardableResult
    func portForward(device: Device, local: String, remote: String) async throws -> String {
        try await execute("-s", device.name, "forward", local, remote)
    }

    /// Find all unix domain sockets for the specified device
    /// - returns: An array of @-prefixed names of abstract unix domain sockets
    func findUnixDomainSockets(for device: Device) async throws -> [String] {
        let lines = try await execute("-s", device.name, "shell", "ss", "-xl")
            .split(whereSeparator: \.isNewline)

        let unixDomainSockets = lines.compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.first(where: { $0.hasPrefix("@") })
                .map(String.init)
        }
        return unixDomainSockets
    }

    /// Resolves the default identifier sent by legacy echo-android clients whose
    /// unix socket name does not carry an Android ID.
    func androidDeviceIdentifier(for device: Device) async throws -> String {
        let identifier = try await execute(
            "-s", device.name, "shell", "settings", "get", "secure", "android_id"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, identifier.lowercased() != "null" else {
            throw ADBError.adbDiscoveryFailed(
                underlyingError: "Unable to resolve an Android ID for \(device.name)."
            )
        }
        return identifier
    }

    /// Execute `adb` with the provided arguments
    @discardableResult
    func execute(_ arguments: String...) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let start = ContinuousClock.now

        do {
            let output = try await process.executeAndReadOutput()
            let duration = start.duration(to: .now)
            logger.debug(
                "adb command completed in \(duration, privacy: .public): \(arguments.joined(separator: " "), privacy: .public)"
            )
            return output.stdout
        }
        catch {
            if error is CancellationError {
                throw error
            }
            else {
                logger.error("adb command failed: \(arguments.joined(separator: " "), privacy: .public)")
                throw ADBError.adbCommandFailed(
                    command: arguments.joined(separator: " "),
                    underlyingError: error.localizedDescription
                )
            }
        }
    }
}

private extension ADB {

    static func which(_ executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }
}

private extension Array where Element == String {

    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

struct ProcessOutput: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

struct ProcessExecutionError: LocalizedError, Equatable, Sendable {
    private static let maximumErrorLength = 2_048

    let terminationStatus: Int32
    let stderr: String

    var errorDescription: String? {
        let boundedError = String(stderr.prefix(Self.maximumErrorLength))
        if boundedError.isEmpty {
            return "Process exited with status \(terminationStatus)."
        }
        return "Process exited with status \(terminationStatus): \(boundedError)"
    }
}

extension Process {

    func executeAndReadOutput() async throws -> ProcessOutput {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        standardOutput = stdoutPipe
        standardError = stderrPipe

        let termination = AsyncStream.makeStream(of: Void.self)
        terminationHandler = { _ in
            termination.continuation.yield(())
            termination.continuation.finish()
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try run()

            // Drain both pipes while the child is running. Waiting for termination
            // first can deadlock once either pipe's kernel buffer fills.
            async let stdoutData = Task.detached {
                stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
            async let stderrData = Task.detached {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }.value

            for await _ in termination.stream {
                break
            }

            try Task.checkCancellation()

            let stdout = String(data: await stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: await stderrData, encoding: .utf8) ?? ""
            let output = ProcessOutput(
                stdout: stdout,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                terminationStatus: terminationStatus
            )
            guard terminationStatus == 0 else {
                throw ProcessExecutionError(
                    terminationStatus: terminationStatus,
                    stderr: output.stderr
                )
            }
            return output
        } onCancel: {
            if isRunning {
                terminate()
            }
        }
    }
}
