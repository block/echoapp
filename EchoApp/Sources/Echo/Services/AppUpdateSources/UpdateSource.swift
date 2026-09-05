import Foundation

// MARK: - Core Models

/// Represents a software release from any update source
public struct Release: Codable, Equatable {
    public let version: String
    public let metadata: [String: String] // For source-specific data

    public init(
        version: String,
        metadata: [String: String] = [:]
    ) {
        self.version = version
        self.metadata = metadata
    }
}

/// Protocol defining a generic interface for app update sources
public protocol AppUpdateSource {
    /// Whether this update source is available for use
    var isAvailable: Bool { get }

    /// Checks for available updates
    /// - Returns: The latest release if available, nil otherwise
    func checkForUpdates() async throws -> Release?

    /// Performs the update and returns the redirect action
    /// - Parameter release: The release to update to
    /// - Returns: The action to show the update alert with redirect URL
    func performUpdate(release: Release) async throws -> AppUpdateSourceRedirectAction
}

/// Describes the alert shown to redirect the user to an external update tool
public struct AppUpdateSourceRedirectAction: Equatable {
    public let message: String
    public let buttonTitle: String
    public let url: String

    public init(message: String, buttonTitle: String, url: String) {
        self.message = message
        self.buttonTitle = buttonTitle
        self.url = url
    }
}

/// Errors that can occur during update source operations
public enum AppUpdateSourceError: Error, Equatable {
    case networkError(String)
    case sourceUnavailable(String)
    case decodingError(String)
}

// MARK: - Type Aliases
typealias UpdateError = AppUpdateSourceError
