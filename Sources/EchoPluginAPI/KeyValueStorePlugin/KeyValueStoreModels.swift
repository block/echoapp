import Foundation

// MARK: - Core Data Models

/// A type-safe wrapper for values that can be stored in key-value stores
public enum EchoCodableValue: Codable, Hashable, Equatable {

    // MARK: - Static Date Formatter

    /// Shared date formatter for consistent date display across all locales
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    case string(String)
    case integer(Int32)
    case integer16(Int16)
    case integer64(Int64)
    case float(Float)
    case double(Double)
    case boolean(Bool)
    case data(Data)
    case date(Date)
    case array([EchoCodableValue])
    case dictionary([String: EchoCodableValue])
    case url(URL)
    case null

    public var type: EchoKeyValueType {
        switch self {
        case .string: return .string
        case .integer: return .integer
        case .integer16: return .integer16
        case .integer64: return .integer64
        case .float: return .float
        case .double: return .double
        case .boolean: return .boolean
        case .data: return .data
        case .date: return .date
        case .array: return .array
        case .dictionary: return .dictionary
        case .url: return .url
        case .null: return .unknown
        }
    }

    public var displayValue: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .integer16(let value): return String(value)
        case .integer64(let value): return String(value)
        case .float(let value): return String(value)
        case .double(let value): return String(value)
        case .boolean(let value): return String(value)
        case .data(let value): return "\(value.count) bytes"
        case .date(let value): return Self.dateFormatter.string(from: value)
        case .array(let values): return "(\(values.count) items) \(values.description)"
        case .dictionary(let dict): return "(\(dict.count) keys) \(dict.description)"
        case .url(let value): return value.absoluteString
        case .null: return "null"
        }
    }

    public var detailDisplayValue: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .integer16(let value): return String(value)
        case .integer64(let value): return String(value)
        case .float(let value): return String(value)
        case .double(let value): return String(value)
        case .boolean(let value): return String(value)
        case .data(let value): return String(value.base64EncodedString())
        case .date(let value): return Self.dateFormatter.string(from: value)
        case .array(let values):
            let anyArray = values.map { $0.anyValue }
            return prettyPrintedJSONFromAny(anyArray) ?? "[\(values.count) items]"
        case .dictionary(let dict):
            let anyDict = dict.mapValues { $0.anyValue }
            return prettyPrintedJSONFromAny(anyDict) ?? "{\(dict.count) keys}"
        case .url(let value): return value.absoluteString
        case .null: return "null"
        }
    }

    private func prettyPrintedJSONFromAny(_ value: Any) -> String? {
        do {
            let jsonSafeValue = makeJSONSafe(value)
            let data = try JSONSerialization.data(withJSONObject: jsonSafeValue, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func makeJSONSafe(_ value: Any) -> Any {
        switch value {
        case let data as Data:
            return data.base64EncodedString()
        case let date as Date:
            return date.timeIntervalSince1970
        case let url as URL:
            return url.absoluteString
        case let array as [Any]:
            return array.map { makeJSONSafe($0) }
        case let dict as [String: Any]:
            return dict.mapValues { makeJSONSafe($0) }
        case let dict as [AnyHashable: Any]:
            var stringDict: [String: Any] = [:]
            for (key, val) in dict {
                stringDict[String(describing: key)] = makeJSONSafe(val)
            }
            return stringDict
        default:
            return value
        }
    }

    // Convert from Any (for UserDefaults compatibility)
    public init(from anyValue: Any) {
        switch anyValue {
        case let string as String:
            self = .string(string)
        case let bool as Bool:
            // Check for Bool first before Int, since Bool can be coerced to Int
            self = .boolean(bool)
        case let number as NSNumber:
            // Handle NSNumber objects that UserDefaults often returns
            // Check if it's actually a boolean stored as NSNumber
            self = number.toEchoCodeableValue()
        case let int as Int32:
            self = .integer(int)
        case let int as Int16:
            self = .integer16(int)
        case let int as Int64:
            self = .integer64(int)
        case let float as Float:
            self = .float(float)
        case let double as Double:
            self = .double(double)
        case let data as Data:
            self = .data(data)
        case let date as Date:
            self = .date(date)
        case let url as URL:
            self = .url(url)
        case let array as [Any]:
            self = .array(array.map { EchoCodableValue(from: $0) })
        case let dict as [String: Any]:
            self = .dictionary(dict.mapValues { EchoCodableValue(from: $0) })
        default:
            self = .string(String(describing: anyValue))
        }
    }

    // Convert to Any (for UserDefaults compatibility)
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .integer(let value): return value
        case .integer16(let value): return value
        case .integer64(let value): return value
        case .float(let value): return value
        case .double(let value): return value
        case .boolean(let value): return value
        case .data(let value): return value
        case .date(let value): return value
        case .url(let value): return value
        case .array(let values): return values.map { $0.anyValue }
        case .dictionary(let dict): return dict.mapValues { $0.anyValue }
        case .null: return NSNull()
        }
    }
}

