import Foundation

/// Window identifiers for use with `openWindow` and `WindowGroup` APIs.
enum WindowID {
    static let plugin = "plugin-popout"
    static let payloadDB = "payload-debugger"
    static let quickLaunch = "quick-launch"
}

struct SessionWindow: Hashable, Codable {
    var id: UUID
}
