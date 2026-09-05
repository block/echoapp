import Foundation
import Network
import os
import XCTest

import EchoConnection

@testable import Echo

final class ADBEchoTests: XCTestCase {

    func test_discoveredClient_analyticsDimensionsDescribeTransportAndPlatform() throws {
        let adbClient = DiscoveredClient.adb(makeDevice())
        let androidBonjourClient = DiscoveredClient.bonjour(
            BonjourService(
                endpoint: .hostPort(
                    host: "127.0.0.1",
                    port: try XCTUnwrap(NWEndpoint.Port(rawValue: 42633))
                ),
                name: "android",
                displayName: nil,
                adbProvider: { nil }
            )
        )
        let appleBonjourClient = DiscoveredClient.bonjour(
            BonjourService(
                endpoint: .service(
                    name: "iPhone",
                    type: "_echoclient._tcp",
                    domain: "local",
                    interface: nil
                ),
                name: "apple",
                displayName: nil,
                adbProvider: { nil }
            )
        )

        XCTAssertEqual(adbClient.transport, "adb")
        XCTAssertEqual(adbClient.platform, "android")
        XCTAssertEqual(androidBonjourClient.transport, "bonjour")
        XCTAssertEqual(androidBonjourClient.platform, "android")
        XCTAssertEqual(appleBonjourClient.transport, "bonjour")
        XCTAssertEqual(appleBonjourClient.platform, "apple")
    }

    func test_adbSearchPaths_prefersWhichThenAndroidEnvironmentThenKnownFallbacks() {
        let paths = ADB.adbSearchPaths(
            environment: [
                "ANDROID_HOME": "/Users/test/Library/Android/sdk",
                "ANDROID_SDK_ROOT": "/opt/android-sdk",
            ],
            whichADB: { "/custom/bin/adb" }
        )

        XCTAssertEqual(paths[0], "/custom/bin/adb")
        XCTAssertEqual(paths[1], "/Users/test/Library/Android/sdk/platform-tools/adb")
        XCTAssertEqual(paths[2], "/opt/android-sdk/platform-tools/adb")
        XCTAssertTrue(paths.contains(ADB.defaultPath))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/adb"))
        XCTAssertTrue(paths.contains("/usr/local/bin/adb"))
    }

    func test_adbSearchPaths_removesDuplicates() {
        let paths = ADB.adbSearchPaths(
            environment: ["ANDROID_HOME": "/opt/homebrew"],
            whichADB: { "/opt/homebrew/platform-tools/adb" }
        )

        XCTAssertEqual(paths.filter { $0 == "/opt/homebrew/platform-tools/adb" }.count, 1)
    }

    func test_adbSearchPaths_whenWhichIsUnavailable_prefersAndroidEnvironment() {
        let paths = ADB.adbSearchPaths(
            environment: ["ANDROID_HOME": "/opt/android-sdk"],
            whichADB: { nil }
        )

        XCTAssertEqual(paths[0], "/opt/android-sdk/platform-tools/adb")
    }

    func test_adbSearchPaths_expandsTildeInAndroidEnvironment() {
        let paths = ADB.adbSearchPaths(
            environment: ["ANDROID_SDK_ROOT": "~/Library/Android/sdk"],
            whichADB: { nil }
        )

        XCTAssertEqual(paths[0], ADB.defaultPath)
    }

    func test_execute_whenADBExitsNonzero_surfacesStatusAndStderr() async throws {
        let adb = try XCTUnwrap(ADB(path: "/bin/sh"))

        do {
            _ = try await adb.execute("-c", "echo 'device offline' >&2; exit 17")
            XCTFail("Expected a nonzero adb exit to throw")
        } catch let error as ADBError {
            guard case let .adbCommandFailed(command, underlyingError) = error else {
                return XCTFail("Unexpected ADB error: \(error)")
            }
            XCTAssertEqual(command, "-c echo 'device offline' >&2; exit 17")
            XCTAssertTrue(underlyingError.contains("status 17"))
            XCTAssertTrue(underlyingError.contains("device offline"))
        }
    }

