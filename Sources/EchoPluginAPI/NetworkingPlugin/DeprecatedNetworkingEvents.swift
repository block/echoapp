import Foundation

/// Maintained for backwards compatibility
@available(*, deprecated, message: "Use NetworkingPluginClientEvent instead.")
public enum DeprecatedNetworkingPluginClientEvent: Codable {
    case request(Request)
    case response(Response)

    public struct Request: Equatable, Codable, CustomStringConvertible {
        /// Uniquely identifies this request
        public var id: String

        public var endpoint: Endpoint // Matches all HTTP Methods
        public var httpMethod: String
        public var headers: [String: String]

        public var timestamp: Date

        public var queryParameters: [String: String]

        public var humanReadableBody: String

        public init(
            id: String,
            endpoint: Endpoint,
            httpMethod: String,
            headers: [String : String],
            timestamp: Date,
            queryParameters: [String : String],
            humanReadableBody: String
        ) {
            self.id = id
            self.endpoint = endpoint
            self.httpMethod = httpMethod
            self.headers = headers
            self.timestamp = timestamp
            self.queryParameters = queryParameters
            self.humanReadableBody = humanReadableBody
        }

        public var description: String {
            var components = URLComponents(string: endpoint.path)

            if !queryParameters.isEmpty {
                components?.queryItems = queryParameters.map { URLQueryItem(name: $0, value: $1) }
            }
            return components?.string ?? endpoint.description
        }
    }

    public struct Response: Codable, Equatable {
        /// Identifies the request this response corresponds to
        public let requestID: String
        public let headers: [String: String]
        public let humanReadableBody: String
        public let statusCode: Int

        public init(
            requestID: String,
            headers: [String: String] = [:],
            humanReadableBody: String,
            statusCode: Int
        ) {
            self.requestID = requestID
            self.headers = headers
            self.humanReadableBody = humanReadableBody
            self.statusCode = statusCode
        }
    }
}
