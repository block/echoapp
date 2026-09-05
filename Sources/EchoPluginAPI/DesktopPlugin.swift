#if os(macOS)
import SwiftUI

/**
 Represents a desktop plugin conforming to this protocol for the Echo app on macOS.
 Plugins implementing this protocol can provide a custom view, handle connections,
 and have associated metadata.
 */
public protocol DesktopPlugin: AnyObject {

    /// Initializes the plugin.
    init()

    /// Metadata containing essential information about the plugin.
    var metadata: DesktopPluginMetadata { get }

    /// Creates and returns the plugin's view.
    func makeView() -> AnyView

    /// Called when a plugin connection is established.
    func onConnect(_ connection: PluginConnection)
    /// Called when a plugin connection is disconnected.
    func onDisconnect()
}

/**
 Base class for providing plugins.
 Subclasses must override `providePluginTypes` to supply the actual plugin types.
 */
public protocol DeepLinkHandler: AnyObject {

    /// For handling deeplinks that take the form `echo://plugin/{plugin_id}/`
    /// For example: `echo://plugin/com.echo.plugin.networking/search?query="get-app-config"`
    func handleDeepLink(path: String, queryItems: [URLQueryItem]) -> Bool
}

public extension [URLQueryItem] {
    func unquotedValue(forKey key: String) -> String? {
        let value = first(where: { $0.name == key })?.value
        return value?.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }
}

/**
 Base class for providing plugins.
 Subclasses must override `providePluginTypes` to supply the actual plugin types.
 */
open class PluginProvider {

    /// Initializes a new plugin provider.
    public init() {}

    /// Must be overridden to return an array of `DesktopPlugin.Type`.
    /// Calling this method without an override will result in a runtime error.
    open func providePluginTypes() -> [any DesktopPlugin.Type] {
        fatalError("You must override this method.")
    }
}

#endif
