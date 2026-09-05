import Foundation

/// A semantic version type that supports comparison of version strings
public struct Version: Comparable, Equatable, Hashable {
    public let rawValue: String
    private let components: [Int]
    
    public init(_ versionString: String) {
        self.rawValue = versionString
        
        // Parse version components (remove 'v' prefix if present)
        let cleanVersion = versionString.hasPrefix("v") ? String(versionString.dropFirst()) : versionString
        self.components = cleanVersion
            .split(separator: ".")
            .compactMap { Int($0) }
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: Version, rhs: Version) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        
        for i in 0..<maxCount {
            let lhsPart = i < lhs.components.count ? lhs.components[i] : 0
            let rhsPart = i < rhs.components.count ? rhs.components[i] : 0
            
            if lhsPart < rhsPart {
                return true
            } else if lhsPart > rhsPart {
                return false
            }
        }
        
        return false // Equal versions
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        return rawValue
    }
}

// MARK: - Convenience Extensions

extension Version: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}