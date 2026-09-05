import EchoPluginAPI
import Foundation

extension EchoURLProtocol {

    /// Converts raw request and response bodies to human-readable strings and vice-versa
    public protocol HTTPBodyConverter {

        /**
         Convert raw **request** data (e.g. protobuf data) into a human-readable format (e.g. JSON)
         - Parameters:
            - request: The original request initiated by the client
         */
        func prettyPrintBody(
            for request: URLRequest
        ) throws -> String

        /**
            Convert raw **response** data (e.g. protobuf data) into a human-readable format (e.g. JSON)
        - Parameters:
            - response: The raw response obtained from the Echo server
            - request: The original request initiated by the client
        - Returns: A human-readable string representation of the response body
         */
        func prettyPrintBody(
            for response: RawResponse,
            request: URLRequest
        ) throws -> String

        /**
         Convert a human-readable response body (e.g. a JSON fixture) into the expected raw data type (e.g. protobuf data)
         - Parameters:
            - response: A human-readable response obtained from the Echo server
            - request: The original request initiated by the client
         - Returns: The raw data representation of the human-readable response body
         */
        func parseHumanReadableResponseBody(
            for response: HumanReadableResponse,
            request: URLRequest
        ) throws -> Data
    }

    /// A shared namespace for `HTTPBodyConverter` implementations
    public enum HTTPBodyConverters {}
}

// MARK: -

extension EchoURLProtocol.HTTPBodyConverters {

    /// A converter that assumes the request and response bodies are UTF-8 strings
    /// This is the default converter set on `EchoURLProtocol` and is suitable for JSON, XML, and other text-based formats
    public final class UTF8: EchoURLProtocol.HTTPBodyConverter {
        public init() {}
        
        public func prettyPrintBody(for request: URLRequest) throws -> String {
            guard let data = request.httpBody else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? "Not a UTF-8 string"
        }

        public func prettyPrintBody(for response: RawResponse, request: URLRequest) throws -> String {
            guard let data = response.body else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? "Not a UTF-8 string"
        }

        public func parseHumanReadableResponseBody(
            for response: HumanReadableResponse,
            request: URLRequest
        ) throws -> Data {
            Data(response.body.utf8)
        }
    }
}
