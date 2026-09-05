import Foundation

// MARK: - Client Events (Mobile → Desktop)

public enum SyncHubClientEvent: Codable, Equatable {
    case syncRequest(SyncHubSyncRequest)
    case syncResponse(SyncHubSyncResponse)
    case connectionStatus(SyncHubConnectionStatus)
    case outboxStatus(SyncHubOutboxStatus)

    private enum CodingKeys: String, CodingKey {
        case syncRequest = "sync_request"
        case syncResponse = "sync_response"
        case connectionStatus = "connection_status"
        case outboxStatus = "outbox_status"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(SyncHubSyncRequest.self, forKey: .syncRequest) {
            self = .syncRequest(value)
        } else if let value = try container.decodeIfPresent(SyncHubSyncResponse.self, forKey: .syncResponse) {
            self = .syncResponse(value)
        } else if let value = try container.decodeIfPresent(SyncHubConnectionStatus.self, forKey: .connectionStatus) {
            self = .connectionStatus(value)
        } else if let value = try container.decodeIfPresent(SyncHubOutboxStatus.self, forKey: .outboxStatus) {
            self = .outboxStatus(value)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown SyncHubClientEvent case")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .syncRequest(let value):
            try container.encode(value, forKey: .syncRequest)
        case .syncResponse(let value):
            try container.encode(value, forKey: .syncResponse)
        case .connectionStatus(let value):
            try container.encode(value, forKey: .connectionStatus)
        case .outboxStatus(let value):
            try container.encode(value, forKey: .outboxStatus)
        }
    }
}

// MARK: - Sync Request/Response (raw JSON payload)

public struct SyncHubSyncRequest: Codable, Equatable {
    public let id: String
    public let domain: String
    public let timestamp: String
    public let operationType: SyncHubOperationType
    public let requestJson: String

    public init(
        id: String,
        domain: String,
        timestamp: String,
        operationType: SyncHubOperationType,
        requestJson: String
    ) {
        self.id = id
        self.domain = domain
        self.timestamp = timestamp
        self.operationType = operationType
        self.requestJson = requestJson
    }
}

public struct SyncHubSyncResponse: Codable, Equatable {
    public let requestId: String
    public let domain: String
    public let timestamp: String
    public let operationType: SyncHubOperationType
    public let durationMs: Int64
    public let status: SyncHubOperationStatus
    public let errorMessage: String
    public let responseJson: String

    public init(
        requestId: String,
        domain: String,
        timestamp: String,
        operationType: SyncHubOperationType,
        durationMs: Int64,
        status: SyncHubOperationStatus,
        errorMessage: String,
        responseJson: String
    ) {
        self.requestId = requestId
        self.domain = domain
        self.timestamp = timestamp
        self.operationType = operationType
        self.durationMs = durationMs
        self.status = status
        self.errorMessage = errorMessage
        self.responseJson = responseJson
    }
}

public struct SyncHubConnectionStatus: Codable, Equatable {
    public let domain: String
    public let timestamp: String
    public let isConnectedToLocalHub: Bool
    public let isConnectedToCloudHub: Bool

    public init(
        domain: String,
        timestamp: String,
        isConnectedToLocalHub: Bool,
        isConnectedToCloudHub: Bool
    ) {
        self.domain = domain
        self.timestamp = timestamp
        self.isConnectedToLocalHub = isConnectedToLocalHub
        self.isConnectedToCloudHub = isConnectedToCloudHub
    }
}

public struct SyncHubOutboxStatus: Codable, Equatable {
    public let domain: String
    public let timestamp: String
    public let pendingCommitCount: Int

    public init(domain: String, timestamp: String, pendingCommitCount: Int) {
        self.domain = domain
        self.timestamp = timestamp
        self.pendingCommitCount = pendingCommitCount
    }
}

// MARK: - Desktop Events (Desktop → Mobile)

public enum SyncHubDesktopEvent: Codable, Equatable {
    case triggerSync(domain: String)
    case clearData
}

// MARK: - Operation Types

public enum SyncHubOperationType: String, Codable, Equatable {
    case initializeDomain = "initialize_domain"
    case syncDomain = "sync_domain"
    case writeDomain = "write_domain"
    case readDomain = "read_domain"
}

public enum SyncHubOperationStatus: String, Codable, Equatable {
    case success
    case error
}

// MARK: - Proto-shaped Types (for parsing requestJson/responseJson)
// These mirror the sync-hub proto JSON structure.
// Wire's WireJsonAdapterFactory outputs snake_case keys matching proto field names.
// The JSONDecoder uses .convertFromSnakeCase to map them to camelCase properties.

