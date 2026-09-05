import EchoConnection
import EchoPluginAPI
import Foundation

// MARK: - Session View Model Builder

@MainActor
protocol SessionViewModelBuilding {
    func makeSession(
        sessionID: UUID,
        port: Int,
        initialClient: DiscoveredClient?,
        isImportedArchive: Bool,
        archiveURL: URL?,
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) -> SessionViewModel

    func makeFileBackedSession(
        sessionID: UUID,
        sessionDir: URL,
        deviceName: String,
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) -> SessionViewModel
}

@MainActor
struct LiveSessionViewModelBuilder: SessionViewModelBuilding {
    let pluginFrameworks: [FrameworkPlugin]

    func makeSession(
        sessionID: UUID,
        port: Int,
        initialClient: DiscoveredClient?,
        isImportedArchive: Bool,
        archiveURL: URL?,
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) -> SessionViewModel {
        let pluginManager = DesktopPluginManager(pluginFrameworks: pluginFrameworks)
        let server = RealServer(port: port)
        let sessionEnvironment = SessionEnvironment(server: server, pluginManager: pluginManager)

        var initialState = SessionState(id: sessionID, port: port, pluginManager: pluginManager)
        initialState.initialClient = initialClient
        initialState.isImportedArchive = isImportedArchive
        initialState.archiveURL = archiveURL

        return SessionViewModel(
            initialState: initialState,
            environment: sessionEnvironment,
            onDebugPayload: onDebugPayload
        )
    }

    func makeFileBackedSession(
        sessionID: UUID,
        sessionDir: URL,
        deviceName: String,
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) -> SessionViewModel {
        let pluginManager = DesktopPluginManager(pluginFrameworks: pluginFrameworks)
        let server = FileBackedServer(sessionDirectoryURL: sessionDir, deviceName: deviceName)
        let sessionEnvironment = SessionEnvironment(server: server, pluginManager: pluginManager)

        let initialState = SessionState(id: sessionID, port: 0, pluginManager: pluginManager)

        return SessionViewModel(
            initialState: initialState,
            environment: sessionEnvironment,
            onDebugPayload: onDebugPayload
        )
    }
}
