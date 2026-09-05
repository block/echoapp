import Foundation
import EchoPluginAPI

// An exchange between client and server
public struct Exchange: Identifiable, Equatable, CustomStringConvertible {

    public enum State: Equatable, Codable {
        /// **Non-Proxy Mode**: Echo is waiting for the client to report the response.
        case waitingForClientProvidedResponse

        /// **Proxy Mode**: a response has not yet been provided to the client.
        /// The associated response sink can be used to send a response to the client.
        /// If EchoApp.app previously provided an invalid response to the client, an exchange can end up back in this state
        /// with an error message explaining what went wrong. The user can then try sending a different response.
        case pendingResponse(responseSink: ResponseSink, errorMessage: String? = nil)

        /// **Proxy Mode**: the user has selected a response policy for this exchange (or the app chose one automatically).
        /// An appropriate response is being proposed to the client and we're waiting for the client to confirm.
        case sendingResponse(using: ResponsePolicy, responseSink: ResponseSink)

        /// **Both modes**: The client has provided the finalized response for this exchange.
        /// This is the response that the app has decided to use to respond to the request.
        case finalizedResponse(HumanReadableResponse, selectedPolicy: ResponsePolicy)
        
        /// A human-readable description of the current state
        public var description: String {
            switch self {
            case .waitingForClientProvidedResponse:
                return "Waiting for response"
            case .pendingResponse(_, let errorMessage):
                if errorMessage != nil {
                    return "Failed"
                } else {
                    return "Pending"
                }
            case .sendingResponse(let policy, _):
                return policy.name
            case .finalizedResponse(let response, let selectedPolicy):
                return "\(response.statusCode) (\(selectedPolicy.name))"
            }
        }

        var finalizedPolicyDescription: String? {
            switch self {
            case let .finalizedResponse(response, selectedPolicy):
                let code = response.statusCode
                return "\(code) - \(selectedPolicy.name)"
            default:
                return nil
            }
        }
    }

    public let id: UUID
    let request: Request
    var rule: Rule?
    var state: State

    init(
        id: UUID = .init(),
        request: Request,
        rule: Rule? = nil,
        state: State
    ) {
        self.id = id
        self.request = request
        self.rule = rule
        self.state = state
    }

    public var description: String {
        request.description
    }

    var response: HumanReadableResponse? {
        if case let .finalizedResponse(response, _) = state {
            return response
        }
        return nil
    }
}

// MARK: - Codable

extension Exchange: Codable {

    enum CodingKeys: CodingKey {
        case id, request, rule, state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            request: try container.decode(Request.self, forKey: .request),
            rule: try container.decodeIfPresent(Rule.self, forKey: .rule),
            state: try container.decode(State.self, forKey: .state)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(request, forKey: .request)
        try container.encodeIfPresent(rule, forKey: .rule)
        try container.encode(state, forKey: .state)
    }
}

extension Exchange.State {

    enum CodingError: Error {
        /// `waitingForClientProvidedResponse` states can't be encoded because they require
        /// a live client-server connection
        case cannotEncodeWaitingForClientProvidedResponse

        /// `sendingResponse` states can't be encoded because they require
        /// a live client-server connection
        case cannotEncodeSendingResponse

        /// `pendingResponse` states can't be encoded because they contain a closure
        /// used to send a network response to a client.
        case cannotEncodePendingResponse
    }

    enum CodingKeys: CodingKey {
        case finalizedResponse
        case selectedPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let response = try container.decodeIfPresent(HumanReadableResponse.self, forKey: .finalizedResponse),
           let selectedPolicy = try container.decodeIfPresent(ResponsePolicy.self, forKey: .selectedPolicy) {
            self = .finalizedResponse(response, selectedPolicy: selectedPolicy)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.finalizedResponse,
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "`finalizedResponse` and `selectedPolicy` are required for finalized state"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .waitingForClientProvidedResponse:
            throw CodingError.cannotEncodeWaitingForClientProvidedResponse
        case .pendingResponse:
            throw CodingError.cannotEncodePendingResponse
        case .sendingResponse:
            throw CodingError.cannotEncodeSendingResponse
        case let .finalizedResponse(response, selectedPolicy):
            try container.encode(response, forKey: .finalizedResponse)
            try container.encode(selectedPolicy, forKey: .selectedPolicy)
        }
    }
}

// MARK: - Helpers

extension Exchange {

