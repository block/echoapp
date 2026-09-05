import XCTest
import EchoPluginAPI
@testable import NetworkingDesktopPlugin

final class ExchangeMCPTests: XCTestCase {

    private func makeRequest(
        url: String = "https://api.example.com/v1/payments",
        method: String = "POST",
        headers: [String: String] = ["Content-Type": "application/json"],
        body: String = "{\"amount\": 100}",
        timestamp: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> Request {
        Request(
            id: UUID().uuidString,
            url: URL(string: url)!,
            httpMethod: method,
            headers: headers,
            timestamp: timestamp,
            humanReadableBody: body,
            rawBody: nil
        )
    }

    private func makeResponse(status: Int = 200, body: String = "{\"id\": \"pay_123\"}") -> HumanReadableResponse {
        HumanReadableResponse(requestID: UUID().uuidString, headers: ["Content-Type": "application/json"], body: body, statusCode: status)
    }

    func testMCPSummaryForFinishedExchange() {
        let request = makeRequest()
        let response = makeResponse(status: 201)
        let exchange = Exchange(request: request, state: .finalizedResponse(response, selectedPolicy: .proxy))

        let summary = exchange.mcpSummary()

        XCTAssertEqual(summary["id"] as? String, exchange.id.uuidString)
        XCTAssertEqual(summary["method"] as? String, "POST")
        XCTAssertEqual(summary["url"] as? String, "https://api.example.com/v1/payments")
        XCTAssertEqual(summary["statusCode"] as? Int, 201)
        XCTAssertEqual(summary["state"] as? String, "finalizedResponse")
        XCTAssertNotNil(summary["timestamp"])
    }

    func testMCPSummaryForPendingExchange() {
        let exchange = Exchange(request: makeRequest(), state: .waitingForClientProvidedResponse)

        let summary = exchange.mcpSummary()

        XCTAssertNil(summary["statusCode"])
        XCTAssertEqual(summary["state"] as? String, "waitingForClientProvidedResponse")
    }

    func testMCPDetailIncludesHeadersAndBodies() {
        let request = makeRequest(headers: ["Authorization": "Bearer tok", "Content-Type": "application/json"])
        let response = makeResponse(status: 401, body: "{\"error\": \"UNAUTHORIZED\"}")
        let exchange = Exchange(request: request, state: .finalizedResponse(response, selectedPolicy: .proxy))

        let detail = exchange.mcpDetail()

        let req = detail["request"] as? [String: Any]
        let resp = detail["response"] as? [String: Any]

        XCTAssertNotNil(req)
        XCTAssertNotNil(resp)
        XCTAssertEqual(req?["method"] as? String, "POST")
        XCTAssertEqual((req?["headers"] as? [String: String])?["Authorization"], "Bearer tok")
        XCTAssertEqual(req?["body"] as? String, "{\"amount\": 100}")
        XCTAssertEqual(resp?["statusCode"] as? Int, 401)
        XCTAssertEqual(resp?["body"] as? String, "{\"error\": \"UNAUTHORIZED\"}")
    }

    func testMCPDetailForPendingExchangeHasNilResponse() {
        let exchange = Exchange(request: makeRequest(), state: .waitingForClientProvidedResponse)

        let detail = exchange.mcpDetail()

        XCTAssertNil(detail["response"])
    }

    func testMCPSummaryJSONRoundtrip() throws {
        let exchange = Exchange(
            request: makeRequest(),
            state: .finalizedResponse(makeResponse(), selectedPolicy: .proxy)
        )
        let summary = exchange.mcpSummary()
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        XCTAssertFalse(data.isEmpty)
    }
}
