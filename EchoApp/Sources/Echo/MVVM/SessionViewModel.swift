import AppKit
import Combine
import EchoConnection
import EchoMCP
import EchoPluginAPI
import Foundation
import Observation
import SwiftUI
import os

@MainActor
private final class ConnectionAttempt {
    let id: UUID
    let client: DiscoveredClient
    let startedAt = Date()
    var lastStage = AnalyticsConnectionStage.request

    init(id: UUID, client: DiscoveredClient) {
        self.id = id
        self.client = client
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}

// MARK: - Session View Model

@dynamicMemberLookup
@MainActor
@Observable
final class SessionViewModel {
    var state: SessionState

    private let environment: SessionEnvironment
    private let logger = Logger(subsystem: "xyz.block.echoapp", category: "SessionViewModel")
    private let onDebugPayload: @MainActor (DebugPayload) -> Void

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeConnectionID: UUID?
    @ObservationIgnored private var activeConnection: (any ClientServerConnection)?
    @ObservationIgnored private let androidTunnelOwnership = AndroidTunnelOwnership()
    @ObservationIgnored private var pendingConnectionIdentifier: String?
    @ObservationIgnored private var connectionRequestID: UUID?
    @ObservationIgnored private var connectionRequestTask: Task<Void, Never>?
    @ObservationIgnored private var mcpServer: MCPServer?
    @ObservationIgnored private let sessionFileCache: SessionFileCache

    init(
        initialState: SessionState,
        environment: SessionEnvironment,
        sessionFileCache: SessionFileCache = SessionFileCache(),
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) {
        self.state = initialState
        self.environment = environment
        self.sessionFileCache = sessionFileCache
        self.onDebugPayload = onDebugPayload
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
        connectionRequestTask?.cancel()
        androidTunnelOwnership.close()
    }

    var id: UUID { state.id }
    var port: Int { state.port }
    var pluginManager: DesktopPluginManager { state.pluginManager }

