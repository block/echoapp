import EchoPluginAPI
import Foundation

/**
 * A ``URLProtocol`` implementation that proxies network requests to Echo.
 * Configure your ``URLSession`` to use this protocol to proxy requests to Echo when the client is connected to Echo.
 * When the client is not connected, ``EchoURLProtocol`` will ignore the request and it will be executed by ``URLSession`` normally.
 *
 * Example:
 * ```
 * let sessionConfig = URLSessionConfiguration.default
 * sessionConfig.protocolClasses = [EchoURLProtocol.self]
 *
 * let session = URLSession(configuration: sessionConfig)
 *
 * // Optional: if your network stack uses non-human-readable request/response bodies, set a custom body converter.
 * // By default, `EchoURLProtocol` uses `HTTPBodyConverters.UTF8()`, which is suitable for JSON, XML, and
 * // other text-based formats.
 * EchoURLProtocol.httpBodyConverter = MyCustomBodyConverter()
 * ```
 */
@MainActor public final class EchoURLProtocol: URLProtocol {

    // MARK: - Private Types

    private enum Error: LocalizedError {
        /// The client disconnected from Echo while the network request was in-flight
        case disconnected

        var errorDescription: String? {
            switch self {
            case .disconnected:
                "The client disconnected from Echo while a network request was in-flight"
            }
        }
    }

    // MARK: - Public Static Properties

    public static var echoClient: EchoClient = .shared
    public static var httpBodyConverter: HTTPBodyConverter = HTTPBodyConverters.UTF8()

    // MARK: - Private Properties

    /// The Task responsible for proxying the network request to Echo.
    private var proxyTask: Task<Void, Never>?

    // MARK: - Life Cycle

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    // MARK: - URLProtocol (Static methods)

    public override static func canInit(with request: URLRequest) -> Bool {
        echoClient.networkingPlugin.isConnected
    }

    public override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else {
            return false
        }
        return canInit(with: request)
    }

    public override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // MARK: - URLProtocol (Instance methods)

    public override func startLoading() {
        let plugin = Self.echoClient.networkingPlugin
        guard plugin.isConnected else {
            client?.urlProtocol(self, didFailWithError: Error.disconnected)
            return
        }

        let converter = Self.httpBodyConverter

        proxyTask = Task.detached { [self] in
            let echoRequest = self.echoRequest(using: converter)

            for await echoResponse in plugin.proxy(echoRequest) {
                if Task.isCancelled { break }

                switch echoResponse {
                case let .left(rawResponse):
                    let finalizedResponse = self.finalizeResponse(
                        for: rawResponse,
                        echoRequest: echoRequest,
                        using: converter
                    )
                    plugin.finalizeResponse(finalizedResponse)

                case let .right(humanReadableResponse):
                    do {
                        let finalizedResponse = try finalizeResponse(
                            for: humanReadableResponse,
                            echoRequest: echoRequest,
                            using: converter
                        )
                        plugin.finalizeResponse(finalizedResponse)
                    } catch {
                        // Invalid response; notify Echo to let the user try again.
                        plugin.reportHumanReadableResponseParsingError(error: error, response: humanReadableResponse)
                    }
                }
            }
        }
    }

    public override func stopLoading() {
        proxyTask?.cancel()
        proxyTask = nil
    }

    // MARK: - Private Methods

    internal nonisolated func echoRequest(
        using converter: HTTPBodyConverter
    ) -> Request {
        // The URL loading system converts request.httpBody to request.httpBodyStream automatically.
        // Read the stream to send the data to Echo.
        // We package the data up into a new URLRequest instance to send it to the client.
        // Note: we intentionally do not repurpose `self.request` here because the URL loading system
        // may mutate it in ways we don't expect. URLRequest is a value type, but it might be backed
        // by a class (e.g. NSURLRequest). Manually marshalling over the properties is safest.
        var urlRequest = URLRequest(url: request.url!)
        urlRequest.httpMethod = request.httpMethod
        urlRequest.httpBody = request.httpBodyStream?.readAll()
        urlRequest.allHTTPHeaderFields = request.allHTTPHeaderFields

        // Generate a human-readable version of the request body to display to the user
        let humanReadableBody: String
        do {
            humanReadableBody = try converter.prettyPrintBody(for: urlRequest)
        } catch {
            humanReadableBody = "Unable to render request body.\n\(error.detailedDescription)"
        }

        return Request(
            id: UUID().uuidString,
            url: urlRequest.url!,
            httpMethod: urlRequest.httpMethod ?? "GET",
            headers: urlRequest.allHTTPHeaderFields ?? [:],
            timestamp: Date(),
            humanReadableBody: humanReadableBody,
            rawBody: urlRequest.httpBody
        )
    }

    /// EchoApp.app provided a raw response. Forward it to the URLSession client and return a final, human-readable response to send to Echo.
    internal nonisolated func finalizeResponse(
        for rawResponse: RawResponse,
        echoRequest: Request,
        using converter: HTTPBodyConverter
    ) -> HumanReadableResponse {
        // Return the response to the URLSession client
        let urlResponse = HTTPURLResponse(
            url: echoRequest.url,
            statusCode: rawResponse.statusCode,
            httpVersion: nil,
            headerFields: rawResponse.headers
        )!
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        if let body = rawResponse.body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)

        // Make a final, human-readable response for Echo to display to the user
        let humanReadableBody: String
        do {
            humanReadableBody = try converter.prettyPrintBody(for: rawResponse, request: URLRequest(echoRequest))
        } catch {
            humanReadableBody = "Unable to render response body.\n\(error.detailedDescription)"
        }

        return HumanReadableResponse(
            requestID: echoRequest.id,
            headers: rawResponse.headers,
            body: humanReadableBody,
            statusCode: rawResponse.statusCode
        )
    }

    /// EchoApp.app proposed a human-readable response. Try to parse it into the expected format, then forward it to
    /// the URLSession client and return a final, human-readable response to send to Echo.
    internal nonisolated func finalizeResponse(
        for humanReadableResponse: HumanReadableResponse,
        echoRequest: Request,
        using converter: HTTPBodyConverter
    ) throws -> HumanReadableResponse {
        // Try to convert the human readable response to a format that the client can understand.
        // If this fails, our caller will catch the error and notify Echo. The user will be given the opportunity
        // to retry with a different proposed response.
        let data = try converter.parseHumanReadableResponseBody(for: humanReadableResponse, request: URLRequest(echoRequest))

        // Return the response to the URLSession client
        let urlResponse = HTTPURLResponse(
            url: echoRequest.url,
            statusCode: humanReadableResponse.statusCode,
            httpVersion: nil,
            headerFields: humanReadableResponse.headers
        )!
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)

        return humanReadableResponse
    }
}

// MARK: -

private extension URLRequest {

    init(_ echoRequest: Request) {
        self.init(url: echoRequest.url)
        httpMethod = echoRequest.httpMethod
        allHTTPHeaderFields = echoRequest.headers

        if let rawBody = echoRequest.rawBody {
            httpBody = rawBody
        }
    }
}

// MARK: -

private extension InputStream {
    func readAll() -> Data? {
        open()
        defer { close() }

        let bufferSize = 1024
        var data = Data()

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while hasBytesAvailable {
            let bytesRead = read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                return nil
            } else if bytesRead == 0 {
                // End of stream
                break
            }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}
