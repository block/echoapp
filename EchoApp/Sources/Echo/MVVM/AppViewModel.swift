import AppKit
import EchoConnection
import EchoPluginAPI
import Foundation
import Observation
import os

// MARK: - App View Model

@dynamicMemberLookup
@MainActor
@Observable
final class AppViewModel {
    private let environment: AppEnvironment
    private let sessionBuilder: any SessionViewModelBuilding
    private let logger = Logger(subsystem: "xyz.block.echoapp", category: "AppViewModel")

    private(set) var state = AppState()
    private(set) var sessions: [UUID: SessionViewModel] = [:]
    private(set) var activeSessionID: UUID?
    private let basePort: Int
    private let cliSessionMonitor = CLISessionMonitor()

    @ObservationIgnored private var updateTask: Task<Void, Never>?

    init(
        environment: AppEnvironment,
        sessionBuilder: any SessionViewModelBuilding,
        initialPort: Int = 34143
    ) {
        self.environment = environment
        self.sessionBuilder = sessionBuilder
        self.basePort = initialPort
    }

    convenience init(
        sessionBuilder: any SessionViewModelBuilding,
        initialPort: Int = 34143
    ) {
        self.init(
            environment: AppEnvironment(),
            sessionBuilder: sessionBuilder,
            initialPort: initialPort
        )
    }

    convenience init(
        pluginFrameworks: [FrameworkPlugin],
        initialPort: Int = 34143
    ) {
        let environment = AppEnvironment(pluginFrameworks: pluginFrameworks)
        self.init(
            environment: environment,
            sessionBuilder: LiveSessionViewModelBuilder(pluginFrameworks: pluginFrameworks),
            initialPort: initialPort
        )
    }

    subscript<T>(dynamicMember keyPath: KeyPath<AppState, T>) -> T {
        state[keyPath: keyPath]
    }

    // MARK: - Session Management

    @discardableResult
    func createSession(
        initialClient: DiscoveredClient? = nil,
        sessionID: UUID,
        isImportedArchive: Bool = false,
        archiveURL: URL? = nil
    ) -> SessionViewModel {
        if let existingSession = sessions[sessionID] {
            return existingSession
        }

        let session = sessionBuilder.makeSession(
            sessionID: sessionID,
            port: nextPort(),
            initialClient: initialClient,
            isImportedArchive: isImportedArchive,
            archiveURL: archiveURL,
            onDebugPayload: { [weak self] payload in
                self?.recordDebugPayload(payload)
            }
        )

        sessions[sessionID] = session
        activeSessionID = sessionID
        session.start()
        processPendingDeepLinks(for: session)
        return session
    }

    func destroySession(_ sessionID: UUID) {
        sessions.removeValue(forKey: sessionID)
        if activeSessionID == sessionID {
            activeSessionID = sessions.keys.sorted().first
        }
    }

    func setActiveSession(_ sessionID: UUID) {
        guard sessions[sessionID] != nil else { return }
        activeSessionID = sessionID
    }

    func session(for sessionID: UUID) -> SessionViewModel? {
        sessions[sessionID]
    }

    var activeSession: SessionViewModel? {
        guard let activeSessionID else { return nil }
        return sessions[activeSessionID]
    }

    var activeCLISessions: [CLISession] {
        cliSessionMonitor.activeCLISessions
    }

    @discardableResult
    func openCLISession(_ cliSession: CLISession) -> UUID {
        let sessionID = UUID()
        let sessionDir = URL(fileURLWithPath: cliSession.sessionPath)

        let session = sessionBuilder.makeFileBackedSession(
            sessionID: sessionID,
            sessionDir: sessionDir,
            deviceName: cliSession.deviceName,
            onDebugPayload: { [weak self] payload in
                self?.recordDebugPayload(payload)
            }
        )

        sessions[sessionID] = session
        activeSessionID = sessionID
        session.start()
        return sessionID
    }

    func enqueuePendingDeepLinks(_ urls: [URL]) {
        state.pendingDeepLinkURLs.append(contentsOf: urls.filter { $0.scheme == "echo" })
    }

    // MARK: - Updates

    func checkForUpdatesAtLaunch() {
        checkForUpdates(isUserInitiated: false)
    }

    func startCLISessionMonitoring() {
        cliSessionMonitor.startMonitoring()
    }

    func checkForUpdates() {
        checkForUpdates(isUserInitiated: true)
    }

    func dismissUpdateAlert() {
        state.updateState.showingUpdateAlert = nil
    }

