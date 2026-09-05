
import Foundation

public struct Endpoint: Identifiable, Equatable, Codable, Hashable, CustomStringConvertible {
    public let path: String

    public init(path: String) {
        self.path = Endpoint.normalizedPath(path)
    }

    public var description: String {
        path
    }

    public var id: String {
        path
    }

    public var containsWildcard: Bool {
        path.contains("*")
    }

    /// Returns true if `self` and `other` refer to the same path, accounting for wildcards.
    /// A wildcard matches exactly one path component, and the wildcard must be the only
    /// character in the path component. A path component with more than one character
    /// is considered verbatim text instead of a wildcard.
    /// Examples:
    /// `2.0/foo/bar` matches `2.0/foo/bar`
    /// `2.0/*/bar/*` matches `2.0/foo/bar/baz`
    /// `2.0/*` does not match `2.0/foo/bar`
    /// `2.0/*bar` does not match `2.0/foobar`
    public func matches(_ other: Self) -> Bool {
        let components = path.components(separatedBy: "/")
        let otherComponents = other.path.components(separatedBy: "/")

        guard components.count == otherComponents.count else {
            return false
        }

        return zip(components, otherComponents).allSatisfy { a, b in
            a == b || a == "*" || b == "*"
        }
    }

    /// Returns a path with a single leading slash and no trailing slashes
    /// (e.g. `v1/example/get-profile/` -> `/v1/example/get-profile`
    public static func normalizedPath(_ path: String) -> String {
        "/\(path.components(separatedBy: "/").compactMap { $0.isEmpty ? nil : $0 }.joined(separator: "/"))"
    }
}
