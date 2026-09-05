import Foundation

// MARK: - GitHub Releases Update Source

/// Update source backed by the public GitHub Releases feed.
class GitHubReleasesUpdateSource: AppUpdateSource {

    private struct GitHubRelease: Codable {
        let tag_name: String
        let name: String?
        let body: String?
    }

    static let releasesURL = "https://github.com/block/echoapp/releases"
    private static let latestReleaseAPIURL = "https://api.github.com/repos/block/echoapp/releases/latest"

    let currentVersion: String

    init() {
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - AppUpdateSource Implementation

    var isAvailable: Bool {
        true
    }

    func checkForUpdates() async throws -> Release? {
        let url = URL(string: Self.latestReleaseAPIURL)!
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw AppUpdateSourceError.sourceUnavailable("GitHub Releases returned HTTP \(httpResponse.statusCode)")
            }

            let latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = latest.tag_name.hasPrefix("v") ? String(latest.tag_name.dropFirst()) : latest.tag_name

            let release = Release(
                version: version,
                metadata: [
                    "name": latest.name ?? latest.tag_name,
                    "description": latest.body ?? "",
                    "installationMethod": "github"
                ]
            )

            AnalyticsProvider.shared.trackUpdateChecked(
                installationMethod: "github",
                currentVersion: currentVersion,
                newVersion: version,
                source: "githubReleases"
            )

            return release
        } catch let error as AppUpdateSourceError {
            throw error
        } catch let decodingError as DecodingError {
            throw AppUpdateSourceError.decodingError("Failed to decode GitHub release: \(decodingError)")
        } catch {
            throw AppUpdateSourceError.networkError("Failed to reach GitHub Releases: \(error.localizedDescription)")
        }
    }

    func performUpdate(release: Release) async throws -> AppUpdateSourceRedirectAction {
        AnalyticsProvider.shared.trackUpdatePerformed(
            installationMethod: "github",
            currentVersion: currentVersion,
            newVersion: release.version,
            source: "githubReleases"
        )

        return AppUpdateSourceRedirectAction(
            message: "Download the latest EchoApp.app.zip from GitHub Releases and replace the one in your /Applications directory.",
            buttonTitle: "Close EchoApp and Open GitHub",
            url: Self.releasesURL
        )
    }
}
