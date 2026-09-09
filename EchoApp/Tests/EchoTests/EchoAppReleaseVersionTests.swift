import XCTest
@testable import Echo

final class EchoAppReleaseVersionTests: XCTestCase {
    func test_ordersNumericComponents() throws {
        XCTAssertLessThan(try XCTUnwrap(EchoAppReleaseVersion("2.11.0")), try XCTUnwrap(EchoAppReleaseVersion("3.0.0")))
    }

    func test_ordersBetaBeforeReleaseCandidateBeforeStable() throws {
        let beta = try XCTUnwrap(EchoAppReleaseVersion("3.0.0-beta.2"))
        let releaseCandidate = try XCTUnwrap(EchoAppReleaseVersion("3.0.0-rc.1"))
        XCTAssertLessThan(beta, releaseCandidate)
        XCTAssertLessThan(releaseCandidate, try XCTUnwrap(EchoAppReleaseVersion("3.0.0")))
    }

    func test_ordersNumericPrereleaseIdentifiersNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(EchoAppReleaseVersion("3.0.0-beta.2")), try XCTUnwrap(EchoAppReleaseVersion("3.0.0-beta.10")))
    }

    func test_mapsExactReleaseToTagCliAndMarketingVersion() throws {
        let release = try XCTUnwrap(EchoAppReleaseVersion("3.0.0-rc.1"))
        XCTAssertEqual(release.gitTag, "3.0.0-rc.1")
        XCTAssertEqual(release.cliVersion, "3.0.0-rc.1")
        XCTAssertEqual(release.marketingVersion, "3.0.0")
    }

    func test_readsHistoricalAndCanonicalGitHubTags() throws {
        XCTAssertEqual(EchoAppReleaseVersion(githubReleaseTag: "2.11.0"), EchoAppReleaseVersion("2.11.0"))
        XCTAssertEqual(EchoAppReleaseVersion(githubReleaseTag: "2.9"), EchoAppReleaseVersion("2.9.0"))
        XCTAssertEqual(EchoAppReleaseVersion(githubReleaseTag: "v3.0.0-beta.1"), EchoAppReleaseVersion("3.0.0-beta.1"))
        XCTAssertNil(EchoAppReleaseVersion(githubReleaseTag: "2"))
        XCTAssertNil(EchoAppReleaseVersion(githubReleaseTag: "v2"))
    }

    func test_rejectsInvalidSemVer() {
        ["3.0", "03.0.0", "3.0.0-01", "3.0.0-", "3.0.0+", "3.0.0-alpha..1", "v3.0.0"].forEach {
            XCTAssertNil(EchoAppReleaseVersion($0))
        }
    }

    func test_followsPrereleasePrecedenceAndOrdersBuildMetadataDeterministically() throws {
        XCTAssertLessThan(try XCTUnwrap(EchoAppReleaseVersion("3.0.0-1")), try XCTUnwrap(EchoAppReleaseVersion("3.0.0-alpha")))
        let release = try XCTUnwrap(EchoAppReleaseVersion("3.0.0"))
        let firstBuild = try XCTUnwrap(EchoAppReleaseVersion("3.0.0+001"))
        let secondBuild = try XCTUnwrap(EchoAppReleaseVersion("3.0.0+build.2"))
        XCTAssertLessThan(release, firstBuild)
        XCTAssertLessThan(firstBuild, secondBuild)
        XCTAssertNotEqual(firstBuild, secondBuild)
    }

    func test_identifiesPrereleasesWithoutTreatingBuildMetadataAsPrerelease() throws {
        XCTAssertTrue(try XCTUnwrap(EchoAppReleaseVersion("3.0.0-rc.1")).isPrerelease)
        XCTAssertFalse(try XCTUnwrap(EchoAppReleaseVersion("3.0.0+build-meta")).isPrerelease)
    }

    func test_buildMetadataDoesNotChangePrecedenceButComparableRemainsTotalOrder() throws {
        let first = try XCTUnwrap(EchoAppReleaseVersion("3.0.0+a"))
        let second = try XCTUnwrap(EchoAppReleaseVersion("3.0.0+z"))
        XCTAssertFalse(first.hasHigherPrecedence(than: second))
        XCTAssertFalse(second.hasHigherPrecedence(than: first))
        XCTAssertLessThan(first, second)
        XCTAssertNotEqual(first, second)
    }

    func test_buildMetadataDoesNotTriggerAnUpdate() async throws {
        let service = RealAppUpdateService(
            appUpdateSource: StubUpdateSource(release: Release(version: "3.0.0+z")),
            currentVersion: try XCTUnwrap(EchoAppReleaseVersion("3.0.0+a"))
        )
        let update = try await service.checkForUpdates()
        XCTAssertNil(update)
    }

    func test_prereleaseCurrentVersionUpdatesToMatchingStableRelease() async throws {
        let service = RealAppUpdateService(
            appUpdateSource: StubUpdateSource(release: Release(version: "3.0.0")),
            currentVersion: try XCTUnwrap(EchoAppReleaseVersion("3.0.0-rc.1"))
        )

        let update = try await service.checkForUpdates()

        XCTAssertEqual(update?.version, "3.0.0")
    }

    func test_stableClientsUseStableFeedAndIgnorePublishedPrereleases() throws {
        let currentVersion = try XCTUnwrap(EchoAppReleaseVersion("3.0.0"))
        XCTAssertEqual(GitHubReleasesUpdateSource.releaseFeed(for: currentVersion), .stable)

        let selected = try GitHubReleasesUpdateSource.latestRelease(
            from: [
                release(tag: "3.1.0-rc.1", prerelease: true),
                release(tag: "3.0.1"),
            ],
            feed: .stable
        )

        XCTAssertEqual(selected.tag_name, "3.0.1")
    }

    func test_stableClientsSelectMaximumSemVerWhenReleasesAreOutOfOrder() throws {
        let selected = try GitHubReleasesUpdateSource.latestRelease(
            from: [
                release(tag: "3.1.1"),
                release(tag: "3.2.0"),
                release(tag: "3.3.0", draft: true),
                release(tag: "not-a-version"),
            ],
            feed: .stable
        )

        XCTAssertEqual(selected.tag_name, "3.2.0")
    }

    func test_releaseSelectionPreservesFeedOrderForEqualPrecedence() throws {
        let selected = try GitHubReleasesUpdateSource.latestRelease(
            from: [release(tag: "3.0.0+a"), release(tag: "3.0.0+z")],
            feed: .stable
        )
        XCTAssertEqual(selected.tag_name, "3.0.0+a")
    }

    func test_prereleaseClientsUsePrereleaseFeedAndDiscoverPublishedPrereleases() throws {
        let currentVersion = try XCTUnwrap(EchoAppReleaseVersion("3.0.0-rc.1"))
        XCTAssertEqual(GitHubReleasesUpdateSource.releaseFeed(for: currentVersion), .prerelease)

        let selected = try GitHubReleasesUpdateSource.latestRelease(
            from: [
                release(tag: "3.0.0-rc.2", prerelease: true),
                release(tag: "3.0.0-rc.3", prerelease: true, draft: true),
                release(tag: "2.9.0"),
            ],
            feed: .prerelease
        )

        XCTAssertEqual(selected.tag_name, "3.0.0-rc.2")
    }

    private func release(tag: String, prerelease: Bool = false, draft: Bool = false) -> GitHubReleasesUpdateSource.GitHubRelease {
        GitHubReleasesUpdateSource.GitHubRelease(
            tag_name: tag,
            name: nil,
            body: nil,
            draft: draft,
            prerelease: prerelease
        )
    }
}

private struct StubUpdateSource: AppUpdateSource {
    let release: Release?

    var isAvailable: Bool { true }

    func checkForUpdates() async throws -> Release? {
        release
    }

    func performUpdate(release: Release) async throws -> AppUpdateSourceRedirectAction {
        AppUpdateSourceRedirectAction(message: "", buttonTitle: "", url: "")
    }
}
