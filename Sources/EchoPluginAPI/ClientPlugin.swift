/**
 Represents a client-side plugin within the Echo app.
 This protocol outlines the requirements for client plugins, including their unique identifiers and lifecycle event handling.
 */
public protocol ClientPlugin {
    /// A unique identifier for the plugin.
    var id: PluginIdentifier { get }

    /// The version number of the client plugin, conforming to Semantic Versioning principles.
    /// This version should be updated following major, minor, or patch changes to maintain compatibility with corresponding DesktopPlugin versions.
    var version: String { get }

    /// Called when a connection with the corresponding DesktopPlugin is established.
    @MainActor
    func onConnect(_ connection: PluginConnection)

    /// Called when the connection with the corresponding DesktopPlugin is disconnected.
    @MainActor
    func onDisconnect()

    /// Called when the corresponding DesktopPlugin becomes active.
    @MainActor
    func onDesktopPluginActive()

    /// Called when the corresponding DesktopPlugin becomes inactive.
    @MainActor
    func onDesktopPluginInactive()
}

/// Provides default implementations for optional lifecycle methods in `ClientPlugin`.
public extension ClientPlugin {
    /// Default implementation for when the DesktopPlugin becomes active. Override if needed.
    @MainActor
    func onDesktopPluginActive() {}

    /// Default implementation for when the DesktopPlugin becomes inactive. Override if needed.
    @MainActor
    func onDesktopPluginInactive() {}
}

/**
 Enumerates the lifecycle events of a DesktopPlugin as observed by a ClientPlugin.
 These events are used as payload messages from the Echo app to the EchoClient.
 */
public enum ClientPluginLifecycleEvent: String, Codable {
    case active = "ClientPluginLifecycleEvent.onDesktopPluginActive"
    case inactive = "ClientPluginLifecycleEvent.onDesktopPluginInactive"
}
