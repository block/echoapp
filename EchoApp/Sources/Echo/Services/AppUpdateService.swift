import Foundation


protocol AppUpdateService {
    /// Current version of the application
    var currentVersion: EchoAppReleaseVersion { get }
    
    /// Checks for available updates
    /// - Returns: The latest release if available and newer than current version, nil otherwise
    func checkForUpdates() async throws -> Release?
    
    /// Performs the update and returns the redirect action
    /// - Parameter release: The release to update to
    /// - Returns: The action to show the update alert with redirect URL
    func performUpdate(release: Release) async throws -> AppUpdateSourceRedirectAction
}

// MARK: - Update Service Implementation

class RealAppUpdateService: AppUpdateService {
    
    // MARK: - Properties
    
    private let appUpdateSource: AppUpdateSource
    let currentVersion: EchoAppReleaseVersion
    
    // MARK: - Initialization
    
    init(
        appUpdateSource: AppUpdateSource,
        currentVersion: EchoAppReleaseVersion = .current()
    ) {
        self.appUpdateSource = appUpdateSource
        self.currentVersion = currentVersion
    }
    
    convenience init() {
        self.init(appUpdateSource: GitHubReleasesUpdateSource())
    }

    func checkForUpdates() async throws -> Release? {
        let release = try await appUpdateSource.checkForUpdates()

        // Only return the release if it's actually newer than current version
        if let release = release,
           let releaseVersion = EchoAppReleaseVersion(githubReleaseTag: release.version),
           releaseVersion.hasHigherPrecedence(than: currentVersion) {
            return release
        }
        
        return nil // No newer version available
    }
    
    func performUpdate(release: Release) async throws -> AppUpdateSourceRedirectAction {
        return try await appUpdateSource.performUpdate(release: release)
    }
}
