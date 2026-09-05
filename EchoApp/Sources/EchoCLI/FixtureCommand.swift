import ArgumentParser
import Foundation

// MARK: - Fixture Data Model

struct FixtureFile: Codable {
    let statusCode: Int
    let headers: [String: String]
    let body: String
}

// MARK: - FixtureCommand

struct FixtureCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fixture",
        abstract: "Manage network response fixtures for the current session.",
        discussion: """
            Fixtures let you intercept network requests and return custom responses \
            during a live echoapp session. When a proxy-mode request matches a \
            fixture's endpoint path, echoapp returns the fixture instead of \
            forwarding the request to the real server.

            Fixtures are session-scoped: they only apply to the current session and \
            are discarded when it ends. A new session starts with no fixtures.

            FIXTURE FILE FORMAT:
            Fixture files are JSON with three fields:
                {
                    "statusCode": 200,
                    "headers": {"Content-Type": "application/json"},
                    "body": "{\\"key\\": \\"value\\"}"
                }

            - statusCode: HTTP status code (integer)
            - headers: HTTP response headers (object, optional)
            - body: Response body as a string (typically JSON)

            Fixture files are stored at:
                $ECHO_DATA_DIR/current/fixtures/<endpoint-path>/<name>.json

            ENDPOINT MATCHING:
            Endpoints are matched by normalized URL path. The path /2.0/example/get-profile \
            matches requests to https://api.example.com/2.0/example/get-profile regardless \
            of host, query parameters, or HTTP method.

            If multiple fixture files exist for the same endpoint, the first one \
            alphabetically is used.

            EXAMPLES:
                # Add a fixture:
                echoapp fixture add /2.0/example/get-profile --body '{"name": "Test"}'

                # List active fixtures:
                echoapp fixture list

                # Remove a fixture:
                echoapp fixture remove /2.0/example/get-profile

                # Remove all fixtures:
                echoapp fixture remove --all
            """,
        subcommands: [
            FixtureAddCommand.self,
            FixtureListCommand.self,
            FixtureRemoveCommand.self,
        ]
    )

    // MARK: - Helpers

    static func fixturesDirectory(for sessionURL: URL) -> URL {
        sessionURL.appendingPathComponent("fixtures", isDirectory: true)
    }

    static func normalizeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/" + trimmed
    }

    /// Validates that a path component does not contain directory traversal segments.
    static func validateNoPathTraversal(_ value: String, label: String) throws {
        let components = value.components(separatedBy: "/")
        for component in components {
            if component == ".." || component == "." {
                throw ValidationError("\(label) must not contain path traversal segments ('.' or '..').")
            }
        }
    }

    /// Validates that a fixture name is a simple filename (no slashes).
    static func validateFixtureName(_ name: String) throws {
        try validateNoPathTraversal(name, label: "Fixture name")
        if name.contains("/") {
            throw ValidationError("Fixture name must not contain '/' -- it is used as a filename, not a path.")
        }
    }

    static func endpointDirectory(for sessionURL: URL, endpoint: String) -> URL {
        let normalized = normalizeEndpoint(endpoint)
        let relativePath = String(normalized.dropFirst()) // drop leading slash
        let resolved = fixturesDirectory(for: sessionURL)
            .appendingPathComponent(relativePath, isDirectory: true)
            .standardized
        return resolved
    }
}

// MARK: - FixtureAddCommand

