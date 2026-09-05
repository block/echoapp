@testable import Echo

import EchoConnection
import XCTest

@MainActor
final class AppViewModelTests: XCTestCase {

    func test_createSession_startsSessionOnceAndIsIdempotent() {
        let builder = TestSessionViewModelBuilder()
        let viewModel = AppViewModel(sessionBuilder: builder)
        let sessionID = UUID()

        let firstSession = viewModel.createSession(sessionID: sessionID)
        let secondSession = viewModel.createSession(sessionID: sessionID)

        XCTAssertTrue(firstSession === secondSession)
        XCTAssertEqual(builder.makeSessionCalls.count, 1)
        XCTAssertEqual(viewModel.activeSessionID, sessionID)
    }

    func test_createSession_incrementsPorts() {
        let builder = TestSessionViewModelBuilder()
        let viewModel = AppViewModel(sessionBuilder: builder, initialPort: 4000)

        _ = viewModel.createSession(sessionID: UUID())
        _ = viewModel.createSession(sessionID: UUID())
        _ = viewModel.createSession(sessionID: UUID())

        XCTAssertEqual(builder.makeSessionCalls.map(\.port), [4000, 4001, 4002])
    }

    func test_createSession_firstSessionUsesBasePort() {
        let builder = TestSessionViewModelBuilder()
        let viewModel = AppViewModel(sessionBuilder: builder)

        _ = viewModel.createSession(sessionID: UUID())

        XCTAssertEqual(builder.makeSessionCalls.first?.port, 34143)
    }

    func test_createSession_recyclesPortAfterDestroy() {
        let builder = TestSessionViewModelBuilder()
        let viewModel = AppViewModel(sessionBuilder: builder, initialPort: 4000)

        let first = UUID()
        let second = UUID()
        _ = viewModel.createSession(sessionID: first)
        _ = viewModel.createSession(sessionID: second)
        viewModel.destroySession(first)

        _ = viewModel.createSession(sessionID: UUID())

        XCTAssertEqual(builder.makeSessionCalls.map(\.port), [4000, 4001, 4000])
    }

    func test_destroySession_updatesActiveSession() {
        let builder = TestSessionViewModelBuilder()
        let viewModel = AppViewModel(sessionBuilder: builder)
        let sessionOne = UUID()
        let sessionTwo = UUID()

        _ = viewModel.createSession(sessionID: sessionOne)
        _ = viewModel.createSession(sessionID: sessionTwo)
        viewModel.setActiveSession(sessionOne)

        viewModel.destroySession(sessionOne)

        XCTAssertNil(viewModel.session(for: sessionOne))
        XCTAssertEqual(viewModel.activeSessionID, sessionTwo)
    }
}

@MainActor
private final class TestSessionViewModelBuilder: SessionViewModelBuilding {
    struct MakeSessionCall {
        let sessionID: UUID
        let port: Int
        let initialClient: DiscoveredClient?
        let isImportedArchive: Bool
        let archiveURL: URL?
    }

    private(set) var makeSessionCalls: [MakeSessionCall] = []

    func makeSession(
        sessionID: UUID,
        port: Int,
        initialClient: DiscoveredClient?,
        isImportedArchive: Bool,
        archiveURL: URL?,
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) -> SessionViewModel {
        makeSessionCalls.append(
            .init(
                sessionID: sessionID,
                port: port,
                initialClient: initialClient,
                isImportedArchive: isImportedArchive,
                archiveURL: archiveURL
            )
        )

        let sessionViewModel = SessionViewModel(
            initialState: SessionState(
                id: sessionID,
                port: port,
                pluginManager: DesktopPluginManager(pluginFrameworks: [])
            ),
            environment: SessionEnvironment(
                server: TestServer(clientServerConnection: TestClientServerConnection()),
                pluginManager: DesktopPluginManager(pluginFrameworks: [])
            ),
            onDebugPayload: onDebugPayload
        )
        return sessionViewModel
    }

    func makeFileBackedSession(
        sessionID: UUID,
        sessionDir: URL,
        deviceName: String,
        onDebugPayload: @escaping @MainActor (DebugPayload) -> Void
    ) -> SessionViewModel {
        let sessionViewModel = SessionViewModel(
            initialState: SessionState(
                id: sessionID,
                port: 0,
                pluginManager: DesktopPluginManager(pluginFrameworks: [])
            ),
            environment: SessionEnvironment(
                server: TestServer(clientServerConnection: TestClientServerConnection()),
                pluginManager: DesktopPluginManager(pluginFrameworks: [])
            ),
            onDebugPayload: onDebugPayload
        )
        return sessionViewModel
    }
}