    func test_execute_drainsLargeOutputBeforeProcessExit() async throws {
        let adb = try XCTUnwrap(ADB(path: "/bin/sh"))
        let script = """
        awk 'BEGIN { for (i = 0; i < 20000; i++) print "stdout-output" }'
        awk 'BEGIN { for (i = 0; i < 20000; i++) print "stderr-output" }' >&2
        """

        let output = try await withTimeout(seconds: 5) {
            try await adb.execute("-c", script)
        }

        XCTAssertGreaterThan(output.utf8.count, 200_000)
    }

    func test_echoEnabledDevices_returnsHealthyDeviceWhenAnotherProbeTimesOut() async throws {
        let script = try makeADBScript(
            """
            if [ "$1" = "devices" ]; then
              printf 'List of devices attached\\nfast device product:test model:Fast device:test transport_id:1\\nslow device product:test model:Slow device:test transport_id:2\\n'
            elif [ "$2" = "fast" ]; then
              printf 'Netid State Type Path\\n0 0 STREAM @echo-server-fast-id\\n'
            else
              sleep 1
            fi
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let adb = try XCTUnwrap(ADB(path: script.path))

        let devices = try await adb.echoEnabledDevices(
            deviceListTimeout: 1,
            socketProbeTimeout: 0.5
        )

        XCTAssertEqual(devices.map(\.name), ["fast"])
        XCTAssertEqual(devices.first?.androidId, "fast-id")
    }

    func test_findUnixDomainSockets_parsesHeaderlessOutput() async throws {
        let script = try makeADBScript("printf '0 0 STREAM @echo-server-device-id\\n'")
        defer { try? FileManager.default.removeItem(at: script) }
        let adb = try XCTUnwrap(ADB(path: script.path))

        let sockets = try await adb.findUnixDomainSockets(for: makeDevice())

        XCTAssertEqual(sockets, ["@echo-server-device-id"])
    }

    func test_echoEnabledDevices_resolvesLegacySocketIdentityWithoutChangingSocketName() async throws {
        let script = try makeADBScript(
            """
            if [ "$1" = "devices" ]; then
              printf 'emulator-5554 device product:test model:Pixel device:virtual transport_id:1\\n'
            elif [ "$4" = "ss" ]; then
              printf 'Netid State Type Path\\n0 0 STREAM @echo-server\\n'
            elif [ "$4" = "settings" ]; then
              printf 'legacy-android-id\\n'
            fi
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let adb = try XCTUnwrap(ADB(path: script.path))

        let devices = try await adb.echoEnabledDevices()
        let device = try XCTUnwrap(devices.first)

        XCTAssertNil(device.androidId)
        XCTAssertEqual(device.androidIdOrName, "legacy-android-id")
        XCTAssertEqual(device.unixDomainSocket, "echo-server")
    }

    func test_dynamicUnixSocketForward_returnsPortAndRemovesLease() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-adb-log-\(UUID().uuidString)")
        let script = try makeADBScript(
            """
            printf '%s\\n' "$*" >> '\(logURL.path)'
            case "$*" in
              *"forward tcp:0"*) printf '54321\\n' ;;
            esac
            """
        )
        defer {
            try? FileManager.default.removeItem(at: script)
            try? FileManager.default.removeItem(at: logURL)
        }
        let adb = try XCTUnwrap(ADB(path: script.path))

        let lease = try await adb.dynamicUnixSocketForward(for: makeDevice())
        XCTAssertEqual(lease.port, 54321)
        lease.release()
        lease.release()

        let invocations = try await fileContents(at: logURL) {
            $0.contains("-s emulator-5554 forward --remove tcp:54321")
        }
        XCTAssertTrue(invocations.contains("-s emulator-5554 forward tcp:0 localabstract:echo-server"))
        XCTAssertEqual(
            invocations.components(separatedBy: "-s emulator-5554 forward --remove tcp:54321").count - 1,
            1
        )
    }