struct FixtureAddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a fixture to intercept a network request during the current session.",
        discussion: """
            When echoapp is running in proxy mode, any request matching the endpoint path \
            will receive this fixture response instead of being forwarded to the real server. \
            Fixtures are session-scoped and are automatically discarded when the session ends.

            EXAMPLES:
                # Return a custom JSON response for an endpoint:
                echoapp fixture add /2.0/example/get-profile --body '{"name": "Test", "balance": 0}'

                # Use a fixture file on disk:
                echoapp fixture add /2.0/example/get-profile --body-file ./mock-profile.json

                # Return a 500 error:
                echoapp fixture add /2.0/example/initiate-payment --body '{}' --status-code 500

                # Multiple fixtures for the same endpoint (first alphabetically wins):
                echoapp fixture add /2.0/example/get-profile --name error --body '{}' --status-code 500
            """
    )

    @Argument(help: "URL path to intercept (e.g., /2.0/example/get-profile).")
    var endpoint: String

    @Option(name: .long, help: "Response body as inline JSON string.")
    var body: String?

    @Option(name: .customLong("body-file"), help: "Read response body from a file.")
    var bodyFile: String?

    @Option(name: .customLong("status-code"), help: "HTTP status code (default: 200).")
    var statusCode: Int = 200

    @Option(name: .long, help: """
        Fixture name. Used as filename. Allows multiple fixtures per endpoint; \
        the first alphabetically is used. (default: fixture)
        """)
    var name: String = "fixture"

    func validate() throws {
        try FixtureCommand.validateNoPathTraversal(endpoint, label: "Endpoint")
        try FixtureCommand.validateFixtureName(name)
        if body == nil && bodyFile == nil {
            throw ValidationError("Either --body or --body-file must be provided.")
        }
        if body != nil && bodyFile != nil {
            throw ValidationError("Only one of --body or --body-file may be provided, not both.")
        }
        if let bodyFile {
            guard FileManager.default.isReadableFile(atPath: bodyFile) else {
                throw ValidationError("Cannot read file at path: \(bodyFile)")
            }
        }
    }

    func run() throws {
        guard let sessionURL = SessionDirectory.currentSessionURL() else {
            throw EchoCLIError.noActiveSession
        }

        let resolvedBody: String
        if let body {
            resolvedBody = body
        } else {
            resolvedBody = try String(contentsOfFile: bodyFile!, encoding: .utf8)
        }

        let fixture = FixtureFile(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: resolvedBody
        )

        let normalizedEndpoint = FixtureCommand.normalizeEndpoint(endpoint)
        let directory = FixtureCommand.endpointDirectory(for: sessionURL, endpoint: endpoint)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "\(name).json"
        let fileURL = directory.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixture)
        try data.write(to: fileURL)

        print("Fixture added: \(normalizedEndpoint) -> \(filename) (\(statusCode) \(httpStatusText(statusCode)))")
        print(fileURL.path)
    }
}

// MARK: - FixtureListCommand

struct FixtureListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all active fixtures in the current session."
    )

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: FixtureListFormat = .text

    func run() throws {
        guard let sessionURL = SessionDirectory.currentSessionURL() else {
            throw EchoCLIError.noActiveSession
        }

        let fixturesDir = FixtureCommand.fixturesDirectory(for: sessionURL)
        guard FileManager.default.fileExists(atPath: fixturesDir.path) else {
            print("No active fixtures.")
            return
        }

        let entries = collectFixtures(in: fixturesDir)
        if entries.isEmpty {
            print("No active fixtures.")
            return
        }

        switch format {
        case .text:
            for entry in entries {
                print("\(entry.endpoint) -> \(entry.name).json (\(entry.statusCode) \(httpStatusText(entry.statusCode)))")
            }
        case .json:
            let output = entries.map { entry -> [String: Any] in
                [
                    "endpoint": entry.endpoint,
                    "name": entry.name,
                    "statusCode": entry.statusCode,
                    "path": entry.path,
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        }
    }

    // MARK: - Private Helpers

    private struct FixtureEntry {
        let endpoint: String
        let name: String
        let statusCode: Int
        let path: String
    }

    private func collectFixtures(in fixturesDir: URL) -> [FixtureEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: fixturesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [FixtureEntry] = []
        let fixturesDirPath = fixturesDir.path

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let fixture = try? JSONDecoder().decode(FixtureFile.self, from: data) else {
                continue
            }

            let directory = fileURL.deletingLastPathComponent().path
            let relativePath = String(directory.dropFirst(fixturesDirPath.count))
            let endpoint = relativePath.isEmpty ? "/" : FixtureCommand.normalizeEndpoint(relativePath)
            let name = fileURL.deletingPathExtension().lastPathComponent

            entries.append(FixtureEntry(
                endpoint: endpoint,
                name: name,
                statusCode: fixture.statusCode,
                path: fileURL.path
            ))
        }

        return entries.sorted { ($0.endpoint, $0.name) < ($1.endpoint, $1.name) }
    }
}