    /// Returns an optional `String` for the given section and tab.
    /// - Parameters:
    ///   - exchangeSection: The section we want the information for. This is either `Request` or `Response`
    ///   - tab: The tab in the given section. This is either `Headers`, `Body`, or `Raw`
    /// - Returns: The text in that given section, if it exists.
    public func textFor(_ exchangeSection: ExchangeSection, tab: ExchangeDetailTab) -> String? {
        switch exchangeSection {
        case .request:
            switch tab {
            case .headers:
                return request.headers.prettyPrintedJSON
            case .body:
                return request.humanReadableBody
            case .raw:
                return request.networkingRawBodyDisplayString
            }
        case .response:
            switch tab {
            case .headers:
                return response?.headers.prettyPrintedJSON
            case .body:
                return response?.body
            case .raw:
                return response?.body
            }
        }
    }

    /// Returns a formatted string with complete exchange information including request and response
    public func completeInformation() -> String {
        var parts: [String] = []
        
        parts.append("\(request.httpMethod) \(request.url.absoluteString)")
        parts.append("")
        // Request Information
        parts.append("# Request")
        parts.append("")
        parts.append("**Host:** `\(request.url.host ?? "unknown")`")
        parts.append("**Endpoint:** `\(request.endpoint.path)`")
        parts.append("**Timestamp:** \(request.timestamp.formatted())")
        parts.append("")
        
        // Request Headers
        parts.append("### Headers")
        parts.append("")
        if request.headers.isEmpty {
            parts.append("*(none)*")
        } else {
            parts.append("```yaml")
            for (key, value) in request.headers.sorted(by: { $0.key < $1.key }) {
                parts.append("\(key): \(value)")
            }
            parts.append("```")
        }
        parts.append("")
        
        // Request Body
        parts.append("### Body")
        parts.append("")
        if request.humanReadableBody.isEmpty {
            parts.append("*(empty)*")
        } else {
            parts.append("```json")
            parts.append(request.humanReadableBody)
            parts.append("```")
        }
        parts.append("")
        parts.append("---")
        parts.append("")
        
        // Response Information
        parts.append("# Response")
        parts.append("")
        
        if let response = response {
            parts.append("**Status Code:** `\(response.statusCode)`")
            
            if case let .finalizedResponse(_, selectedPolicy) = state {
                parts.append("**Echo Response Policy:** \(selectedPolicy.name)")
            }
            
            parts.append("")
            
            // Response Headers
            parts.append("### Headers")
            parts.append("")
            if response.headers.isEmpty {
                parts.append("*(none)*")
            } else {
                parts.append("```yaml")
                for (key, value) in response.headers.sorted(by: { $0.key < $1.key }) {
                    parts.append("\(key): \(value)")
                }
                parts.append("```")
            }
            parts.append("")
            
            // Response Body
            parts.append("### Body")
            parts.append("")
            if response.body.isEmpty {
                parts.append("*(empty)*")
            } else {
                parts.append("```json")
                parts.append(response.body)
                parts.append("```")
            }
        } else {
            parts.append("**Status:** \(state.description)")
        }
        
        return parts.joined(separator: "\n")
    }
}

// MARK: -

extension Data {

    var networkingRawDisplayString: String {
        if let string = String(data: self, encoding: .utf8) {
            return string
        }
        return base64EncodedString()
    }
}

extension Request {

    var networkingRawBodyDisplayString: String {
        rawBody?.networkingRawDisplayString ?? humanReadableBody
    }
}

// MARK: - MCP Serialization

extension Exchange {

    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    /// Lightweight summary for list_exchanges tool results.
    public func mcpSummary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "method": request.httpMethod,
            "url": request.url.absoluteString,
            "timestamp": Exchange.iso8601.string(from: request.timestamp),
            "state": mcpStateDescription,
        ]
        if let statusCode = response?.statusCode {
            dict["statusCode"] = statusCode
        }
        return dict
    }

    /// Full detail for get_exchange tool results.
    public func mcpDetail() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "state": mcpStateDescription,
            "timestamp": Exchange.iso8601.string(from: request.timestamp),
            "request": [
                "method": request.httpMethod,
                "url": request.url.absoluteString,
                "headers": request.headers,
                "body": request.humanReadableBody,
            ] as [String: Any],
        ]
        if let r = response {
            dict["response"] = [
                "statusCode": r.statusCode,
                "headers": r.headers,
                "body": r.body,
            ] as [String: Any]
        }
        return dict
    }

    private var mcpStateDescription: String {
        switch state {
        case .waitingForClientProvidedResponse: return "waitingForClientProvidedResponse"
        case .pendingResponse: return "pendingResponse"
        case .sendingResponse: return "sendingResponse"
        case .finalizedResponse: return "finalizedResponse"
        }
    }
}
