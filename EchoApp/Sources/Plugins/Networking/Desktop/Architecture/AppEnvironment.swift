import AppKit

/// Contains global app dependencies
public struct AppEnvironment {
    public var appStateArchiver: AppStateArchiver
    public var fixturesRepo: FixturesRepo
    public var pasteboard: NSPasteboard

    /// Opens URLs in the user's default web browser
    public var urlOpener: (URL) -> Void

    public init(
        appStateArchiver: AppStateArchiver = AppStateDiskArchiver(),
        fixturesRepo: FixturesRepo = .init(),
        pasteboard: NSPasteboard = .general,
        urlOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.appStateArchiver = appStateArchiver
        self.fixturesRepo = fixturesRepo
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener
    }
}
