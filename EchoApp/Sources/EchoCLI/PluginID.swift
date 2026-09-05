import Foundation

enum PluginID {
    /// Strips the domain prefix from a plugin ID.
    /// e.g., "com.echo.plugin.analytics" -> "analytics"
    static func sanitize(_ pluginID: String) -> String {
        let components = pluginID.split(separator: ".")
        if components.count > 1 {
            return String(components.last!)
        }
        return pluginID
    }
}