    subscript<T>(dynamicMember keyPath: KeyPath<SessionState, T>) -> T {
        state[keyPath: keyPath]
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        state.shouldAutoReconnect = shouldAutoReconnect
        let initialClient = state.initialClient
        state.initialClient = nil

        Task { [weak self] in
            guard let self else { return }
            if !self.state.isImportedArchive {
                await PluginMessageCache.shared.clearCacheOnStartup()
            }

            do {
                try self.environment.server.start()
            } catch {
                self.logger.fault("Failed to start server: \(error.localizedDescription)")
                self.showError(ErrorState(LifecycleError.serverStartFailed(underlyingError: error.localizedDescription)))
                return
            }

            self.loadPlugins()
            self.monitorConnectionLifecycle()
            self.browseForClients()

            if let initialClient {
                self.selectClient(initialClient)
            }
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func restart() {
        environment.applicationReloader.reload()
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func handleDeepLink(_ url: URL) {
        guard url.host == "plugin",
              let pluginID = url.path().split(separator: "/").first.map(String.init)
        else {
            return
        }

        let fullPath = url.path()
        let pathComponents = fullPath.split(separator: "/")
        guard pathComponents.count > 1 else {
            return
        }

        guard let plugin = state.loadedPlugins[id: pluginID]?.plugin else {
            state.pendingDeepLink = url
            return
        }
        state.pendingDeepLink = nil

        if state.connectedClient == nil {
            state.pendingDeepLink = url
            state.autoConnectToFirstAvailable = true
            connectToFirstAvailable()
            return
        }

        navigateToScreen(.main)
        selectPlugin(pluginID)

        let pluginPath = pathComponents.dropFirst().joined(separator: "/")
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let deeplinkHandler = plugin as? DeepLinkHandler {
            _ = deeplinkHandler.handleDeepLink(path: pluginPath, queryItems: queryItems)
        }
    }

    // MARK: - Navigation & UI

    func showQuickLaunchPanel(_ show: Bool) {
        state.isShowingPluginQuickLaunchView = show
    }

    func navigateToScreen(_ screen: SessionState.NavigationScreen) {
        state.currentScreen = screen
        if screen == .clientPicker {
            environment.adbBrowser.refreshDevices()
            state.selectedPlugin = nil
        }
    }

    func showError(_ errorState: ErrorState) {
        state.errorState = errorState
    }

    func dismissError() {
        state.errorState = nil
    }

    func showExportPanel(selectedOnly: Bool) {
        let loadedPlugins = state.loadedPlugins
        let selectedPlugin = state.selectedPlugin?.value

        Task { [weak self] in
            guard let self else { return }
            let messageCache = PluginMessageCache.shared
            var pluginData: [PluginExportTable.PluginData] = []

            if selectedOnly, let selectedPlugin {
                if let count = try? await messageCache.getCachedData(for: selectedPlugin.id).count {
                    pluginData.append(
                        .init(
                            id: selectedPlugin.id,
                            plugin: selectedPlugin,
                            messageCount: count,
                            isSelected: count > 0
                        )
                    )
                }
            } else {
                for plugin in loadedPlugins {
                    if let count = try? await messageCache.getCachedData(for: plugin.id).count {
                        pluginData.append(
                            .init(
                                id: plugin.id,
                                plugin: plugin,
                                messageCount: count,
                                isSelected: count > 0
                            )
                        )
                    }
                }
            }

            self.state.exportState.pluginData = pluginData.sorted { $0.messageCount > $1.messageCount }
            self.state.exportState.isShowingSavePanel = true
            self.state.exportState.selectedPluginId = selectedOnly ? selectedPlugin?.id : nil
        }
    }

    func updateExportPluginSelection(pluginID: String, isSelected: Bool) {
        guard let index = state.exportState.pluginData.firstIndex(where: { $0.id == pluginID }) else { return }
        state.exportState.pluginData[index].isSelected = isSelected
    }

    func dismissExport() {
        state.exportState.isShowingSavePanel = false
        state.exportState.selectedPluginId = nil
        state.exportState.error = nil
    }

    func handleExport(_ url: URL) {
        let pluginsToExport = state.exportState.pluginData
            .filter { $0.isSelected && $0.messageCount > 0 }
            .map { $0.plugin.id }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await PluginMessageCache.shared.exportData(for: pluginsToExport, to: url)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                self.state.exportState.isShowingSavePanel = false
                self.state.exportState.error = nil
            } catch {
                self.state.exportState.error = error.localizedDescription
            }
        }
    }

    // MARK: - Client

    func browseForClients() {
        state.shouldAutoReconnect = shouldAutoReconnect
        environment.clientBrowser.start()
        environment.adbBrowser.refreshDevices()

        setTask(
            key: "bonjourServices",
            Task { [weak self] in
                guard let self else { return }
                for await updatedClients in self.environment.clientBrowser.discoveredServices {
                    self.updateAvailableBonjourClients(updatedClients)
                }
            }
        )

        setTask(
            key: "bonjourErrors",
            Task { [weak self] in
                guard let self else { return }
                for await error in self.environment.clientBrowser.errors {
                    self.showError(ErrorState(ClientError.clientDiscoveryFailed(error)))
                }
            }
        )

        setTask(
            key: "adbDevices",
            Task { [weak self] in
                guard let self else { return }
                for await updatedDevices in self.environment.adbBrowser.discoveredDevices {
                    self.updateAvailableADBClients(updatedDevices)
                }
            }
        )

        setTask(
            key: "adbRefresh",
            Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    self.environment.adbBrowser.refreshDevices()
                }
            }
        )
    }

    func refreshADBDevices() {
        environment.adbBrowser.refreshDevices()
    }

    func refreshBonjourDevices() {
        environment.clientBrowser.refreshServices()
    }

