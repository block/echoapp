
import EchoPluginAPI
import XCTest

// MARK: - SyncHubClientEvent Tests

final class SyncHubClientEventTests: XCTestCase {

    // MARK: - Codable

    func test_encodeDecode_syncRequest() throws {
        let request = SyncHubSyncRequest(
            id: "req-1",
            domain: "kds",
            timestamp: "2025-01-15T10:30:00Z",
            operationType: .syncDomain,
            requestJson: "{\"domain_sync_data\":{\"from_domain_version\":\"v1\"}}"
        )
        let event = SyncHubClientEvent.syncRequest(request)
        let decoded = try encodeAndDecode(event)
        XCTAssertEqual(decoded, event)
    }

    func test_encodeDecode_syncResponse() throws {
        let response = SyncHubSyncResponse(
            requestId: "req-1",
            domain: "kds",
            timestamp: "2025-01-15T10:30:01Z",
            operationType: .syncDomain,
            durationMs: 250,
            status: .success,
            errorMessage: "",
            responseJson: "{\"read_result\":{\"domain_version\":\"v2\"}}"
        )
        let event = SyncHubClientEvent.syncResponse(response)
        let decoded = try encodeAndDecode(event)
        XCTAssertEqual(decoded, event)
    }

    func test_encodeDecode_connectionStatus() throws {
        let status = SyncHubConnectionStatus(
            domain: "kds",
            timestamp: "2025-01-15T10:30:00Z",
            isConnectedToLocalHub: true,
            isConnectedToCloudHub: false
        )
        let event = SyncHubClientEvent.connectionStatus(status)
        let decoded = try encodeAndDecode(event)
        XCTAssertEqual(decoded, event)
    }

    func test_encodeDecode_outboxStatus() throws {
        let status = SyncHubOutboxStatus(
            domain: "orders",
            timestamp: "2025-01-15T10:30:00Z",
            pendingCommitCount: 7
        )
        let event = SyncHubClientEvent.outboxStatus(status)
        let decoded = try encodeAndDecode(event)
        XCTAssertEqual(decoded, event)
    }

