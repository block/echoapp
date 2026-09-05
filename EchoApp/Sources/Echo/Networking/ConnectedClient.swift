import EchoConnection

/// Describes a client that is **currently connected** to Echo
struct ConnectedClient: Codable, Equatable {
    /// Uniquely identifies the connected device. Available as soon as the connection is established
    let deviceIdentifier: DeviceIdentifier

    /// A human-readable name for the connected device. Can be nil for older clients.
    let deviceName: String?
    
    /// Uniquely identifies the connected device's running app. Available as soon as the connection is established
    let appIdentifier: String

    /// Additional information about the client. Populated and updated async by the client
    var clientInfo: ClientInfoPayload?

    init(deviceIdentifier: DeviceIdentifier, deviceName: String?, appIdentifier: String) {
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.appIdentifier = appIdentifier
        self.clientInfo = nil
    }
}