    func refreshAvailableClients() {
        refreshBonjourDevices()
        refreshADBDevices()
    }

    func selectClient(_ client: DiscoveredClient) {
        if state.pendingConnectionClient == client {
            return
        }

        connectionRequestTask?.cancel()

        let connectionAttempt = ConnectionAttempt(id: UUID(), client: client)
        connectionRequestID = connectionAttempt.id
        pendingConnectionIdentifier = nil
        environment.server.beginExpectingConnection()
        state.pendingConnectionClient = client
        state.lastConnectedClient = client
        AnalyticsProvider.shared.trackClientSelected(
            clientId: connectionAttempt.client.name,
            transport: connectionAttempt.client.transport,
            platform: connectionAttempt.client.platform,
            attemptId: connectionAttempt.id.uuidString
        )

        connectionRequestTask = Task { [weak self] in
            guard let self else { return }
            var pendingAndroidTunnel: AndroidTunnel?
            defer {
                pendingAndroidTunnel?.close()
                if self.connectionRequestID == connectionAttempt.id {
                    self.pendingConnectionIdentifier = nil
                    self.connectionRequestID = nil
                    self.connectionRequestTask = nil
                    self.state.pendingConnectionClient = nil
                }
            }

            do {
                try Task.checkCancellation()
                let previousConnectionID = self.environment.server.currentConnection?.id
                AnalyticsProvider.shared.trackClientConnectionStage(
                    clientId: connectionAttempt.client.name,
                    transport: connectionAttempt.client.transport,
                    platform: connectionAttempt.client.platform,
                    attemptId: connectionAttempt.id.uuidString,
                    stage: .request,
                    outcome: .started,
                    duration: nil
                )
                let connectionRequest = ConnectionRequest(serverURL: self.environment.server.webSocketURL)
                let onRequestSent: @MainActor @Sendable () -> Void = { [weak self] in
                    guard let self,
                          self.connectionRequestID == connectionAttempt.id,
                          connectionAttempt.lastStage == .request else {
                        return
                    }
                    connectionAttempt.lastStage = .websocket
                    AnalyticsProvider.shared.trackClientConnectionStage(
                        clientId: connectionAttempt.client.name,
                        transport: connectionAttempt.client.transport,
                        platform: connectionAttempt.client.platform,
                        attemptId: connectionAttempt.id.uuidString,
                        stage: .request,
                        outcome: .sent,
                        duration: connectionAttempt.duration
                    )
                }
                switch connectionAttempt.client {
                case let .bonjour(service):
                    pendingAndroidTunnel = try await service.send(
                        connectionRequest,
                        onRequestSent: onRequestSent
                    ) {
                        guard self.connectionRequestID == connectionAttempt.id else { return }
                        self.pendingConnectionIdentifier = $0
                        self.environment.server.expectConnection(identifier: $0)
                    }
                case let .adb(device):
                    guard self.connectionRequestID == connectionAttempt.id else { throw CancellationError() }
                    guard let adb = self.environment.adbProvider() else {
                        throw ADBError.adbNotFound
                    }
                    self.pendingConnectionIdentifier = device.androidIdOrName
                    self.environment.server.expectConnection(identifier: device.androidIdOrName)
                    pendingAndroidTunnel = try await adb.send(
                        connectionRequest,
                        to: device,
                        onRequestSent: onRequestSent
                    )
                }
                try Task.checkCancellation()
                let expectedIdentifier = self.pendingConnectionIdentifier
                let connection = try await self.waitForClientConnection(
                    matching: expectedIdentifier,
                    after: previousConnectionID,
                    timeout: 10
                )
                try await self.waitForLifecycleOwnership(of: connection.id, timeout: 10)
                AnalyticsProvider.shared.trackClientConnectionStage(
                    clientId: connectionAttempt.client.name,
                    transport: connectionAttempt.client.transport,
                    platform: connectionAttempt.client.platform,
                    attemptId: connectionAttempt.id.uuidString,
                    stage: .websocket,
                    outcome: .connected,
                    duration: connectionAttempt.duration
                )
                try self.androidTunnelOwnership.transfer(
                    pendingAndroidTunnel,
                    connectionID: connection.id,
                    activeConnectionID: self.activeConnectionID
                )
                pendingAndroidTunnel = nil
                AnalyticsProvider.shared.trackClientConnectionSucceeded(
                    clientId: connectionAttempt.client.name,
                    transport: connectionAttempt.client.transport,
                    platform: connectionAttempt.client.platform,
                    attemptId: connectionAttempt.id.uuidString,
                    duration: connectionAttempt.duration
                )
            } catch is CancellationError {
                if self.connectionRequestID == connectionAttempt.id {
                    self.environment.server.expectConnection(identifier: nil)
                }
                return
            } catch {
                if self.connectionRequestID == connectionAttempt.id {
                    self.environment.server.expectConnection(identifier: nil)
                }
                self.logger.error(
                    "Error connecting to client \(connectionAttempt.client.name): \(error.localizedDescription)"
                )
                AnalyticsProvider.shared.trackClientConnectionFailed(
                    clientId: connectionAttempt.client.name,
                    transport: connectionAttempt.client.transport,
                    platform: connectionAttempt.client.platform,
                    attemptId: connectionAttempt.id.uuidString,
                    stage: connectionAttempt.lastStage,
                    duration: connectionAttempt.duration,
                    error: error
                )
                self.showError(
                    ErrorState(
                        ClientError.connectionRequestFailed(
                            clientName: connectionAttempt.client.name,
                            underlyingError: error
                        )
                    )
                )
            }
        }
    }