    func test_decode_unknownCase_throws() {
        let json = """
        {"unknown_event":{"value":1}}
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SyncHubClientEvent.self, from: data))
    }

    // MARK: - JSON Key Format

    func test_syncRequest_encodesWithSnakeCaseKeys() throws {
        let request = SyncHubSyncRequest(
            id: "req-1",
            domain: "kds",
            timestamp: "2025-01-15T10:30:00Z",
            operationType: .syncDomain,
            requestJson: "{}"
        )
        let event = SyncHubClientEvent.syncRequest(request)
        let data = try JSONEncoder().encode(event)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"sync_request\""))
        XCTAssertTrue(jsonString.contains("\"id\""))
        XCTAssertTrue(jsonString.contains("\"domain\""))
    }

    func test_syncResponse_encodesWithSnakeCaseKeys() throws {
        let response = SyncHubSyncResponse(
            requestId: "req-1",
            domain: "kds",
            timestamp: "2025-01-15T10:30:01Z",
            operationType: .syncDomain,
            durationMs: 100,
            status: .success,
            errorMessage: "",
            responseJson: "{}"
        )
        let event = SyncHubClientEvent.syncResponse(response)
        let data = try JSONEncoder().encode(event)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"sync_response\""))
    }

    // MARK: - Private

    private func encodeAndDecode<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - SyncHubDesktopEvent Tests

final class SyncHubDesktopEventTests: XCTestCase {

    func test_encodeDecode_triggerSync() throws {
        let event = SyncHubDesktopEvent.triggerSync(domain: "kds")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SyncHubDesktopEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func test_encodeDecode_clearData() throws {
        let event = SyncHubDesktopEvent.clearData
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SyncHubDesktopEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }
}

// MARK: - SyncHubOperationType Tests

final class SyncHubOperationTypeTests: XCTestCase {

    func test_rawValues() {
        XCTAssertEqual(SyncHubOperationType.initializeDomain.rawValue, "initialize_domain")
        XCTAssertEqual(SyncHubOperationType.syncDomain.rawValue, "sync_domain")
        XCTAssertEqual(SyncHubOperationType.writeDomain.rawValue, "write_domain")
        XCTAssertEqual(SyncHubOperationType.readDomain.rawValue, "read_domain")
    }

    func test_encodeDecode() throws {
        for type in [SyncHubOperationType.initializeDomain, .syncDomain, .writeDomain, .readDomain] {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(SyncHubOperationType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }
}

// MARK: - Proto-shaped Types Tests

final class ProtoSyncDomainRequestTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func test_decode_withCommitsAndVersion() throws {
        let json = """
        {
            "domain_sync_data": {
                "from_domain_version": "v42",
                "commits": [
                    {
                        "operations": [
                            {
                                "create_entity_operation": {
                                    "entity": {
                                        "entity_id": "e1",
                                        "domain_object": {
                                            "@type": "type.googleapis.com/Item",
                                            "name": "Widget"
                                        }
                                    }
                                }
                            },
                            {
                                "delete_entity_operation": {
                                    "entity_id": "e2",
                                    "entity_type": "type.googleapis.com/Item"
                                }
                            }
                        ],
                        "audit_log": {
                            "commit_idempotence_token": "tok-1",
                            "command": {
                                "@type": "type.googleapis.com/CreateItem"
                            },
                            "commit_source": {
                                "actor": { "type": "MERCHANT", "id": "m1" },
                                "surface": { "type": "POS", "id": "s1" }
                            }
                        }
                    }
                ]
            }
        }
        """
        let request = try decoder.decode(ProtoSyncDomainRequest.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(request.domainSyncData?.fromDomainVersion, "v42")
        XCTAssertEqual(request.domainSyncData?.commits?.count, 1)

        let commit = try XCTUnwrap(request.domainSyncData?.commits?.first)
        XCTAssertEqual(commit.operations?.count, 2)
        XCTAssertNotNil(commit.operations?[0].createEntityOperation)
        XCTAssertEqual(commit.operations?[0].createEntityOperation?.entity?.entityId, "e1")
        XCTAssertEqual(commit.operations?[0].createEntityOperation?.entity?.domainObject?.typeUrl, "type.googleapis.com/Item")
        XCTAssertNotNil(commit.operations?[1].deleteEntityOperation)
        XCTAssertEqual(commit.operations?[1].deleteEntityOperation?.entityId, "e2")

        let auditLog = try XCTUnwrap(commit.auditLog)
        XCTAssertEqual(auditLog.commitIdempotenceToken, "tok-1")
        XCTAssertEqual(auditLog.command?.typeUrl, "type.googleapis.com/CreateItem")
        XCTAssertEqual(auditLog.commitSource?.actor?.type, "MERCHANT")
        XCTAssertEqual(auditLog.commitSource?.actor?.id, "m1")
        XCTAssertEqual(auditLog.commitSource?.surface?.type, "POS")
        XCTAssertEqual(auditLog.commitSource?.surface?.id, "s1")
    }

    func test_decode_emptyCommits() throws {
        let json = """
        {"domain_sync_data":{"from_domain_version":"v1","commits":[]}}
        """
        let request = try decoder.decode(ProtoSyncDomainRequest.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(request.domainSyncData?.fromDomainVersion, "v1")
        XCTAssertEqual(request.domainSyncData?.commits?.count, 0)
    }

    func test_decode_minimalPayload() throws {
        let json = "{}"
        let request = try decoder.decode(ProtoSyncDomainRequest.self, from: json.data(using: .utf8)!)
        XCTAssertNil(request.domainSyncData)
    }
}

final class ProtoSyncDomainResponseTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func test_decode_fullResponse() throws {
        let json = """
        {
            "read_result": {
                "domain_version": "v50",
                "entity_read_result": {
                    "entities": [
                        {"entity_id": "e1", "domain_object": {"@type": "type.googleapis.com/Item"}}
                    ]
                },
                "relation_read_result": {
                    "relations": [
                        {
                            "subject_entity_id": "s1",
                            "subject_entity_type": "Item",
                            "object_entity_id": "o1",
                            "object_entity_type": "Category"
                        }
                    ]
                },
                "tombstoned_entity_read_result": {
                    "tombstones": [
                        {"id": "t1", "type_url": "type.googleapis.com/Item"}
                    ]
                },
                "tombstoned_relation_read_result": {
                    "tombstones": [
                        {
                            "subject_entity_id": "rs1",
                            "subject_entity_type": "Item",
                            "object_entity_id": "ro1",
                            "object_entity_type": "Category"
                        }
                    ]
                }
            },
            "commit_audit_logs": [
                {
                    "commit_idempotence_token": "tok-1",
                    "command": {"@type": "type.googleapis.com/CreateItem"},
                    "commit_source": {
                        "actor": {"type": "MERCHANT", "id": "m1"},
                        "surface": {"type": "POS", "id": "s1"}
                    },
                    "local_hub_processing_result": {
                        "commit_status": "COMMIT_STATUS_APPLIED",
                        "applied_to_domain_version": "v49"
                    },
                    "cloud_hub_processing_result": {
                        "commit_status": "COMMIT_STATUS_REJECTED",
                        "applied_to_domain_version": "v50",
                        "debug_message": "conflict"
                    }
                }
            ]
        }
        """
        let response = try decoder.decode(ProtoSyncDomainResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.readResult?.domainVersion, "v50")

        let entities = try XCTUnwrap(response.readResult?.entityReadResult?.entities)
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities[0].entityId, "e1")

        let relations = try XCTUnwrap(response.readResult?.relationReadResult?.relations)
        XCTAssertEqual(relations.count, 1)
        XCTAssertEqual(relations[0].subjectEntityId, "s1")
        XCTAssertEqual(relations[0].objectEntityId, "o1")

        let entityTombstones = try XCTUnwrap(response.readResult?.tombstonedEntityReadResult?.tombstones)
        XCTAssertEqual(entityTombstones.count, 1)
        XCTAssertEqual(entityTombstones[0].id, "t1")

        let relationTombstones = try XCTUnwrap(response.readResult?.tombstonedRelationReadResult?.tombstones)
        XCTAssertEqual(relationTombstones.count, 1)
        XCTAssertEqual(relationTombstones[0].subjectEntityId, "rs1")

        let auditLogs = try XCTUnwrap(response.commitAuditLogs)
        XCTAssertEqual(auditLogs.count, 1)
        XCTAssertEqual(auditLogs[0].commitIdempotenceToken, "tok-1")
        XCTAssertEqual(auditLogs[0].localHubProcessingResult?.commitStatus, "COMMIT_STATUS_APPLIED")
        XCTAssertEqual(auditLogs[0].localHubProcessingResult?.appliedToDomainVersion, "v49")
        XCTAssertEqual(auditLogs[0].cloudHubProcessingResult?.commitStatus, "COMMIT_STATUS_REJECTED")
        XCTAssertEqual(auditLogs[0].cloudHubProcessingResult?.debugMessage, "conflict")
    }

    func test_decode_emptyResponse() throws {
        let json = "{}"
        let response = try decoder.decode(ProtoSyncDomainResponse.self, from: json.data(using: .utf8)!)
        XCTAssertNil(response.readResult)
        XCTAssertNil(response.commitAuditLogs)
    }
}

// MARK: - AnyCodable Tests

final class AnyCodableTests: XCTestCase {

    func test_decodesString() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: "\"hello\"".data(using: .utf8)!)
        XCTAssertEqual(decoded, .string("hello"))
    }

    func test_decodesInt() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: "42".data(using: .utf8)!)
        XCTAssertEqual(decoded, .int(42))
    }

    func test_decodesBool() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: "true".data(using: .utf8)!)
        XCTAssertEqual(decoded, .bool(true))
    }

    func test_decodesNull() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: "null".data(using: .utf8)!)
        XCTAssertEqual(decoded, .null)
    }

    func test_decodesArray() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: "[1,2]".data(using: .utf8)!)
        XCTAssertEqual(decoded, .array([.int(1), .int(2)]))
    }

    func test_decodesObject() throws {
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: "{\"a\":1}".data(using: .utf8)!)
        XCTAssertEqual(decoded, .object(["a": .int(1)]))
    }

    func test_encodeDecode_roundTrip() throws {
        let value: AnyCodable = .object([
            "name": .string("Widget"),
            "count": .int(5),
            "active": .bool(true),
            "tags": .array([.string("a"), .string("b")]),
            "meta": .null,
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_toJsonString_prettyPrinted() {
        let value: AnyCodable = .object(["key": .string("value")])
        let jsonString = value.toJsonString()
        XCTAssertTrue(jsonString.contains("\"key\""))
        XCTAssertTrue(jsonString.contains("\"value\""))
    }

    func test_toJsonString_compact() {
        let value: AnyCodable = .object(["key": .string("value")])
        let jsonString = value.toJsonString(prettyPrint: false)
        XCTAssertFalse(jsonString.contains("\n"))
    }
}

// MARK: - ProtoAnyMessage Tests

final class ProtoAnyMessageTests: XCTestCase {

    func test_decode_capturesTypeUrlAndRawJson() throws {
        let json = """
        {"@type":"type.googleapis.com/Item","name":"Widget","price":999}
        """
        let message = try JSONDecoder().decode(ProtoAnyMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(message.typeUrl, "type.googleapis.com/Item")
        XCTAssertEqual(message.rawJson?["name"], .string("Widget"))
        XCTAssertEqual(message.rawJson?["price"], .int(999))
    }

    func test_decode_noTypeUrl() throws {
        let json = """
        {"name":"Widget"}
        """
        let message = try JSONDecoder().decode(ProtoAnyMessage.self, from: json.data(using: .utf8)!)
        XCTAssertNil(message.typeUrl)
        XCTAssertEqual(message.rawJson?["name"], .string("Widget"))
    }
}
