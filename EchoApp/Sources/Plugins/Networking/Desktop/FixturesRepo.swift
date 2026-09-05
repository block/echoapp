import Foundation
import EchoPluginAPI

/// A helper class for obtaining fixtures from the fixtures repo
public final class FixturesRepo {

    public init() {}

    // MARK: - Public Methods

    public func loadFixtures(
        fromFixturesRepoDirectory fixturesRepoDirectory: URL
    ) -> [Endpoint: [Fixture]] {
        guard FileManager.default.fileExists(atPath: fixturesRepoDirectory.path) else {
            return [:]
        }

        return findFixtures(in: fixturesRepoDirectory)
    }

    // MARK: - Private Methods

    private func findFixtures(in rootDirectory: URL) -> [Endpoint: [Fixture]] {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [Endpoint: [Fixture]] = [:]

        for case let fileURL as URL in enumerator {
            guard
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                resourceValues.isRegularFile == true
            else {
                continue
            }

            // Compute the relative URL (path from rootDirectory to fileURL)
            let relativeURL = fileURL.pathComponents.dropFirst(rootDirectory.pathComponents.count)
            let relativeDirectory = relativeURL.dropLast() // remove filename
            let relativePath = relativeDirectory.joined(separator: "/")
            let endpoint = Endpoint(path: relativePath)

            let fileType = FileType(forFileAt: fileURL).contentType
            let fixture = Fixture(kind: .text(contentType: fileType), url: fileURL)
            result[endpoint, default: []].append(fixture)
        }
        return result
    }

}

// MARK: -

private enum FileType {
    case javascript
    case json
    case plainText

    init(forFileAt url: URL) {
        if url.pathExtension.isEmpty {
            self = .plainText
        } else {
            self.init(fileExtension: url.pathExtension)
        }
    }

    init(fileExtension: String) {
        switch fileExtension {
        case "js": self = .javascript
        case "json": self = .json
        case "txt", "text": self = .plainText
        default: self = .plainText
        }
    }

    var contentType: String {
        switch self {
        case .javascript: return "application/javascript"
        case .json: return "application/json"
        case .plainText: return "text/plain"
        }
    }
}
