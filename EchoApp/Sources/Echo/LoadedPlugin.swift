import EchoPluginAPI
import SwiftUI
import Combine

@dynamicMemberLookup
final class LoadedPlugin: Equatable, Identifiable {
    // MARK: - Properties
    
    /// The framework or dylib this plugin was loaded from, or `nil` if bundled with Echo
    let framework: FrameworkPlugin?
    let plugin: DesktopPlugin
    
    // MARK: - Initialization
    
    init(framework: FrameworkPlugin?, plugin: DesktopPlugin) {
        self.framework = framework
        self.plugin = plugin
    }
    
    // MARK: - Identifiable
    
    var id: PluginIdentifier {
        plugin.metadata.id
    }
    
    // MARK: - Dynamic Member Lookup
    
    subscript<T>(dynamicMember keyPath: KeyPath<DesktopPlugin, T>) -> T {
        plugin[keyPath: keyPath]
    }

    subscript<T>(dynamicMember keyPath: KeyPath<DesktopPluginMetadata, T>) -> T {
        plugin.metadata[keyPath: keyPath]
    }
}

// MARK: - Plugin Connection

extension LoadedPlugin {
    public func onConnect(_ connection: PluginConnection) {
        plugin.onConnect(connection)
    }

    public func onDisconnect() {
        plugin.onDisconnect()
    }
}

// MARK: - Equatable

extension LoadedPlugin {
    static func == (lhs: LoadedPlugin, rhs: LoadedPlugin) -> Bool {
        lhs.plugin.metadata.id == rhs.plugin.metadata.id
    }
}
