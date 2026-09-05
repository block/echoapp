
import Combine
import EchoPluginAPI
import Foundation

/// The Echo networking plugin supports two modes: **Proxy** and **Passive**.
///
/// **Proxy Mode**
/// Echo executes network requests _on behalf of the client_,
/// giving users full control over request behavior. Through EchoApp.app’s UI, users can:
/// delay requests, use predefined fixtures, proxy requests to a different server,
/// or simulate HTTP errors.
///
/// **Passive Mode**
/// The client executes network requests normally (e.g., via `URLSession`).
/// EchoApp.app passively records requests and responses, providing users with a reviewable history.
///
/// ---
///
/// **Proxy Mode**
/// 1. Client app calls `networkingClientPlugin.proxy(_:)` with a request. The return value
///    of this method is an `AsyncStream`.
/// 2. The client app `await`s the stream to receive a response. When a response arrives,
///    the client app processes it and calls `finalizeResponse(_:)` to complete
///    the interaction
/// 3. If processing fails, the client app calls one of the error methods defined on NetworkingPlugin.
///    When an error is reported, EchoApp.app will allow the user to retry with a different
///    response and send it in the same AsyncStream. Once processing eventually succeeds, the client app
///    calls `finalizeResponse(_:)` to complete the interaction.
///```
/// +---------+       +----------+       +---------+
/// | Client  |       |  Echo    |       |   Web   |
/// +---------+       |  Server  |       +---------+
///      |            +----------+           |
///      |                 |                 |
///      | proxy()         |                 |
///      |---------------->|                 |
///      |                 |                 |
///      |                 |  HTTP Request   |
///      |                 |---------------> |
///      |                 |                 |
///      |                 |  HTTP Response  |
///      |                 |<--------------- |
///      |                 |                 |
///      | response        |                 |
///      | from AsyncStream|                 |
///      |<----------------|                 |
///      |                 |                 |
///      | finalizedResponse                 |
///      |---------------->|                 |
/// ```
///
///
/// **Passive Mode**
/// 1. Client app calls `networkingClientPlugin.recordRequest(_:)` with a request.
/// 2. The client app executes the request normally (e.g. using `URLSession`)
/// 3. The client app calls `finalizeResponse(_:)` to complete the interaction.
/// ```
/// +---------+       +---------+        +---------+
/// | Client  |       |  Echo   |        |   Web   |
/// +---------+       |  Server |        +---------+
///      |            +---------+             |
///      |                 |                  |
///      | recordRequest() |                  |
///      |---------------->|                  |
///      |                 |                  |
///      |  HTTP Request   |                  |
///      |----------------------------------->|
///      |                 |                  |
///      |  HTTP Response  |                  |
///      |<-----------------------------------|
///      |                 |                  |
///      | finalizedResponse                  |
///      |---------------->|                  |
/// ```
public final class NetworkingPlugin: ClientPlugin {

    // MARK: - Private Properties

    private var connection: PluginConnection?
    private var cancellable: AnyCancellable?

    private let suspendedRequestsLock = NSLock()

    /// Requests that have been sent to Echo but have not yet received a response.
    /// Always access with `suspendedRequestsLock`
    private var suspendedRequestsByID: [
        String: AsyncStream<Either<RawResponse, HumanReadableResponse>>.Continuation
    ] = [:]


    // MARK: - Client Plugin

    public var id: PluginIdentifier = "com.echo.plugin.network"

    public var version: String = "0.0.1"

    public func onConnect(_ connection: PluginConnection) {
        self.connection = connection

        cancellable = connection.receive(NetworkingPluginServerEvent.self).sink { [weak self] event in
            guard let self else { return }

            suspendedRequestsLock.lock()
            defer { suspendedRequestsLock.unlock() }

            switch event {
            case let .rawResponse(rawResponse):
                let suspendedRequest = suspendedRequestsByID[rawResponse.requestID]
                suspendedRequest?.yield(.left(rawResponse))

            case let .proposedHumanReadableResponse(humanReadableResponse):
                let suspendedRequest = suspendedRequestsByID[humanReadableResponse.requestID]
                suspendedRequest?.yield(.right(humanReadableResponse))
            }
        }
    }

    public func onDisconnect() {
        self.connection = nil
        self.cancellable = nil
    }

    // MARK: - Public Methods

    public var isConnected: Bool {
        connection != nil
    }

    // MARK: - Public Methods (Passive Mode)

    /**
     * **Passive Mode**
     * Record a request made by the client.
     * The client app should execute the request normally (e.g. using `URLSession`) and then call `finalizeResponse` to complete the interaction.
     *
     * Alternatively, the client can opt-in to **Proxy Mode**. See the ``proxy(_:)`` method for more information.
     */
    public func recordRequest(_ request: Request) {
        trySend(.request(request, proxy: false))
    }

    // MARK: - Public Methods (Proxy Mode)

    /**
     * **Proxy Mode**
     * Proxy a request to Echo.
     * The client app should await the returned stream to receive the response from Echo.
     * In the happy path, the stream yields a single response, the client processes it, and finally calls `finalizeResponse(_:)` to complete the interaction.
     * If an error occurs while processing, the client should call the appropriate error method instead.
     * The user will be asked to try again, and another response will be emitted in the same stream.
     * The client should _always_ eventually call `finalizeResponse(_:)` to complete the interaction.
     */
    public func proxy(_ request: Request) -> AsyncStream<Either<RawResponse, HumanReadableResponse>> {
        suspendedRequestsLock.lock()
        let stream = AsyncStream { continuation in
            suspendedRequestsByID[request.id] = continuation
            suspendedRequestsLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                suspendedRequestsLock.withLock {
                    self.suspendedRequestsByID[request.id] = nil
                }
            }

            trySend(.request(request, proxy: true))
        }
        return stream
    }

    /**
     * **Proxy Mode**
     * Notify Echo that the client failed to use the provided response.
     * - parameter error: The underlying error that occurred while parsing the response.
     *                    This is recommended to be a `LocalizedError` instance with at least one property populated.
     */
    public func reportHumanReadableResponseParsingError(error: Error, response: HumanReadableResponse) {
        let errorReason = "The client failed to parse the response body.\n\(error.detailedDescription)"

        trySend(
            .error(
                .failedToParseProposedHumanReadableResponse(reason: errorReason),
                requestID: response.requestID
            )
        )
    }

    // MARK: - Public Methods (Both Modes)

    /**
     * **Both Modes**
     * Report the finalized response to Echo to complete the client-server interaction for a particular request.
     * This method should be called after processing a proxied result (using `proxy()`) or after executing a request that was reported via `recordRequest()`.
     */
    public func finalizeResponse(_ finalizedResponse: HumanReadableResponse) {
        let suspendedRequest = suspendedRequestsLock.withLock {
            suspendedRequestsByID[finalizedResponse.requestID]
        }
        // Clean up the suspended request now that the client-server interaction is complete
        suspendedRequest?.finish()

        trySend(.finalizedResponse(finalizedResponse))
    }

    // MARK: - Public Methods (Deprecated)

    @available(*, deprecated, message: "Use `recordRequest` or `proxy` to send requests. Use `finalizeResponse` to send responses.")
    public func send(event: DeprecatedNetworkingPluginClientEvent) {
        do {
            try connection?.send(event)
        } catch {
            print("Echo failed to send networking plugin event \(event)")
        }
    }

    // MARK: - Private Methods

    private func trySend(_ event: NetworkingPluginClientEvent) {
        do {
            try connection?.send(event)
        } catch {
            print("Echo: Failed to send networking plugin event `\(event)`")
        }
    }
}
