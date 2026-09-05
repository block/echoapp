import Foundation
import Network
import os

/// Continuously browses for devices using `adb`.
@MainActor
final class ADBBrowser {

    // MARK: - Private Properties

    private let adbProvider: () -> ADB?
    private let logger = Logger.echoLogger(category: "ADBBrowser")
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?

    // MARK: - Public Properties

    let (discoveredDevices, discoveredDevicesContinuation) = AsyncStream.makeStream(of: Result<[ADB.Device], ADBError>.self)

    // MARK: - Life Cycle

    init(adbProvider: @escaping () -> ADB?) {
        self.adbProvider = adbProvider
    }

    // MARK: - Public Methods

    func refreshDevices() {
        guard let adb = adbProvider() else {
            discoveredDevicesContinuation.yield(.failure(.adbNotFound))
            return
        }
        refreshTask?.cancel()
        let refreshID = UUID()
        self.refreshID = refreshID
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.refreshID == refreshID {
                    self.refreshTask = nil
                    self.refreshID = nil
                }
            }
            let start = ContinuousClock.now
            do {
                logger.debug("Refreshing Android devices with \(adb.path, privacy: .public)")
                let devices = try await adb.echoEnabledDevices()
                let duration = start.duration(to: .now)
                logger.info(
                    "ADB discovery found \(devices.count, privacy: .public) Echo device(s) in \(duration, privacy: .public)"
                )
                discoveredDevicesContinuation.yield(.success(devices))
            } catch {
                if error is CancellationError {
                    return
                }
                let adbError = error as? ADBError
                    ?? .adbDiscoveryFailed(underlyingError: error.localizedDescription)
                logger.error(
                    "ADB discovery failed: \(adbError.completeErrorDescription, privacy: .public)"
                )
                discoveredDevicesContinuation.yield(.failure(adbError))
            }
        }
    }
}
