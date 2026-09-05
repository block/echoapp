import EchoPluginAPI
import Foundation

///  Describes how the plugin should respond to an incoming request
public struct Rule: Codable, Hashable, Identifiable  {
    public var id = UUID()
    public var endpoint: Endpoint
    public var responsePolicy: ResponsePolicy
}