    func disconnectClient() {
        connectionRequestTask?.cancel()
        connectionRequestTask = nil
        connectionRequestID = nil
        pendingConnectionIdentifier = nil
        state.pendingConnectionClient = nil
        state.lastConnectedClient = nil
        environment.server.expectConnection(identifier: nil)
        disconnectActiveConnection()

        Task { [weak self] in
            guard let self else { return }
            await self.environment.server.closeCurrentConnection()
        }
    }

    // MARK: - Plugins

    func loadPlugins() {
        let plugins = Array(environment.pluginManager.makePlugins())
        state.loadedPlugins = .init(uniqueElements: plugins)
        configureMCPConnect(for: plugins)

        if let pendingDeepLink = state.pendingDeepLink {
            handleDeepLink(pendingDeepLink)
        }

        if state.isImportedArchive {
            replayCachedDataToPlugins()
        }
    }

    func replayCachedDataToPlugins() {
        let plugins = state.loadedPlugins

        Task { [weak self] in
            guard let self else { return }
            var pluginsWithData: [LoadedPlugin] = []
            var pluginIDsWithData: Set<PluginIdentifier> = []

            for plugin in plugins {
                do {
                    let cachedData = try await PluginMessageCache.shared.getCachedData(for: plugin.id)
                    if !cachedData.isEmpty {
                        pluginsWithData.append(plugin)
                        pluginIDsWithData.insert(plugin.id)
                    }
                } catch {
                    self.logger.error("Failed to check cached data for plugin \(plugin.id): \(error.localizedDescription)")
                }
            }

            self.state.pluginsWithCachedData = pluginIDsWithData

            for plugin in pluginsWithData {
                do {
                    let cachedData = try await PluginMessageCache.shared.getCachedData(for: plugin.id)
                    let publisher = PassthroughSubject<PluginMessage, Never>()
                    let pluginConnection = PluginConnection(
                        incomingMessages: publisher.eraseToAnyPublisher(),
                        send: { _ in }
                    )
                    plugin.onConnect(pluginConnection)

                    for data in cachedData {
                        let message = PluginMessage(command: data.payload.command, data: data.payload.data)
                        publisher.send(message)
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                    publisher.send(completion: .finished)
                } catch {
                    self.logger.error("Failed to replay cached data for plugin \(plugin.id): \(error.localizedDescription)")
                }
            }
        }
    }

    func selectPlugin(_ pluginID: PluginIdentifier?) {
        guard pluginID != state.selectedPlugin?.id else { return }

        let oldPluginID = state.selectedPlugin?.id
        let oldMetadata = state.selectedPlugin?.metadata

        if let oldPluginID {
            do {
                try self.environment.server.currentConnection?.sendPluginLifecycleEvent(.inactive, pluginID: oldPluginID)
            } catch {
                self.showError(ErrorState(PluginError.sendFailed(context: "Send plugin inactive event", underlyingError: error)))
            }
        }
        if let oldMetadata {
            AnalyticsProvider.shared.trackPluginViewed(metadata: oldMetadata)
        }
        self.deferredSelectPlugin(pluginID)
    }

    func selectNextPlugin() {
        let plugins = state.enabledPlugins.elements
        guard !plugins.isEmpty,
              let currentIndex = plugins.firstIndex(where: { $0.id == state.selectedPlugin?.id })
        else { return }
        let nextIndex = (currentIndex + 1) % plugins.count
        selectPlugin(plugins[nextIndex].id)
    }

    func selectPreviousPlugin() {
        let plugins = state.enabledPlugins.elements
        guard !plugins.isEmpty,
              let currentIndex = plugins.firstIndex(where: { $0.id == state.selectedPlugin?.id })
        else { return }
        let previousIndex = (currentIndex - 1 + plugins.count) % plugins.count
        selectPlugin(plugins[previousIndex].id)
    }

    func resetPlugins() {
        state.selectedPlugin = nil
        state.loadedPlugins.forEach { $0.plugin.onDisconnect() }
        state.loadedPlugins.removeAll()

        loadPlugins()
        disconnectClient()
        AnalyticsProvider.shared.trackPluginsReset()
    }

    func updatePluginVisibility(_ pluginIDs: [PluginIdentifier], shouldShow: Bool) {
        var disabled = UserDefaults.standard.disabledPluginIdentifiers ?? []
        if !shouldShow {
            disabled.append(contentsOf: pluginIDs)
        } else {
            disabled.removeAll { pluginIDs.contains($0) }
        }
        UserDefaults.standard.disabledPluginIdentifiers = disabled
    }

    func openPluginInFinder(_ pluginID: PluginIdentifier) {
        guard let framework = state.loadedPlugins[id: pluginID]?.framework else { return }
        NSWorkspace.shared.open(framework)
    }

    func collapseSection(shouldCollapse: Bool, section: String) {
        if shouldCollapse {
            state.collapsedSections.append(section)
        } else {
            state.collapsedSections.removeAll { $0 == section }
        }
        UserDefaults.standard.collapsedSections = state.collapsedSections
    }

    // MARK: - Private

    private var shouldAutoReconnect: Bool {
        if UserDefaults.standard.object(forKey: "shouldAutoReconnectToClient") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "shouldAutoReconnectToClient")
    }

