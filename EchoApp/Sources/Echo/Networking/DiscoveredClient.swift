import EchoConnection

enum DiscoveredClient: Equatable {
    enum Kind: String, Hashable {
        case bonjour = "Bonjour"
        case adb = "ADB"
    }

    case bonjour(BonjourService)
    case adb(ADB.Device)

    var name: String {
        switch self {
        case let .bonjour(service):
            service.name

        case let .adb(device):
            device.name
        }
    }

    var kind: Kind {
        switch self {
        case .bonjour: .bonjour
        case .adb: .adb
        }
    }

    var transport: String {
        kind.rawValue.lowercased()
    }

    var platform: String {
        switch self {
        case let .bonjour(service):
            service.isAndroidEmulator ? "android" : "apple"
        case .adb:
            "android"
        }
    }
}
