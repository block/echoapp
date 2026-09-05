import EchoConnection
import EchoPluginAPI
import Foundation

extension ClientServerConnection {
    func sendPluginLifecycleEvent(_ event: ClientPluginLifecycleEvent, pluginID: String) throws {
        let data = try JSONEncoder().encode(event)
        try send(PluginPayload(pluginID: pluginID, data: data))
    }
}
