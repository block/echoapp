import Foundation

// MARK: - GitHub Releases Update Source

/// Update source backed by the public GitHub Releases feed.
class GitHubReleasesUpdateSource: AppUpdateSource {

    struct GitHubRelease: Codable, Equatable {
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    enum ReleaseFeed: Equatable {
        case stable
        case prerelease
    }

    static let releasesURL = "https://github.com/block/echoapp/releases"
    private static let releasesAPIURL = "https://api.github.com/repos/block/echoapp/releases"
    private static let releasesPageSize = 100

    let currentVersion: String
    private let currentReleaseVersion: EchoAppReleaseVersion

    init() {
        self.currentReleaseVersion = EchoAppReleaseVersion.current()
        self.currentVersion = currentReleaseVersion.rawValue
    }

    // MARK: - AppUpdateSource Implementation

    var isAvailable: Bool {
        true
    }

    func checkForUpdates() async throws -> Release? {
        do {
            let latestGitHubRelease = try Self.latestRelease(
                from: try await fetchPublishedReleases(),
                feed: Self.releaseFeed(for: currentReleaseVersion)
            )

            let version = try Self.releaseVersion(from: latestGitHubRelease).rawValue

            let release = Release(
                version: version,
                metadata: [
                    "name": latestGitHubRelease.name ?? latestGitHubRelease.tag_name,
                    "description": latestGitHubRelease.body ?? "",
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

    static func releaseFeed(for currentReleaseVersion: EchoAppReleaseVersion) -> ReleaseFeed {
        currentReleaseVersion.isPrerelease ? .prerelease : .stable
    }

    static func latestRelease(from releases: [GitHubRelease], feed: ReleaseFeed) throws -> GitHubRelease {
        let versionedReleases = releases
            .filter({ $0.draft != true })
            .compactMap({ release in
                EchoAppReleaseVersion(githubReleaseTag: release.tag_name)
                    .map({ (release, $0) })
            })
            .filter({ feed == .prerelease || (!$0.1.isPrerelease && $0.0.prerelease != true) })
        guard let firstRelease = versionedReleases.first else {
            throw AppUpdateSourceError.decodingError("GitHub Releases did not include a published SemVer release")
        }
        return versionedReleases.dropFirst().reduce(firstRelease) { latest, candidate in
            candidate.1.hasHigherPrecedence(than: latest.1) ? candidate : latest
        }.0
    }

    private func fetchPublishedReleases() async throws -> [GitHubRelease] {
        var releases: [GitHubRelease] = []
        var page = 1
        while true {
            let url = "\(Self.releasesAPIURL)?per_page=\(Self.releasesPageSize)&page=\(page)"
            let releasePage = try await fetchReleasePage(from: url)
            releases.append(contentsOf: releasePage)
            if releasePage.count < Self.releasesPageSize { break }
            page += 1
        }
        return releases
    }

    private func fetchReleasePage(from urlString: String) async throws -> [GitHubRelease] {
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AppUpdateSourceError.sourceUnavailable("GitHub Releases returned HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private static func releaseVersion(from release: GitHubRelease) throws -> EchoAppReleaseVersion {
        guard let version = EchoAppReleaseVersion(githubReleaseTag: release.tag_name) else {
            throw AppUpdateSourceError.decodingError("GitHub release tag is not valid SemVer: \(release.tag_name)")
        }
        return version
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
