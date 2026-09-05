
import EchoPluginAPI
import Foundation

/// A standard implementation of the "App Info" plugin
public final class AppInfoPlugin {
    public struct Entry: Codable {
        public var scope: String
        public var key: String
        public var value: String

        public init(scope: String, key: String, value: String) {
            self.scope = scope
            self.key = key
            self.value = value
        }
    }

    private var connection: PluginConnection?
    private let queue = DispatchQueue(label: "com.echo.plugin.appinfo")

    private var entries: [Entry] = []

    public init() {}

    // MARK: - Public API

    /// Sends the provided list of entries. All previous entries will be removed and replaced
    /// with the provided list.
    public func setEntries(_ entries: [Entry]) {
        queue.async {
            self.entries = entries
            self.sendLatestEntries()
        }
    }

    // MARK: -

    private func sendLatestEntries() {
        do {
            try connection?.send(entries)
        } catch {
            print("Echo: Error Sending App Info \(error)")
        }
    }
}

extension AppInfoPlugin: ClientPlugin {
    public static let id: PluginIdentifier = "com.echo.plugin.appinfo"

    public var id: PluginIdentifier { Self.id }
    public var version: String { "0.0.1" }

    public func onConnect(_ connection: PluginConnection) {
        self.connection = connection
        queue.async {
            self.sendLatestEntries()
        }
    }

    public func onDisconnect() {
        connection = nil
    }

    public func onDesktopPluginActive() {}
}
