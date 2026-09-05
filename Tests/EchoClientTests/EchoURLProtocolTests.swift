@testable import EchoClient
import EchoPluginAPI
import Foundation
import XCTest

final class EchoURLProtocolTests: XCTestCase {

    // MARK: - Tests

    @MainActor
    func test_echoRequest_populatesURLRequestBodyFromStream() throws {
        let originalBodyData = Data("Hello, World!".utf8)

        // Given a URLRequest with httpBodyStream instead of httpBody (as URLSession does)
        var urlRequest = URLRequest(url: URL(string: "https://example.com")!)
        urlRequest.httpBodyStream = InputStream(data: originalBodyData)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mockConverter = MockHTTPBodyConverter()

        // When EchoURLProtocol converts the request to an Echo request
        let urlProtocol = EchoURLProtocol(request: urlRequest, cachedResponse: nil, client: nil)
        let echoRequest = urlProtocol.echoRequest(using: mockConverter)
        
        // Then the converter should have been called with a URLRequest that has httpBody populated
        XCTAssertEqual(mockConverter.prettyPrintRequestBodyCalls.count, 1)
        let prettyPrintCall = try XCTUnwrap(mockConverter.prettyPrintRequestBodyCalls.first)
        XCTAssertEqual(prettyPrintCall.httpBody, originalBodyData)
        XCTAssertEqual(prettyPrintCall.url, urlRequest.url!)
        XCTAssertEqual(prettyPrintCall.httpMethod, urlRequest.httpMethod)
        XCTAssertEqual(prettyPrintCall.allHTTPHeaderFields, urlRequest.allHTTPHeaderFields)

        // And the echo request should have the expected properties
        XCTAssertEqual(echoRequest.rawBody, originalBodyData)
        XCTAssertEqual(echoRequest.url, urlRequest.url)
        XCTAssertEqual(echoRequest.httpMethod, urlRequest.httpMethod)
        XCTAssertEqual(echoRequest.headers, urlRequest.allHTTPHeaderFields)
        XCTAssertEqual(echoRequest.humanReadableBody, mockConverter.prettyPrintedRequestBody)
    }
    
    @MainActor
    func test_echoRequest_handlesEmptyBody() throws {
        // Given a URLRequest with no body
        let request = URLRequest(url: URL(string: "https://example.com")!)

        let mockConverter = MockHTTPBodyConverter()

        // When EchoURLProtocol creates an echo request
        let urlProtocol = EchoURLProtocol(request: request, cachedResponse: nil, client: nil)
        _ = urlProtocol.echoRequest(using: mockConverter)

        // Then the converter should have been called with a URLRequest that has no httpBody
        XCTAssertEqual(mockConverter.prettyPrintRequestBodyCalls.count, 1)
        let prettyPrintCall = try XCTUnwrap(mockConverter.prettyPrintRequestBodyCalls.first)
        XCTAssertNil(prettyPrintCall.httpBody)
    }
    