    private func deferredSelectPlugin(_ pluginID: PluginIdentifier?) {
        state.selectedPlugin = pluginID.flatMap { id in
            state.loadedPlugins[id: id].map { .init($0, id: id) }
        }

        if pluginID != nil {
            state.currentScreen = .main
        }

        if let pluginID {
            do {
                try environment.server.currentConnection?.sendPluginLifecycleEvent(.active, pluginID: pluginID)
            } catch {
                showError(ErrorState(PluginError.sendFailed(context: "Send plugin active event", underlyingError: error)))
            }
        }

        if let metadata = state.selectedPlugin?.plugin.metadata {
            AnalyticsProvider.shared.trackPluginOpened(metadata: metadata)
        }
    }

    private func updateAvailableBonjourClients(_ clients: [BonjourService]) {
        state.availableBonjourClients = clients
        state.shouldAutoReconnect = shouldAutoReconnect

        if state.autoConnectToFirstAvailable,
           state.connectedClient == nil,
           state.pendingConnectionClient == nil,
           let first = clients.first {
            state.autoConnectToFirstAvailable = false
            selectClient(.bonjour(first))
            return
        }

        if state.shouldAutoReconnect,
           state.connectedClient == nil,
           state.pendingConnectionClient == nil,
           let lastConnectedClient = state.lastConnectedClient,
           let newService = clients.first(where: { $0.name == lastConnectedClient.name }) {
            selectClient(.bonjour(newService))
        }
    }

