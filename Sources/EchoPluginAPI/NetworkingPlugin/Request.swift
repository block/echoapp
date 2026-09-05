
import Foundation

public struct Request: Equatable, Codable, CustomStringConvertible {
    /// Uniquely identifies this request
    public var id: String

    public var url: URL
    public var httpMethod: String
    public var headers: [String: String]

    public var timestamp: Date

    public var humanReadableBody: String
    public var rawBody: Data?

    public var endpoint: Endpoint {
        if #available(iOS 16.0, *) {
            Endpoint(path: url.path(percentEncoded: false))
        } else {
            Endpoint(path: url.path)
        }
    }

    public init(
        id: String,
        url: URL,
        httpMethod: String,
        headers: [String : String],
        timestamp: Date,
        humanReadableBody: String,
        rawBody: Data?
    ) {
        self.id = id
        self.url = url
        self.httpMethod = httpMethod
        self.headers = headers
        self.timestamp = timestamp
        self.humanReadableBody = humanReadableBody
        self.rawBody = rawBody
    }

    public var description: String {
        endpoint.description
    }
}