enum FixtureListFormat: String, ExpressibleByArgument {
    case text
    case json
}

// MARK: - FixtureRemoveCommand

struct FixtureRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove fixture(s) for an endpoint, or all fixtures."
    )

    @Argument(help: "URL path to remove fixtures for.")
    var endpoint: String?

    @Flag(name: .long, help: "Remove all fixtures for the current session.")
    var all: Bool = false

    @Option(name: .long, help: "Remove only the fixture with this name.")
    var name: String?

    func validate() throws {
        if !all && endpoint == nil {
            throw ValidationError("Provide an <endpoint> or use --all to remove all fixtures.")
        }
        if all && endpoint != nil {
            throw ValidationError("Cannot use --all together with a specific endpoint.")
        }
        if all && name != nil {
            throw ValidationError("Cannot use --all together with --name.")
        }
        if name != nil && endpoint == nil {
            throw ValidationError("--name requires an <endpoint> to be specified.")
        }
        if let endpoint {
            try FixtureCommand.validateNoPathTraversal(endpoint, label: "Endpoint")
        }
        if let name {
            try FixtureCommand.validateFixtureName(name)
        }
    }

    func run() throws {
        guard let sessionURL = SessionDirectory.currentSessionURL() else {
            throw EchoCLIError.noActiveSession
        }

        let fm = FileManager.default
        let fixturesDir = FixtureCommand.fixturesDirectory(for: sessionURL)

        if all {
            if fm.fileExists(atPath: fixturesDir.path) {
                try fm.removeItem(at: fixturesDir)
                print("All fixtures removed.")
            } else {
                print("No fixtures to remove.")
            }
            return
        }

        let normalizedEndpoint = FixtureCommand.normalizeEndpoint(endpoint!)
        let endpointDir = FixtureCommand.endpointDirectory(for: sessionURL, endpoint: endpoint!)

        guard fm.fileExists(atPath: endpointDir.path) else {
            print("No fixtures found for \(normalizedEndpoint).")
            return
        }

        if let name {
            let fileURL = endpointDir.appendingPathComponent("\(name).json")
            guard fm.fileExists(atPath: fileURL.path) else {
                print("No fixture named '\(name)' for \(normalizedEndpoint).")
                return
            }
            try fm.removeItem(at: fileURL)
            print("Removed fixture: \(normalizedEndpoint) -> \(name).json")
            cleanupEmptyDirectories(from: endpointDir, upTo: fixturesDir)
        } else {
            // Remove only regular JSON fixture files in this directory, preserving
            // subdirectories (which represent nested endpoint fixtures).
            let contents = try fm.contentsOfDirectory(
                at: endpointDir,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            let jsonFiles = contents.filter { url -> Bool in
                guard url.pathExtension == "json" else { return false }
                let keys: Set<URLResourceKey> = [.isRegularFileKey]
                let isFile = (try? url.resourceValues(forKeys: keys).isRegularFile) ?? false
                return isFile
            }
            guard !jsonFiles.isEmpty else {
                print("No fixtures found for \(normalizedEndpoint).")
                return
            }
            for file in jsonFiles {
                try fm.removeItem(at: file)
            }
            print("Removed all fixtures for \(normalizedEndpoint).")
            cleanupEmptyDirectories(from: endpointDir, upTo: fixturesDir)
        }
    }

    // MARK: - Private Helpers

    private func cleanupEmptyDirectories(from directory: URL, upTo root: URL) {
        let fm = FileManager.default
        var current = directory

        while current.path != root.path && current.path.hasPrefix(root.path) {
            guard let contents = try? fm.contentsOfDirectory(atPath: current.path),
                  contents.isEmpty else {
                break
            }
            try? fm.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }
}

// MARK: - HTTP Status Helpers

private func httpStatusText(_ code: Int) -> String {
    HTTPURLResponse.localizedString(forStatusCode: code).capitalized
}