    private func updateAvailableADBClients(_ updateResult: Result<[ADB.Device], ADBError>) {
        state.shouldAutoReconnect = shouldAutoReconnect
        switch updateResult {
        case let .failure(error):
            state.adbError = error
        case let .success(clients):
            state.availableADBClients = clients
            state.adbError = nil

            if state.autoConnectToFirstAvailable,
               state.connectedClient == nil,
               state.pendingConnectionClient == nil,
               let first = clients.first {
                state.autoConnectToFirstAvailable = false
                selectClient(.adb(first))
                return
            }

            if state.shouldAutoReconnect,
               state.connectedClient == nil,
               state.pendingConnectionClient == nil,
               case let .adb(lastADBClient) = state.lastConnectedClient,
               clients.contains(lastADBClient) {
                selectClient(.adb(lastADBClient))
            }
        }
    }

    private func monitorConnectionLifecycle() {
        setTask(
            key: "connectionLifecycle",
            Task { [weak self] in
                guard let self else { return }
                for await connection in self.environment.server.connectionUpdates {
                    self.handleConnectionChange(connection)
                }
            }
        )
    }

    private func waitForClientConnection(
        matching identifier: String?,
        after previousConnectionID: UUID?,
        timeout: TimeInterval
    ) async throws -> any ClientServerConnection {
        if let connection = environment.server.currentConnection,
           connection.id != previousConnectionID,
           identifier.map({ connectionMatchesClient(connection, identifier: $0) }) ?? true {
            return connection
        }

        do {
            return try await withTimeout(seconds: timeout) {
                for await connection in self.environment.server.connectionUpdates {
                    try Task.checkCancellation()
                    guard let connection,
                          connection.id != previousConnectionID,
                          identifier.map({
                              self.connectionMatchesClient(connection, identifier: $0)
                          }) ?? true else { continue }
                    return connection
                }
                throw ConnectionRequestTimeoutError(seconds: timeout)
            }
        } catch is OperationTimeoutError {
            throw ConnectionRequestTimeoutError(seconds: timeout)
        }
    }

    private func waitForLifecycleOwnership(of connectionID: UUID, timeout: TimeInterval) async throws {
        do {
            try await withTimeout(seconds: timeout) {
                while self.activeConnectionID != connectionID {
                    try Task.checkCancellation()
                    guard self.environment.server.currentConnection?.id == connectionID else {
                        throw ConnectionConfirmationError()
                    }
                    await Task.yield()
                }
            }
        } catch is OperationTimeoutError {
            throw ConnectionRequestTimeoutError(seconds: timeout)
        }
    }

    private func connectionMatchesClient(
        _ connection: any ClientServerConnection,
        identifier: String
    ) -> Bool {
        connection.currentConnectedClient.deviceIdentifier.value
            .caseInsensitiveCompare(identifier) == .orderedSame
    }

    private func handleConnectionChange(_ connection: (any ClientServerConnection)?) {
        guard let connection else {
            if environment.server.currentConnection == nil {
                disconnectActiveConnection()
            }
            return
        }

        guard environment.server.currentConnection?.id == connection.id else { return }
        guard activeConnectionID != connection.id else { return }

        if let identifier = pendingConnectionIdentifier,
           !connectionMatchesClient(connection, identifier: identifier) {
            Task { await connection.close() }
            return
        }

        if activeConnectionID != nil || state.connectedClient != nil {
            disconnectActiveConnection()
        }

        activeConnectionID = connection.id
        activeConnection = connection
        environment.server.expectConnection(identifier: nil)

        connectPlugins(to: connection)
        startConnectedClientUpdates(for: connection)
        startIncomingPayloadMonitoring(for: connection)
    }