/// Represents the type of a key-value entry
public enum EchoKeyValueType: String, Codable, CaseIterable {
    case string
    case integer
    case integer16
    case integer64
    case float
    case double
    case boolean
    case data
    case date
    case array
    case dictionary
    case url
    case unknown

    public var displayName: String {
        switch self {
        case .string: return "String"
        case .integer: return "Integer (32-bit)"
        case .integer16: return "Integer (16-bit)"
        case .integer64: return "Integer (64-bit)"
        case .float: return "Float"
        case .double: return "Double"
        case .boolean: return "Boolean"
        case .data: return "Data"
        case .date: return "Date"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        case .url: return "URL"
        case .unknown: return "Unknown"
        }
    }
}

/// Tracks changes to values over time
public struct EchoValueModification: Codable, Hashable, Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let oldValue: EchoCodableValue?
    public let newValue: EchoCodableValue
    public let source: ModificationSource
    public let changeDescription: String
    public let changeId: UUID?

    public enum ModificationSource: String, Codable {
        case app = "App"
        case desktop = "Echo Desktop"
        case system = "System"
        case unknown = "Unknown"
    }

    public init(
        timestamp: Date = Date(),
        oldValue: EchoCodableValue?,
        newValue: EchoCodableValue,
        source: ModificationSource,
        changeDescription: String,
        changeId: UUID? = nil
    ) {
        self.timestamp = timestamp
        self.oldValue = oldValue
        self.newValue = newValue
        self.source = source
        self.changeDescription = changeDescription
        self.changeId = changeId
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, oldValue, newValue, source, changeDescription, changeId
    }
}

/// A single key-value entry in a store
public struct EchoKeyValueEntry: Codable, Hashable, Identifiable {
    public let key: String
    public let value: EchoCodableValue
    public let type: EchoKeyValueType
    public let isEditable: Bool
    public let lastModified: Date?
    public let modificationHistory: [EchoValueModification]

    public var id: String {
        return key
    }

    public var displayValue: String {
        value.displayValue
    }

    public var detailDisplayValue: String {
        value.detailDisplayValue
    }

    public var formattedType: String {
        type.displayName
    }

    public init(
        key: String,
        value: EchoCodableValue,
        type: EchoKeyValueType,
        isEditable: Bool,
        lastModified: Date? = nil,
        modificationHistory: [EchoValueModification] = []
    ) {
        self.key = key
        self.value = value
        self.type = type
        self.isEditable = isEditable
        self.lastModified = lastModified
        self.modificationHistory = modificationHistory
    }

    private enum CodingKeys: String, CodingKey {
        case key, value, type, isEditable, lastModified, modificationHistory
    }
}

/// A collection of key-value entries representing a store (like UserDefaults)
public struct EchoKeyValueStore: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let sfSymbol: String
    public let entries: [EchoKeyValueEntry]
    public let isReadOnly: Bool
    public let lastUpdated: Date
    public let supportedTypes: [EchoKeyValueType]

    public var supportedTypesOrDefault: [EchoKeyValueType] {
        if !supportedTypes.isEmpty {
            supportedTypes
        } else {
            EchoKeyValueType.allCases.filter { $0 != .unknown }
        }
    }
    
    public init(
        id: String,
        name: String,
        sfSymbol: String = "gearshape.fill",
        entries: [EchoKeyValueEntry],
        isReadOnly: Bool,
        lastUpdated: Date = Date(),
        supportedTypes: [EchoKeyValueType] = []
    ) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.entries = entries
        self.isReadOnly = isReadOnly
        self.lastUpdated = lastUpdated
        self.supportedTypes = supportedTypes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sfSymbol, entries, isReadOnly, lastUpdated, supportedTypes
    }
}

/// A snapshot of all stores at a given point in time
public struct EchoKeyValueStoreSnapshot: Codable, Hashable {
    public let stores: [EchoKeyValueStore]
    public let timestamp: Date

    public init(stores: [EchoKeyValueStore], timestamp: Date = Date()) {
        self.stores = stores
        self.timestamp = timestamp
    }
}

/// Errors that can occur during key-value store operations
public enum EchoKeyValueStoreError: Error, LocalizedError {
    case invalidType(String)
    case keyNotFound(String)
    case readOnlyStore
    case connectionError(String)
    case encodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidType(let message):
            return "Invalid type: \(message)"
        case .keyNotFound(let key):
            return "Key not found: \(key)"
        case .readOnlyStore:
            return "Cannot modify read-only store"
        case .connectionError(let message):
            return "Connection error: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        }
    }
}

private extension NSNumber {
    func toEchoCodeableValue() -> EchoCodableValue {
        if CFBooleanGetTypeID() == CFGetTypeID(self) {
            return .boolean(self.boolValue)
        }
        let type = CFNumberGetType(self)
        switch type {
        case .sInt32Type, .longType:
            return .integer(self.int32Value)
        case .sInt16Type, .shortType:
            return .integer16(self.int16Value)
        case .sInt64Type, .longLongType:
            return .integer64(self.int64Value)
        case .floatType, .float32Type:
            return .float(self.floatValue)
        case .doubleType, .float64Type:
            return .double(self.doubleValue)
        default:
            return .null
        }
    }
}
