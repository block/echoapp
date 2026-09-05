
#if os(iOS)
import UIKit
#elseif os(macOS)
import Foundation
#endif

/// A human-readable identifier for a device (non-unique)
/// E.g. 'Jack's Macbook Pro'
public struct DeviceIdentifier: Codable, Equatable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static var current: Self {
#if os(iOS)
        let device = UIDevice.current
        return .init(value: "\(device.name) (iOS \(device.systemVersion))")
#elseif os(macOS)
        let processInfo = ProcessInfo.processInfo
        return .init(value: "\(processInfo.hostName) (\(processInfo.operatingSystemVersionString)")
#endif
    }
}
