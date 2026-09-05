import Foundation
import EchoPluginAPI

/// A response sink is used to send a response to the client. One response sink is created for each incoming request.
public final class ResponseSink: Identifiable, Equatable {

    /// A closure used to send a response to the client
    typealias ResponseSender = (NetworkingPluginServerEvent) -> Void
    /// A closure used to report errors back to the server
    typealias ErrorReporter = (String, String) -> Void
    public let id = UUID()

    private var responseSender: ResponseSender
    private var errorReporter: ErrorReporter?

    // MARK: - Life Cycle

    init(responseSender: @escaping ResponseSender, errorReporter: ErrorReporter? = nil) {
        self.responseSender = responseSender
        self.errorReporter = errorReporter
    }

    // MARK: - Public Methods

    func send(_ response: NetworkingPluginServerEvent) {
        responseSender(response)
    }

    // MARK: - Equatable

    public static func == (lhs: ResponseSink, rhs: ResponseSink) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: -

extension ResponseSink {

    /// Convenience method to send a fixture to the client.
    func send(
        _ fixture: Fixture,
        requestID: String
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let body = try String(contentsOf: fixture.url)

                let response = HumanReadableResponse(
                    requestID: requestID,
                    headers: ["Content-Type": fixture.contentType],
                    body: body,
                    statusCode: StatusCodes.ok
                )
                self.send(.proposedHumanReadableResponse(response))
            } catch {
                let errorMessage = """
                    Failed to read fixture file: \(fixture.url.lastPathComponent)
                    
                    Error: \(error.localizedDescription)
                    
                    Please ensure the fixture file exists and is readable.
                    """
                DispatchQueue.main.async {
                    self.errorReporter?(errorMessage, requestID)
                }
            }
        }
    }

    /// Convenience method to send a custom response to the client.
    func sendCustomResponsePolicy(
        _ policy: CustomResponsePolicy,
        request: Request
    ) {
        switch policy.value {
        case let .httpStatusCode(statusCode):
            let response = RawResponse(
                requestID: request.id,
                body: nil,
                statusCode: statusCode ?? 0
            )
            self.send(.rawResponse(response))

        case let .reroute(newBaseURL):
            self.proxyRequest(request, replacementBaseURL: newBaseURL)
        }
    }

    /// Convenience method to proxy the provided request to an environment (staging | production)
    /// and send the response to the client.
    /// - Parameter request: The request to proxy
    /// - Parameter replacementBaseURL: The base URL to use. `nil` will use the original base URL.
    func proxyRequest(
        _ request: Request,
        replacementBaseURL: URL? = nil
    ) {
        guard let urlRequest = URLRequest.makeProxyRequest(from: request, replacementBaseURL: replacementBaseURL) else {
            // This shouldn't happen if validation is working correctly in the Rules UI
            // Send an error response to the client
            self.sendCustomResponsePolicy(
                .error(statusCode: StatusCodes.internalServerError),
                request: request
            )
            return
        }
        URLSession(configuration: .default).dataTask(with: urlRequest) {
            data,
            urlResponse,
            error in
            guard error == nil else {
                self.sendCustomResponsePolicy(
                    .error(statusCode: (urlResponse as? HTTPURLResponse)?.statusCode ?? StatusCodes.internalServerError),
                    request: request
                )
                return
            }
            guard let urlResponse = urlResponse as? HTTPURLResponse else {
                // Unexpected response type - send error
                self.sendCustomResponsePolicy(
                    .error(statusCode: StatusCodes.internalServerError),
                    request: request
                )
                return
            }

            guard let headers = urlResponse.allHeaderFields as? [String: String] else {
                // Reference: https://tools.ietf.org/html/rfc7230#section-3.2.4
                // Headers should always be strings, but send error if not
                self.sendCustomResponsePolicy(
                    .error(statusCode: StatusCodes.internalServerError),
                    request: request
                )
                return
            }
            
            let response = RawResponse(
                requestID: request.id,
                headers: headers,
                body: data,
                statusCode: urlResponse.statusCode
            )
            self.send(.rawResponse(response))
        }.resume()
    }

}

// MARK: -

private enum StatusCodes {
    static let ok = 200
    static let internalServerError = 500
}
