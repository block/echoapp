import Foundation

struct DebugPayload: Equatable, Identifiable {
    let id = UUID()
    let time = Date()
    let pluginID: String
    let prettyData: String
    let prefixData: String
}
