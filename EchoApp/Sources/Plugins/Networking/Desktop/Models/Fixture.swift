import Foundation

/// Describes a network response fixture on disk
public struct Fixture: Hashable, Codable, Identifiable {

    enum Kind: Hashable {
        /// A text-based fixture
        case text(contentType: String)
    }

    let kind: Kind
    let url: URL

    public var id: String {
        url.absoluteString
    }

    var contentType: String {
        switch kind {
        case let .text(contentType):
            contentType
        }
    }
}

extension Fixture.Kind: Equatable {

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.text(lhsType), .text(rhsType)):
            return lhsType == rhsType
        }
    }

}

extension Fixture.Kind: Codable {

    private enum CodingKeys: CodingKey {
        case proto, text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contentType = try container.decode(String.self, forKey: .text)
        self = .text(contentType: contentType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(contentType):
            try container.encode(contentType, forKey: .text)
        }
    }
}
