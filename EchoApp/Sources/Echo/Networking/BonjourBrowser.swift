import Network
import os

/// Continuously browses for Bonjour services.
final class BonjourBrowser {

    // MARK: - Private Properties

    private let serviceType: String
    private let adbProvider: () -> ADB?
    private var browser: NWBrowser?
    private let logger = Logger.echoLogger(category: "BonjourBrowser")
    private let discoveredServicesContinuation: AsyncStream<[BonjourService]>.Continuation
    private let errorContinuation: AsyncStream<ConnectionError>.Continuation

    // MARK: - Public Properties

    let discoveredServices: AsyncStream<[BonjourService]>
    let errors: AsyncStream<ConnectionError>

    // MARK: - Life Cycle

    init(
        serviceType: String,
        adbProvider: @escaping () -> ADB?
    ) {
        self.serviceType = serviceType
        self.adbProvider = adbProvider

        let errors = AsyncStream.makeStream(of: ConnectionError.self)
        self.errors = errors.stream
        self.errorContinuation = errors.continuation

        let discoveredServices = AsyncStream.makeStream(of: [BonjourService].self)
        self.discoveredServices = discoveredServices.stream
        self.discoveredServicesContinuation = discoveredServices.continuation
    }

    deinit {
        browser?.cancel()
        discoveredServicesContinuation.finish()
        errorContinuation.finish()
    }

    // MARK: - Public Methods

    func start() {
        guard browser == nil else { return }
        startBrowser()
    }

    func refreshServices() {
        browser?.cancel()
        browser = nil
        discoveredServicesContinuation.yield([])
        startBrowser()
    }

    // MARK: - Private Methods

    private func startBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true // TODO: - needed?

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [errorContinuation] state in
            if case let .failed(error) = state {
                let connectionError = ConnectionError.browseFailed(underlyingError: error.localizedDescription)
                errorContinuation.yield(connectionError)
            }
        }
        browser.browseResultsChangedHandler = { [adbProvider, discoveredServicesContinuation] results, _ in
            let bonjourServices = results.compactMap { result in
                BonjourService(result, adbProvider: adbProvider)
            }
            discoveredServicesContinuation.yield(bonjourServices)
        }

        self.browser = browser
        browser.start(queue: .main)
    }
}

// MARK: -

private extension BonjourService {

    /// echo-android advertises a bonjour service with this suffix
    static let androidEmulatorBonjourServiceSuffix = ":android_emulator"

    /// Map NWBrowser.Result to Echo's BonjourService type
    init?(_ result: NWBrowser.Result, adbProvider: @escaping () -> ADB?) {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return nil
        }
        
        var deviceName: String? = nil
        if case let .bonjour(txtRecord) = result.metadata {
            deviceName = txtRecord["device_name"]
        }

        var bonjourService = BonjourService(
            endpoint: result.endpoint,
            name: name,
            displayName: deviceName,
            adbProvider: adbProvider
        )

        if (name.contains(Self.androidEmulatorBonjourServiceSuffix)) {
            // For Android emulators, use the known emulator host and port
            bonjourService.endpoint = NWEndpoint.hostPort(
                host: .init(ADB.emulatorHost),
                port: .init(rawValue: ADB.emulatorPort)!
            )
            // and strip the ":android_emulator" suffix for readability
            bonjourService.name = name.components(separatedBy: ":").first ?? name
        }

        self = bonjourService
    }
}