    private func disconnectActiveConnection() {
        guard activeConnectionID != nil
                || state.connectedClient != nil
                || androidTunnelOwnership.hasActiveTunnel else { return }
        androidTunnelOwnership.close()

        tasks["connectedClientUpdates"]?.cancel()
        tasks["connectedClientUpdates"] = nil
        tasks["incomingPayloads"]?.cancel()
        tasks["incomingPayloads"] = nil

        state.loadedPlugins.forEach { $0.plugin.onDisconnect() }
        activeConnectionID = nil
        activeConnection = nil
        updateConnectedClient(nil)
    }

    private func startConnectedClientUpdates(for connection: any ClientServerConnection) {
        let connectionID = connection.id
        setTask(
            key: "connectedClientUpdates",
            Task { [weak self, connection] in
                guard let self else { return }
                for await connectedClient in connection.connectedClientUpdates {
                    guard self.activeConnectionID == connectionID else { break }
                    self.updateConnectedClient(connectedClient)
                }
            }
        )
    }

    private func updateConnectedClient(_ newConnectedClient: ConnectedClient?) {
        let previouslyConnected = state.connectedClient
        state.connectedClient = newConnectedClient

        if let newConnectedClient, previouslyConnected == nil {
            let deviceID = state.lastConnectedClient?.name ?? UUID().uuidString
            Task { @MainActor [weak self] in self?.mcpServer?.setSession(DeviceSession(id: deviceID)) }

            let deviceName = newConnectedClient.deviceName ?? deviceID
            let deviceType: String
            if case .adb = state.lastConnectedClient { deviceType = "android" } else { deviceType = "ios" }
            let fileCache = sessionFileCache
            Task {
                do {
                    _ = try await fileCache.startSession(deviceName: deviceName, deviceType: deviceType)
                } catch {
                    print("[SessionFileCache] Failed to start session: \(error)")
                }
            }
        } else if previouslyConnected != nil, newConnectedClient == nil {
            Task { @MainActor [weak self] in self?.mcpServer?.setSession(nil) }
            let fileCache = sessionFileCache
            Task {
                do {
                    try await fileCache.endSession()
                } catch {
                    print("[SessionFileCache] Failed to end session: \(error)")
                }
            }
        }

        if let newConnectedClient,
           let clientInfo = newConnectedClient.clientInfo {
            AnalyticsProvider.shared.trackClientConnectedToAppIdentifier(
                appId: newConnectedClient.appIdentifier,
                availablePlugins: clientInfo.clientPluginIDs
            )
        }

        if previouslyConnected == nil,
           newConnectedClient != nil,
           let selectedPluginID = state.selectedPlugin?.id {
            do {
                try environment.server.currentConnection?.sendPluginLifecycleEvent(.active, pluginID: selectedPluginID)
            } catch {
                showError(ErrorState(PluginError.sendFailed(context: "Send plugin active event", underlyingError: error)))
            }
        }

        if newConnectedClient != nil, let pendingDeepLink = state.pendingDeepLink {
            handleDeepLink(pendingDeepLink)
        }
    }

    private func connectToFirstAvailable() {
        guard state.autoConnectToFirstAvailable,
              state.connectedClient == nil,
              state.pendingConnectionClient == nil
        else { return }

        if let first = state.availableBonjourClients.first {
            state.autoConnectToFirstAvailable = false
            selectClient(.bonjour(first))
            return
        }

        if let first = state.availableADBClients.first {
            state.autoConnectToFirstAvailable = false
            selectClient(.adb(first))
        }
    }