    @MainActor
    func test_finalizeResponse_rawResponse() throws {
        let rawRequestBody = Data("request body".utf8)

        let echoRequest = Request(
            id: "test-id",
            url: URL(string: "https://example.com")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "request body",
            rawBody: rawRequestBody
        )
        
        let rawResponse = RawResponse(
            requestID: "test-id",
            headers: ["Content-Type": "application/json"],
            body: Data("response body".utf8),
            statusCode: 200
        )
        
        let mockConverter = MockHTTPBodyConverter()
        let mockClient = MockURLProtocolClient()
        
        // When finalizing the response
        let urlProtocol = EchoURLProtocol(
            request: URLRequest(url: URL(string: "https://example.com")!),
            cachedResponse: nil,
            client: mockClient
        )
        let finalizedResponse = urlProtocol.finalizeResponse(
            for: rawResponse,
            echoRequest: echoRequest,
            using: mockConverter
        )
        
        // The converter should have been called with properly populated URLRequest and RawResponse
        XCTAssertEqual(mockConverter.prettyPrintResponseBodyCalls.count, 1)
        let prettyPrintCall = try XCTUnwrap(mockConverter.prettyPrintResponseBodyCalls.first)

        XCTAssertEqual(prettyPrintCall.request.httpBody, rawRequestBody)
        XCTAssertEqual(prettyPrintCall.request.url?.absoluteString, "https://example.com")
        XCTAssertEqual(prettyPrintCall.request.httpMethod, "POST")
        XCTAssertEqual(prettyPrintCall.request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        XCTAssertEqual(prettyPrintCall.response, rawResponse)

        // And the finalized response should have the expected properties
        XCTAssertEqual(finalizedResponse.requestID, rawResponse.requestID)
        XCTAssertEqual(finalizedResponse.statusCode, rawResponse.statusCode)
        XCTAssertEqual(finalizedResponse.headers, rawResponse.headers)
        XCTAssertEqual(finalizedResponse.body, mockConverter.prettyPrintedResponseBody)
    }
    
    @MainActor
    func test_finalizeResponse_humanReadableResponse() throws {
        let rawRequestBody = Data("request body".utf8)

        let echoRequest = Request(
            id: "test-id",
            url: URL(string: "https://example.com")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "request body",
            rawBody: rawRequestBody
        )
        
        let humanReadableResponse = HumanReadableResponse(
            requestID: "test-id",
            headers: ["Content-Type": "application/json"],
            body: "human readable response",
            statusCode: 200
        )
        
        let mockConverter = MockHTTPBodyConverter()
        let mockClient = MockURLProtocolClient()
        
        // When finalizing the response
        let urlProtocol = EchoURLProtocol(
            request: URLRequest(url: URL(string: "https://example.com")!),
            cachedResponse: nil,
            client: mockClient
        )
        let finalizedResponse = try urlProtocol.finalizeResponse(
            for: humanReadableResponse,
            echoRequest: echoRequest,
            using: mockConverter
        )
        
        // The converter should have been called with properly populated URLRequest and HumanReadableResponse
        XCTAssertEqual(mockConverter.parseHumanReadableResponseBodyCalls.count, 1)
        let parseCall = try XCTUnwrap(mockConverter.parseHumanReadableResponseBodyCalls.first)
        
        XCTAssertEqual(parseCall.request.httpBody, rawRequestBody)
        XCTAssertEqual(parseCall.request.url, echoRequest.url)
        XCTAssertEqual(parseCall.request.httpMethod, echoRequest.httpMethod)
        XCTAssertEqual(parseCall.request.allHTTPHeaderFields, echoRequest.headers)
        XCTAssertEqual(parseCall.response, humanReadableResponse)

        // The client should have received the _parsed_ response body
        XCTAssertEqual(mockClient.receivedData, [mockConverter.parsedHumanReadableResponse])

        // and the echo response should be returned unchanged
        XCTAssertEqual(finalizedResponse, humanReadableResponse)
    }
}

// MARK: -

private final class MockHTTPBodyConverter: EchoURLProtocol.HTTPBodyConverter {

    // Stubbed responses
    var prettyPrintedRequestBody: String
    var prettyPrintedResponseBody: String
    var parsedHumanReadableResponse: Data

    init(
        prettyPrintedRequestBody: String = "Mock request body",
        prettyPrintedResponseBody: String = "Mock response body",
        parsedHumanReadableResponse: Data = Data("Mock parsed response data".utf8)
    ) {
        self.prettyPrintedRequestBody = prettyPrintedRequestBody
        self.prettyPrintedResponseBody = prettyPrintedResponseBody
        self.parsedHumanReadableResponse = parsedHumanReadableResponse
    }

    // Captured calls
    var prettyPrintRequestBodyCalls: [URLRequest] = []
    var prettyPrintResponseBodyCalls: [(response: RawResponse, request: URLRequest)] = []
    var parseHumanReadableResponseBodyCalls: [(response: HumanReadableResponse, request: URLRequest)] = []

    // MARK: - HTTPBodyConverter

    func prettyPrintBody(for request: URLRequest) throws -> String {
        prettyPrintRequestBodyCalls.append(request)
        return prettyPrintedRequestBody
    }
    
    func prettyPrintBody(for response: RawResponse, request: URLRequest) throws -> String {
        prettyPrintResponseBodyCalls.append((response, request))
        return prettyPrintedResponseBody
    }
    
    func parseHumanReadableResponseBody(for response: HumanReadableResponse, request: URLRequest) throws -> Data {
        parseHumanReadableResponseBodyCalls.append((response, request))
        return parsedHumanReadableResponse
    }
}

// MARK: -

private final class MockURLProtocolClient: NSObject, URLProtocolClient {
    var receivedResponses: [URLResponse] = []
    var receivedData: [Data] = []
    var didFinishLoading = false
    var receivedErrors: [Error] = []
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        didReceive response: URLResponse,
        cacheStoragePolicy policy: URLCache.StoragePolicy
    ) {
        receivedResponses.append(response)
    }
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        didLoad data: Data
    ) {
        receivedData.append(data)
    }
    
    func urlProtocolDidFinishLoading(_ urlProtocol: URLProtocol) {
        didFinishLoading = true
    }
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        didFailWithError error: Error
    ) {
        receivedErrors.append(error)
    }
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        wasRedirectedTo request: URLRequest,
        redirectResponse: URLResponse
    ) {}
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        didReceive challenge: URLAuthenticationChallenge
    ) {}
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        didCancel challenge: URLAuthenticationChallenge
    ) {}
    
    func urlProtocol(
        _ urlProtocol: URLProtocol,
        cachedResponseIsValid cachedResponse: CachedURLResponse
    ) {}
}
