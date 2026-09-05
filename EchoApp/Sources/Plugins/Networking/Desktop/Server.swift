import Combine
import ComposableArchitecture
import EchoPluginAPI
import Foundation

final class Server {
    private let store: Store<AppState, AppAction>
    private let connection: CurrentValueSubject<PluginConnection?, Never>
    private var cancellables: Set<AnyCancellable> = []

    public init(
        store: Store<AppState, AppAction>,
        connection: CurrentValueSubject<PluginConnection?, Never>
    ) {
        self.store = store
        self.connection = connection
    }

    public func start() {
        // Listen for deprecated client events
        connection
            .flatMap {
                $0?.receive(DeprecatedNetworkingPluginClientEvent.self) ?? Empty().eraseToAnyPublisher()
            }
            .sink { [weak self] deprecatedClientEvent in
                // Translate the deprecated client event into a modern client event
                let modernClientEvent = NetworkingPluginClientEvent(deprecatedClientEvent)
                Task {
                    await self?.handle(modernClientEvent)
                }
            }
            .store(in: &cancellables)

        // Listen for modern client events
        connection
            .flatMap { $0?.receive(NetworkingPluginClientEvent.self) ?? Empty().eraseToAnyPublisher() }
            .sink { [weak self] clientEvent in
                Task {
                    await self?.handle(clientEvent)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handle(_ clientEvent: NetworkingPluginClientEvent) {
        switch clientEvent {
        case let .request(request, proxy):
            var responseSink: ResponseSink {
                ResponseSink(
                    responseSender: { [weak self] serverEvent in
                        try? self?.connection.value?.send(serverEvent)
                    },
                    errorReporter: { [weak self] errorMessage, requestID in
                        self?.store.send(.exchange(.recordServerError(errorMessage, requestID: requestID)))
                    }
                )
            }
            let initialState: Exchange.State = proxy
                ? .pendingResponse(responseSink: responseSink)
                : .waitingForClientProvidedResponse
            let exchange = Exchange(request: request, state: initialState)
            store.send(.exchange(.recordExchange(exchange)))

        case let .finalizedResponse(response):
            store.send(.exchange(.recordResponse(response)))

        case let .error(error, requestID):
            store.send(.exchange(.recordClientError(error, requestID: requestID)))
        }
    }
}

// MARK: -

private extension NetworkingPluginClientEvent {
    /// Transforms a deprecated client event type to the modern event type
    init(_ deprecatedClientEvent: DeprecatedNetworkingPluginClientEvent) {
        switch deprecatedClientEvent {
        case let .request(deprecatedRequest):
            let modernRequest = Request(deprecatedRequest)
            self = .request(modernRequest, proxy: false)

        case let .response(deprecatedResponse):
            let modernResponse = HumanReadableResponse(deprecatedResponse)
            self = .finalizedResponse(modernResponse)
        }
    }
}

// MARK: -

private extension HumanReadableResponse {
    /// Transforms a deprecated response type to the modern response type
    init(_ deprecatedResponse: DeprecatedNetworkingPluginClientEvent.Response) {
        self.init(
            requestID: deprecatedResponse.requestID,
            headers: deprecatedResponse.headers,
            body: deprecatedResponse.humanReadableBody,
            statusCode: deprecatedResponse.statusCode
        )
    }
}

// MARK: -

extension Request {
    /// Transforms a deprecated request type to the modern request type
    init(_ deprecatedRequest: DeprecatedNetworkingPluginClientEvent.Request) {
        // Deprecated requests only specify the URL path, so we need to construct a fake URL
        let fakeBaseURL = URL(string: "echo://")!
        var url = URL(string: deprecatedRequest.endpoint.path, relativeTo: fakeBaseURL)!
        if !deprecatedRequest.queryParameters.isEmpty {
            url = url.appending(
                queryItems: deprecatedRequest.queryParameters.map(URLQueryItem.init)
            )
        }
        self.init(
            id: deprecatedRequest.id,
            url: url,
            httpMethod: deprecatedRequest.httpMethod,
            headers: deprecatedRequest.headers,
            timestamp: deprecatedRequest.timestamp,
            humanReadableBody: deprecatedRequest.humanReadableBody,
            rawBody: nil
        )
    }

    func asCurlCommand() -> String {
        // ───────── Build a shell-ready cURL command ─────────
        var parts: [String] = ["curl"]
        parts.append("'\(url.absoluteString)'")

        // 2. HTTP method  – only emit -X if not GET
        let verb = httpMethod
        if verb.uppercased() != "GET" { parts.append("-X \(verb)") }

        // 3. Headers  – emit them exactly as received
        for (key, value) in headers {
            let escaped = value.replacingOccurrences(of: "'", with: #"'\''"#)
            parts.append("-H '\(key): \(escaped)'")
        }

        // 4. Body
        if let body = rawBody, !body.isEmpty {
            let tmp = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).bin")
            try? body.write(to: tmp)

            // use default: "" so result is always a String
            if headers["Content-Encoding", default: ""].lowercased() == "gzip" {
                parts.append("--compressed")
            }
            parts.append("--data-binary '@\(tmp.path)'")

        } else if !humanReadableBody.isEmpty {
            let escaped = humanReadableBody
                .replacingOccurrences(of: "'", with: #"'\''"#)
            parts.append("--data '\(escaped)'")
        }

        // 5. Pretty formatting
        return parts.joined(separator: " \\\n    ")
    }
}