    private func connectPlugins(to connection: any ClientServerConnection) {
        state.loadedPlugins.forEach { plugin in
            let pluginConnection = PluginConnection(
                incomingMessages: connection
                    .incomingPluginPayloads
                    .filter { $0.pluginID == plugin.id }
                    .map { PluginMessage(command: $0.command, data: $0.data) }
                    .catch { [logger = self.logger] error in
                        logger.error("Echo server incoming payload error: \(error.localizedDescription)")
                        return Empty<PluginMessage, Never>()
                    }
                    .eraseToAnyPublisher(),
                send: { message in
                    let payload = PluginPayload(pluginID: plugin.id, data: message.data, command: message.command)
                    try? connection.send(payload)
                }
            )
            plugin.onConnect(pluginConnection)
        }
    }

    private func startIncomingPayloadMonitoring(for connection: any ClientServerConnection) {
        let connectionID = connection.id
        setTask(
            key: "incomingPayloads",
            Task { [weak self, connection] in
                guard let self else { return }
                do {
                    for try await payload in connection.incomingPluginPayloads.values {
                        guard self.activeConnectionID == connectionID else { break }
                        try? await PluginMessageCache.shared.addMessage(pluginId: payload.pluginID, payload: payload)
                        try? await self.sessionFileCache.append(payload: payload)
                        self.onDebugPayload(self.makeDebugPayload(from: payload))
                    }
                } catch {
                    self.logger.error("Failed to read incoming payloads: \(error.localizedDescription)")
                }
            }
        )
    }

    private func makeDebugPayload(from payload: PluginPayload) -> DebugPayload {
        let prettyData: String = {
            if let object = try? JSONSerialization.jsonObject(with: payload.data),
               let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return String(data: payload.data, encoding: .utf8) ?? payload.data.base64EncodedString()
        }()

        return DebugPayload(
            pluginID: payload.pluginID,
            prettyData: prettyData,
            prefixData: String(prettyData.prefix(120))
        )
    }

    private func setTask(key: String, _ task: Task<Void, Never>) {
        tasks[key]?.cancel()
        tasks[key] = task
    }

    // MARK: - MCP

    private func configureMCPConnect(for plugins: [LoadedPlugin]) {
        let allPlugins = plugins.map { $0.plugin }
        let server = MCPServer()
        server.connectDeviceHandler = { [weak self] id in
            self?.connectToClientByID(id) ?? false
        }
        do {
            try server.start(plugins: allPlugins)
            self.mcpServer = server
        } catch {
            logger.error("[MCPServer] Failed to start: \(error.localizedDescription)")
        }
    }

    private func connectToClientByID(_ id: String) -> Bool {
        if let bonjour = state.availableBonjourClients.first(where: { $0.name == id }) {
            selectClient(.bonjour(bonjour))
            return true
        }
        if let adb = state.availableADBClients.first(where: { $0.name == id }) {
            selectClient(.adb(adb))
            return true
        }
        return false
    }
}

final class AndroidTunnelOwnership: @unchecked Sendable {
    private let activeTunnel = OSAllocatedUnfairLock<AndroidTunnel?>(initialState: nil)

    var hasActiveTunnel: Bool { activeTunnel.withLock { $0 != nil } }

    func transfer(
        _ tunnel: AndroidTunnel?,
        connectionID: UUID,
        activeConnectionID: UUID?
    ) throws {
        guard connectionID == activeConnectionID else {
            throw ConnectionConfirmationError()
        }
        let previousTunnel = activeTunnel.withLock { activeTunnel in
            defer { activeTunnel = tunnel }
            return activeTunnel
        }
        previousTunnel?.close()
    }

    func close() {
        let previousTunnel = activeTunnel.withLock { activeTunnel in
            defer { activeTunnel = nil }
            return activeTunnel
        }
        previousTunnel?.close()
    }
}