public struct ProtoSyncDomainResponse: Codable {
    public let readResult: ProtoReadResult?
    public let commitAuditLogs: [ProtoCommitAuditLog]?
}

public struct ProtoSyncDomainRequest: Codable {
    public let domainSyncData: ProtoDomainSyncData?
}

public struct ProtoDomainSyncData: Codable {
    public let fromDomainVersion: String?
    public let commits: [ProtoCommit]?
}

public struct ProtoCommit: Codable {
    public let operations: [ProtoOperation]?
    public let auditLog: ProtoCommitAuditLog?
}

public struct ProtoOperation: Codable {
    public let createEntityOperation: ProtoCreateEntityOperation?
    public let replaceEntityOperation: ProtoReplaceEntityOperation?
    public let deleteEntityOperation: ProtoDeleteEntityOperation?
    public let createRelationOperation: ProtoCreateRelationOperation?
    public let updateRelationMetadataOperation: ProtoUpdateRelationMetadataOperation?
    public let deleteRelationOperation: ProtoDeleteRelationOperation?
}

public struct ProtoCreateEntityOperation: Codable {
    public let entity: ProtoEntity?
}

public struct ProtoReplaceEntityOperation: Codable {
    public let entity: ProtoEntity?
}

public struct ProtoDeleteEntityOperation: Codable {
    public let entityId: String?
    public let entityType: String?
}

public struct ProtoCreateRelationOperation: Codable {
    public let relation: ProtoRelation?
}

public struct ProtoUpdateRelationMetadataOperation: Codable {
    public let relation: ProtoRelation?
}

public struct ProtoDeleteRelationOperation: Codable {
    public let subjectEntityId: String?
    public let objectEntityId: String?
}

public struct ProtoReadResult: Codable {
    public let domainVersion: String?
    public let entityReadResult: ProtoEntityReadResult?
    public let relationReadResult: ProtoRelationReadResult?
    public let tombstonedEntityReadResult: ProtoTombstonedEntityReadResult?
    public let tombstonedRelationReadResult: ProtoTombstonedRelationReadResult?
}

public struct ProtoEntityReadResult: Codable {
    public let entities: [ProtoEntity]?
}

public struct ProtoRelationReadResult: Codable {
    public let relations: [ProtoRelation]?
}

public struct ProtoTombstonedEntityReadResult: Codable {
    public let tombstones: [ProtoEntityTombstone]?
}

public struct ProtoTombstonedRelationReadResult: Codable {
    public let tombstones: [ProtoRelationTombstone]?
}

public struct ProtoEntity: Codable {
    public let entityId: String?
    public let domainObject: ProtoAnyMessage?
}

public struct ProtoRelation: Codable {
    public let subjectEntityId: String?
    public let subjectEntityType: String?
    public let objectEntityId: String?
    public let objectEntityType: String?
}

public struct ProtoEntityTombstone: Codable {
    public let id: String?
    public let typeUrl: String?
}

public struct ProtoRelationTombstone: Codable {
    public let subjectEntityId: String?
    public let subjectEntityType: String?
    public let objectEntityId: String?
    public let objectEntityType: String?
}

public struct ProtoAnyMessage: Codable {
    public let typeUrl: String?
    public let rawJson: [String: AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case typeUrl = "@type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.typeUrl = try container.decodeIfPresent(String.self, forKey: .typeUrl)

        // Also capture the full raw JSON
        let rawContainer = try decoder.singleValueContainer()
        self.rawJson = try? rawContainer.decode([String: AnyCodable].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(typeUrl, forKey: .typeUrl)
    }
}

/// Type-erased Codable wrapper for arbitrary JSON values
public enum AnyCodable: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodable])
    case array([AnyCodable])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Convert to a formatted JSON string for display
    public func toJsonString(prettyPrint: Bool = true) -> String {
        let encoder = JSONEncoder()
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

public struct ProtoCommitAuditLog: Codable {
    public let commitIdempotenceToken: String?
    public let command: ProtoAnyMessage?
    public let commitSource: ProtoCommitSource?
    public let localHubProcessingResult: ProtoCommitResult?
    public let cloudHubProcessingResult: ProtoCommitResult?
}

public struct ProtoCommitSource: Codable {
    public let actor: ProtoActor?
    public let surface: ProtoSurface?
}

public struct ProtoActor: Codable {
    public let type: String?
    public let id: String?
}

public struct ProtoSurface: Codable {
    public let type: String?
    public let id: String?
}

public struct ProtoCommitResult: Codable {
    public let commitStatus: String?
    public let appliedToDomainVersion: String?
    public let debugMessage: String?
}
