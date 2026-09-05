import Foundation

struct Snapshot: Codable {
    var imageData: Data
    var elements: [AccessibilityElement]
}