    @MainActor
    func test_bonjourSend_resolvesAndroidIdentityBeforeStartingTargetedSend() async throws {
        let script = try makeADBScript(
            """
            if [ "$1" = "devices" ]; then
              printf 'emulator-5554 device product:test model:Pixel device:virtual transport_id:1\\n'
            elif [ "$3" = "shell" ]; then
              printf 'Netid State Type Path\\n0 0 STREAM @echo-server-Android-ID\\n'
            elif [ "$3" = "forward" ]; then
              printf '9\\n'
            fi
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let adb = try XCTUnwrap(ADB(path: script.path))
        let service = BonjourService(
            endpoint: .hostPort(
                host: "127.0.0.1",
                port: try XCTUnwrap(NWEndpoint.Port(rawValue: 42633))
            ),
            name: "android-id",
            displayName: nil,
            adbProvider: { adb }
        )
        var resolvedIdentifier: String?

        do {
            _ = try await service.send(
                ConnectionRequest(serverURL: try XCTUnwrap(URL(string: "ws://localhost:34143/channel"))),
                timeout: 0.01,
                onResolvedDeviceIdentifier: { resolvedIdentifier = $0 }
            )
            XCTFail("Expected the closed local port to fail")
        } catch {
            XCTAssertEqual(resolvedIdentifier, "Android-ID")
        }
    }

    func test_androidTunnel_close_releasesResourcesOnce() {
        let counter = TestCloseCounter()
        let tunnel = AndroidTunnel {
            counter.increment()
        }

        tunnel.close()
        tunnel.close()

        XCTAssertEqual(counter.value, 1)
    }

    @MainActor
    func test_androidTunnelOwnership_transfersOnlyAfterLifecycleOwnsConnection() throws {
        let ownership = AndroidTunnelOwnership()
        let oldCounter = TestCloseCounter()
        let newCounter = TestCloseCounter()
        let oldConnectionID = UUID()
        let newConnectionID = UUID()

        try ownership.transfer(
            AndroidTunnel { oldCounter.increment() },
            connectionID: oldConnectionID,
            activeConnectionID: oldConnectionID
        )
        XCTAssertThrowsError(
            try ownership.transfer(
                AndroidTunnel { newCounter.increment() },
                connectionID: newConnectionID,
                activeConnectionID: oldConnectionID
            )
        ) { error in
            XCTAssertTrue(error is ConnectionConfirmationError)
        }
        XCTAssertEqual(oldCounter.value, 0)
        XCTAssertEqual(newCounter.value, 1, "the unowned temporary tunnel should deinitialize")

        try ownership.transfer(
            AndroidTunnel { newCounter.increment() },
            connectionID: newConnectionID,
            activeConnectionID: newConnectionID
        )
        XCTAssertEqual(oldCounter.value, 1)
        ownership.close()
        XCTAssertEqual(newCounter.value, 2)
    }

    func test_echoEnabledDevices_throwsWhenNoEchoDeviceSurvivesAProbeFailure() async throws {
        let script = try makeADBScript(
            """
            if [ "$1" = "devices" ]; then
              printf 'plain device product:test model:Plain device:test transport_id:1\\nslow device product:test model:Slow device:test transport_id:2\\n'
            elif [ "$2" = "plain" ]; then
              printf 'Netid State Type Path\\n'
            else
              sleep 1
            fi
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }
        let adb = try XCTUnwrap(ADB(path: script.path))

        do {
            _ = try await adb.echoEnabledDevices(
                deviceListTimeout: 1,
                socketProbeTimeout: 0.5
            )
            XCTFail("Expected the failed probe to remain actionable")
        } catch let error as ADBError {
            guard case let .adbDiscoveryFailed(underlyingError) = error else {
                return XCTFail("Unexpected ADB error: \(error)")
            }
            XCTAssertTrue(underlyingError.contains("slow:"))
        }
    }

