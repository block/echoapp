import Foundation

/// A semantic version type that supports comparison of version strings.
///
/// Retained temporarily while callers migrate to `EchoAppReleaseVersion`.
public struct Version: Comparable, Equatable, Hashable {
    public let rawValue: String
    private let components: [Int]

    public init(_ versionString: String) {
        self.rawValue = versionString
        let cleanVersion = versionString.hasPrefix("v") ? String(versionString.dropFirst()) : versionString
        self.components = cleanVersion.split(separator: ".").compactMap { Int($0) }
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let lhsPart = index < lhs.components.count ? lhs.components[index] : 0
            let rhsPart = index < rhs.components.count ? rhs.components[index] : 0
            if lhsPart != rhsPart { return lhsPart < rhsPart }
        }
        return false
    }

    public var description: String { rawValue }

}

extension Version: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(value) }
}

/// The exact public release version, distinct from Apple's numeric bundle fields.
public struct EchoAppReleaseVersion: Comparable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public let buildMetadata: String?
    private let numericComponents: [String]
    private let prereleaseIdentifiers: [PrereleaseIdentifier]?

    /// Parses a Semantic Version 2.0.0 value without a Git tag prefix.
    public init?(_ rawValue: String) {
        let buildParts = rawValue.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard buildParts.count <= 2,
              let coreAndPrerelease = buildParts.first,
              !coreAndPrerelease.isEmpty else {
            return nil
        }

        let buildMetadata = buildParts.count == 2 ? String(buildParts[1]) : nil
        guard buildMetadata.map({ Self.isValidIdentifierList($0, rejectsNumericLeadingZeroes: false) }) ?? true else {
            return nil
        }

        let prereleaseParts = coreAndPrerelease.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericComponents = prereleaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numericComponents.count == 3,
              numericComponents.allSatisfy(Self.isValidNumericIdentifier) else {
            return nil
        }

        let prereleaseIdentifiers: [PrereleaseIdentifier]?
        if prereleaseParts.count == 2 {
            let prerelease = String(prereleaseParts[1])
            guard Self.isValidIdentifierList(prerelease, rejectsNumericLeadingZeroes: true) else {
                return nil
            }
            prereleaseIdentifiers = prerelease.split(separator: ".").map(PrereleaseIdentifier.init)
        } else {
            prereleaseIdentifiers = nil
        }

        self.rawValue = rawValue
        self.numericComponents = numericComponents.map(String.init)
        self.buildMetadata = buildMetadata
        self.prereleaseIdentifiers = prereleaseIdentifiers
    }

    /// Parses an EchoApp GitHub release tag. Both historical unprefixed tags
    /// and canonical `v<semver>` tags are accepted when reading releases.
    public init?(githubReleaseTag tag: String) {
        var version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let components = version.split(separator: ".")
        if components.count == 2, components.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            version += ".0"
        }
        self.init(version)
    }

    /// The bare Semantic Version tag emitted for GitHub and consumed by SwiftPM.
    public var gitTag: String { rawValue }

    /// The numeric value required by `CFBundleShortVersionString`.
    public var marketingVersion: String { numericComponents.joined(separator: ".") }

    /// The exact Semantic Version reported by `echoapp --version`.
    public var cliVersion: String { rawValue }

    public var isPrerelease: Bool { prereleaseIdentifiers != nil }

    public var description: String { rawValue }

    /// Returns whether this version has higher Semantic Version precedence.
    /// Build metadata is deliberately ignored, as required by SemVer 2.0.0.
    public func hasHigherPrecedence(than other: EchoAppReleaseVersion) -> Bool {
        Self.isPrecedenceLess(other, than: self)
    }

    /// The current app version, preferring the exact release value over Apple's
    /// numeric-only marketing version.
    public static func current(in bundle: Bundle = .main) -> EchoAppReleaseVersion {
        if let exactVersion = bundle.object(forInfoDictionaryKey: "EchoAppReleaseVersion") as? String,
           let releaseVersion = EchoAppReleaseVersion(exactVersion) {
            return releaseVersion
        }
        if let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let releaseVersion = EchoAppReleaseVersion(githubReleaseTag: marketingVersion) {
            return releaseVersion
        }
        return EchoAppReleaseVersion("0.0.0-dev")!
    }

    public static func < (lhs: EchoAppReleaseVersion, rhs: EchoAppReleaseVersion) -> Bool {
        if Self.isPrecedenceLess(lhs, than: rhs) { return true }
        if Self.isPrecedenceLess(rhs, than: lhs) { return false }
        return Self.isBuildMetadataLess(lhs.buildMetadata, than: rhs.buildMetadata)
    }

    private static func isPrecedenceLess(
        _ lhs: EchoAppReleaseVersion,
        than rhs: EchoAppReleaseVersion
    ) -> Bool {
        for (lhsComponent, rhsComponent) in zip(
            lhs.numericComponents,
            rhs.numericComponents
        ) {
            if lhsComponent != rhsComponent {
                return Self.isNumericallyLess(lhsComponent, than: rhsComponent)
            }
        }

        switch (lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (.some(lhsIdentifiers), .some(rhsIdentifiers)):
            for (lhsIdentifier, rhsIdentifier) in zip(lhsIdentifiers, rhsIdentifiers) {
                if lhsIdentifier != rhsIdentifier {
                    return lhsIdentifier < rhsIdentifier
                }
            }
            if lhsIdentifiers.count != rhsIdentifiers.count {
                return lhsIdentifiers.count < rhsIdentifiers.count
            }
            return false
        }
    }

    /// SemVer build metadata does not change precedence. We use it only as a
    /// deterministic tie-breaker so this `Comparable` value remains a total
    /// order consistent with its exact release identity and `Equatable`.
    private static func isBuildMetadataLess(_ lhs: String?, than rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): false
        case (nil, .some): true
        case (.some, nil): false
        case let (.some(lhs), .some(rhs)): lhs < rhs
        }
    }

    private static func isValidNumericIdentifier(_ value: Substring) -> Bool {
        !value.isEmpty
            && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
            && (value.count == 1 || value.first != "0")
    }

    private static func isValidIdentifierList(
        _ value: String,
        rejectsNumericLeadingZeroes: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }

        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({
                      ($0 >= 48 && $0 <= 57)
                          || ($0 >= 65 && $0 <= 90)
                          || ($0 >= 97 && $0 <= 122)
                          || $0 == 45
                  }) else {
                return false
            }
            return !rejectsNumericLeadingZeroes || !Self.isNumericIdentifierWithLeadingZero(identifier)
        }
    }

    private static func isNumericIdentifierWithLeadingZero(_ value: Substring) -> Bool {
        value.count > 1 && value.first == "0" && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    fileprivate static func isNumericallyLess(_ lhs: String, than rhs: String) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count < rhs.count
        }
        return lhs < rhs
    }
}

private struct PrereleaseIdentifier: Comparable, Equatable, Hashable {
    let value: String

    init(_ value: Substring) {
        self.value = String(value)
    }

    static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
        let lhsIsNumeric = lhs.value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        let rhsIsNumeric = rhs.value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }

        switch (lhsIsNumeric, rhsIsNumeric) {
        case (true, true):
            return EchoAppReleaseVersion.isNumericallyLess(lhs.value, than: rhs.value)
        case (true, false):
            return true
        case (false, true):
            return false
        case (false, false):
            return lhs.value < rhs.value
        }
    }
}
