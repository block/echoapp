
import Foundation

/// An HTTP response sent to the client
public struct Response<Body>: Codable, Equatable where Body: Codable & Equatable {
    /// Identifies the request this response corresponds to
    public let requestID: String

    public let headers: [String: String]
    public let body: Body
    public let statusCode: Int

    public init(
        requestID: String,
        headers: [String: String] = [:],
        body: Body,
        statusCode: Int
    ) {
        self.requestID = requestID
        self.headers = headers
        self.body = body
        self.statusCode = statusCode
    }

    public var isSuccessful: Bool {
        (200..<400) ~= statusCode
    }

    public var statusCodeDescription: String {
        "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"
    }
}
