import EchoPluginAPI
import Foundation

/// Connection stages reported to analytics.
public enum AnalyticsConnectionStage: String {
    case request
    case websocket
}

/// Connection outcomes reported to analytics.
public enum AnalyticsConnectionOutcome: String {
    case started
    case sent
    case connected
}

/// Seam for product analytics. The public app installs the no-op
/// implementation below; internal distributions may inject their own
/// implementation via `AnalyticsProvider.shared` at startup.
public protocol EchoAnalytics {
    func trackPluginOpened(metadata: DesktopPluginMetadata)
    func trackPluginViewed(metadata: DesktopPluginMetadata)
    func trackPluginsReset()
    func trackPluginSettingsViewed()
    func trackPluginInstalled(pluginId: String)
    func trackPluginLoadFailed(type: String, errorMessage: String, path: String)
    func trackDebuggerOpened()
    func trackClientSelected(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String
    )
    func trackClientConnectionStage(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String,
        stage: AnalyticsConnectionStage,
        outcome: AnalyticsConnectionOutcome,
        duration: TimeInterval?
    )
    func trackClientConnectionSucceeded(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String,
        duration: TimeInterval
    )
    func trackClientConnectionFailed(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String,
        stage: AnalyticsConnectionStage,
        duration: TimeInterval,
        error: Error
    )
    func trackClientConnectedToAppIdentifier(
        appId: String,
        availablePlugins: [PluginIdentifier]
    )
    func trackUpdateChecked(
        installationMethod: String,
        currentVersion: String,
        newVersion: String,
        source: String
    )
    func trackUpdatePerformed(
        installationMethod: String,
        currentVersion: String,
        newVersion: String,
        source: String
    )
}

/// Default analytics sink: does nothing. Public builds are telemetry-free.
public struct NoOpAnalytics: EchoAnalytics {
    public init() {}

    public func trackPluginOpened(metadata: DesktopPluginMetadata) {}
    public func trackPluginViewed(metadata: DesktopPluginMetadata) {}
    public func trackPluginsReset() {}
    public func trackPluginSettingsViewed() {}
    public func trackPluginInstalled(pluginId: String) {}
    public func trackPluginLoadFailed(type: String, errorMessage: String, path: String) {}
    public func trackDebuggerOpened() {}
    public func trackClientSelected(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String
    ) {}
    public func trackClientConnectionStage(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String,
        stage: AnalyticsConnectionStage,
        outcome: AnalyticsConnectionOutcome,
        duration: TimeInterval?
    ) {}
    public func trackClientConnectionSucceeded(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String,
        duration: TimeInterval
    ) {}
    public func trackClientConnectionFailed(
        clientId: String,
        transport: String,
        platform: String,
        attemptId: String,
        stage: AnalyticsConnectionStage,
        duration: TimeInterval,
        error: Error
    ) {}
    public func trackClientConnectedToAppIdentifier(
        appId: String,
        availablePlugins: [PluginIdentifier]
    ) {}
    public func trackUpdateChecked(
        installationMethod: String,
        currentVersion: String,
        newVersion: String,
        source: String
    ) {}
    public func trackUpdatePerformed(
        installationMethod: String,
        currentVersion: String,
        newVersion: String,
        source: String
    ) {}
}

/// Injection point for the app's analytics sink.
public enum AnalyticsProvider {
    public nonisolated(unsafe) static var shared: EchoAnalytics = NoOpAnalytics()
}

/// Maps errors to coarse type names that are safe to report (no payloads,
/// commands, or device details).
public enum AnalyticsErrorType {
    public static func connectionErrorType(_ error: Error) -> String {
        let typeName = String(reflecting: type(of: error))
        guard let adbError = error as? ADBError else { return typeName }

        let caseName = switch adbError {
        case .adbNotFound:
            "adbNotFound"
        case .adbDiscoveryFailed:
            "adbDiscoveryFailed"
        case .adbCommandFailed:
            "adbCommandFailed"
        }
        return "\(typeName).\(caseName)"
    }
}