    func test_execute_whenTaskIsAlreadyCancelled_doesNotLaunchProcess() async throws {
        let adb = try XCTUnwrap(ADB(path: "/bin/sh"))
        let task = Task {
            try await adb.execute("-c", "sleep 10")
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func test_deviceMatchesBonjourAndroidServiceName_byKnownIdentityOrDeviceName_caseInsensitively() {
        var device = ADB.Device(
            name: "emulator-5554",
            product: nil,
            model: nil,
            deviceType: "sdk_gphone64_arm64",
            transportId: "1"
        )
        device.androidId = "abc123"
        device.connectionIdentifier = "legacy-id"

        XCTAssertTrue(device.matchesBonjourAndroidServiceName("ABC123"))
        XCTAssertTrue(device.matchesBonjourAndroidServiceName("LEGACY-ID"))
        XCTAssertTrue(device.matchesBonjourAndroidServiceName("emulator-5554"))
        XCTAssertFalse(device.matchesBonjourAndroidServiceName("other-device"))
    }

    func test_send_whenConnectionFailsAfterReadySendCompletion_resumesContinuationOnce() async throws {
        let adb = try XCTUnwrap(ADB(path: "/bin/sh"))
        let connection = TestAndroidTunnelConnection()
        let serverURL = try XCTUnwrap(URL(string: "ws://localhost:42634"))
        let bridgedServerURL = OSAllocatedUnfairLock<URL?>(initialState: nil)

        connection.onStart = {
            connection.receive(state: .ready)
            connection.completeSend(with: nil)
            connection.receive(state: .failed(.posix(.ECONNRESET)))
        }

        try await adb.send(
            ConnectionRequest(serverURL: serverURL),
            using: connection,
            timeout: 1
        ) { _, serverURL in
            bridgedServerURL.withLock { $0 = serverURL }
        }

        XCTAssertEqual(bridgedServerURL.withLock { $0 }, serverURL)
        XCTAssertEqual(connection.sendCallCount, 1)
        XCTAssertEqual(connection.startCallCount, 1)
        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertEqual(connection.lastSentContent?.last, 0x0A)
        XCTAssertEqual(connection.lastIsComplete, false)
    }

    func test_send_whenConnectionNeverBecomesReady_timesOutAndCancels() async throws {
        let adb = try XCTUnwrap(ADB(path: "/bin/sh"))
        let connection = TestAndroidTunnelConnection()
        let serverURL = try XCTUnwrap(URL(string: "ws://localhost:42634"))

        do {
            try await adb.send(
                ConnectionRequest(serverURL: serverURL),
                using: connection,
                timeout: 0.01
            ) { _, _ in }
            XCTFail("Expected the stalled connection to time out")
        } catch is ConnectionRequestTimeoutError {
            XCTAssertEqual(connection.cancelCallCount, 1)
        }
    }

    func test_send_whenTaskIsCancelled_cancelsConnectionAndResumesWithCancellation() async throws {
        let adb = try XCTUnwrap(ADB(path: "/bin/sh"))
        let connection = TestAndroidTunnelConnection()
        let serverURL = try XCTUnwrap(URL(string: "ws://localhost:42634"))
        let started = expectation(description: "connection started")
        connection.onStart = { started.fulfill() }

        let task = Task {
            try await adb.send(
                ConnectionRequest(serverURL: serverURL),
                using: connection,
                timeout: 1
            ) { _, _ in }
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(connection.cancelCallCount, 1)
        }
    }

    private func makeDevice() -> ADB.Device {
        ADB.Device(
            name: "emulator-5554",
            product: "sdk",
            model: "Pixel",
            deviceType: "virtual",
            transportId: "1"
        )
    }

    private func makeADBScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-adb-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func fileContents(
        at url: URL,
        matching predicate: (String) -> Bool
    ) async throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        var contents = ""

        while clock.now < deadline {
            contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if predicate(contents) {
                return contents
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for expected adb invocation. Last contents: \(contents)")
        return contents
    }
}

private final class TestCloseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private final class TestAndroidTunnelConnection: AndroidTunnelConnection, @unchecked Sendable {
    var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)?
    var onStart: (() -> Void)?

    private(set) var sendCallCount = 0
    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var lastSentContent: Data?
    private(set) var lastIsComplete: Bool?
    private var sendCompletion: NWConnection.SendCompletion?

    func send(
        content: Data?,
        contentContext: NWConnection.ContentContext,
        isComplete: Bool,
        completion: NWConnection.SendCompletion
    ) {
        sendCallCount += 1
        lastSentContent = content
        lastIsComplete = isComplete
        sendCompletion = completion
    }

    func start(queue: DispatchQueue) {
        startCallCount += 1
        onStart?()
    }

    func cancel() {
        cancelCallCount += 1
    }

    func receive(state: NWConnection.State) {
        stateUpdateHandler?(state)
    }

    func completeSend(with error: NWError?) {
        guard let sendCompletion else {
            XCTFail("Expected send to be called before completing it.")
            return
        }

        switch sendCompletion {
        case let .contentProcessed(handler):
            handler(error)

        case .idempotent:
            XCTFail("Expected send completion to process content.")

        default:
            XCTFail("Unexpected send completion.")
        }
    }
}