    func performUpdate() {
        guard let release = state.updateState.availableUpdate else {
            state.updateState.showingUpdateAlert = .updateError("No update available")
            return
        }

        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let redirectAction = try await self.environment.updateService.performUpdate(release: release)
                self.state.updateState.showingUpdateAlert = .updateRedirect(
                    message: redirectAction.message,
                    buttonTitle: redirectAction.buttonTitle,
                    url: redirectAction.url
                )
            } catch {
                self.state.updateState.showingUpdateAlert = .updateError(error.localizedDescription)
            }
        }
    }

    // MARK: - Firewall

    func updateFirewallState() {
        do {
            let enabled = try environment.firewallDaemon.iOSFirewallExceptionsEnabled()
            state.firewallState = .known(exceptionsEnabled: enabled)
        } catch {
            logger.error("Failed to determine firewall state: \(error.localizedDescription)")
            state.firewallState = .unknown
            if let session = activeSession {
                session.showError(ErrorState(FirewallError.stateError(error)))
            }
        }
    }

    func toggleFirewallExceptions() {
        do {
            try environment.firewallDaemon.toggleIOSFirewallExceptions()
            updateFirewallState()
        } catch {
            logger.error("Failed to toggle firewall exceptions: \(error.localizedDescription)")
            if let session = activeSession {
                session.showError(ErrorState(FirewallError.toggleFailed(error)))
            }
        }
    }

    // MARK: - Debugger

    func setDebuggerEnabled(_ enabled: Bool) {
        state.debuggerState.isEnabled = enabled
        if !enabled {
            clearDebuggerPayloads()
        } else {
            AnalyticsProvider.shared.trackDebuggerOpened()
        }
    }

    func clearDebuggerPayloads() {
        state.debuggerState.debugPayloads = []
        state.debuggerState.selectedPayloadId = nil
    }

    func setDebuggerSearchText(_ text: String) {
        state.debuggerState.searchText = text
    }

    func setMessageLimit(_ limit: Int) {
        state.debuggerState.messageLimit = max(1, limit)
    }

    func setPluginFilter(_ pluginID: String?) {
        state.debuggerState.selectedPluginFilter = pluginID
    }

    func setDebuggerPaused(_ isPaused: Bool) {
        state.debuggerState.isPaused = isPaused
    }

    func selectPayload(_ payloadID: UUID?) {
        state.debuggerState.selectedPayloadId = payloadID
    }

    // MARK: - Private

    private func checkForUpdates(isUserInitiated: Bool) {
        #if DEBUG
        if !isUserInitiated {
            logger.info("Skipping automatic update check in debug build")
            return
        }
        #endif

        guard !state.updateState.isCheckingForUpdates else {
            logger.info("Update check already in progress")
            return
        }

        state.updateState.isCheckingForUpdates = true
        state.updateState.updateError = nil

        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let latestRelease = try await self.environment.updateService.checkForUpdates()
                self.handleUpdateCheckCompleted(.success(latestRelease), isUserInitiated: isUserInitiated)
            } catch {
                let updateError = error as? UpdateError ?? .networkError("Update check failed: \(error.localizedDescription)")
                self.handleUpdateCheckCompleted(.failure(updateError), isUserInitiated: isUserInitiated)
            }
        }
    }

    private func handleUpdateCheckCompleted(
        _ result: Result<Release?, UpdateError>,
        isUserInitiated: Bool
    ) {
        state.updateState.isCheckingForUpdates = false

        switch result {
        case let .success(release):
            if let release {
                state.updateState.availableUpdate = release
                logger.info("Update available: \(release.version)")
            } else {
                state.updateState.availableUpdate = nil
                if isUserInitiated && state.updateState.showingUpdateAlert == nil {
                    state.updateState.showingUpdateAlert = .noUpdatesAvailable
                }
            }
        case let .failure(error):
            state.updateState.updateError = error.localizedDescription
            logger.error("Update check failed: \(error.localizedDescription)")
            state.updateState.showingUpdateAlert = .updateError(error.localizedDescription)
        }
    }

    private func recordDebugPayload(_ payload: DebugPayload) {
        guard state.debuggerState.isEnabled, !state.debuggerState.isPaused else { return }
        state.debuggerState.debugPayloads = [payload] + state.debuggerState.debugPayloads
    }

    private func processPendingDeepLinks(for session: SessionViewModel) {
        guard !state.pendingDeepLinkURLs.isEmpty else { return }
        let pending = state.pendingDeepLinkURLs
        state.pendingDeepLinkURLs.removeAll()
        for url in pending where url.scheme == "echo" {
            session.handleDeepLink(url)
        }
    }

    private func nextPort() -> Int {
        let usedPorts = Set(sessions.values.map { $0.state.port })
        var port = basePort
        while usedPorts.contains(port) {
            port += 1
        }
        return port
    }
}
