import Foundation

/// Describes the strategy for obtaining a response for an incoming request
public enum ResponsePolicy: Hashable, Identifiable {
    case alwaysAsk
    case fixture(Fixture)
    case custom(CustomResponsePolicy)
    case proxy

    public var id: String {
        switch self {
        case let .custom(policy):
            policy.id.uuidString
        case let .fixture(fixture):
            fixture.id
        default:
            name
        }
    }

    var name: String {
        switch self {
        case .alwaysAsk:
            return "Always Ask"

        case let .fixture(fixture):
            return fixture.url.pathComponents.last!

        case .proxy:
            return "Proxy Original Request"

        case let .custom(customPolicy):
            return customPolicy.name
        }
    }

    var symbol: String {
        switch self {
        case .alwaysAsk:
            return "questionmark.app.dashed"

        case .fixture:
            return "arrow.down.app.fill"

        case .proxy:
            return "arrow.up.arrow.down.square.fill"

        case .custom:
            return "arrow.up.to.line.square.fill"
        }
    }
}

// MARK: - Codable

extension ResponsePolicy: Codable {

    private enum CodingKeys: CodingKey {
        case alwaysAsk, fixture, custom, proxy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.allKeys.contains(.alwaysAsk) {
            self = .alwaysAsk
        } else if let fixture = try? container.decode(Fixture.self, forKey: .fixture) {
            self = .fixture(fixture)
        } else if let customPolicy = try? container.decodeIfPresent(CustomResponsePolicy.self, forKey: .custom) {
            self = .custom(customPolicy)
        } else {
            self = .proxy
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .alwaysAsk:
            try container.encode(true, forKey: .alwaysAsk)

        case let .fixture(fixture):
            try container.encode(fixture, forKey: .fixture)

        case let .custom(customPolicy):
            try container.encode(customPolicy, forKey: .custom)

        case .proxy:
            try container.encode(true, forKey: .proxy)
        }
    }
}

// MARK: -

public struct CustomResponsePolicy: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var value: Value

    public enum Kind: String, Codable, Hashable, CaseIterable, CustomStringConvertible {
        case reroute = "Reroute"
        case httpStatusCode = "HTTP Status Code"

        public var description: String { rawValue }

        public var helpText: String {
            switch self {
            case .reroute:
                """
                Change the base URL of the request.
                For example: enter "http://localhost" to reroute all requests to localhost.
                "https://api.example.com/foo/bar" becomes "http://localhost/foo/bar"
                """
            case .httpStatusCode:
                "Send a specific HTTP status code in the response"
            }
        }
    }

    public enum Value: Codable, Hashable, CustomStringConvertible {
        case reroute(newBaseURL: URL = URL(string: "http://localhost")!)
        case httpStatusCode(Int? = 200)

        public var description: String {
            switch self {
            case let .reroute(url):
                url.absoluteString

            case let .httpStatusCode(code):
                code.map(String.init) ?? ""
            }
        }

        public var kind: Kind {
            switch self {
            case .reroute: .reroute
            case .httpStatusCode: .httpStatusCode
            }
        }
    }

    public static var defaults: [Self] {
        [
            .localHost,
            .internalServerError,
            .badRequest,
            .unauthorized,
        ]
    }

    static let localHost = Self.init(name: "Proxy to Local Host", value: .reroute())
    static let internalServerError = Self.error(statusCode: 500)
    static let badRequest = Self.error(statusCode: 400)
    static let unauthorized = Self.error(statusCode: 401)

    static func error(statusCode: Int) -> Self {
        return .init(
            name: HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized,
            value: .httpStatusCode(statusCode)
        )
    }
}
