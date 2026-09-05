@testable import NetworkingDesktopPlugin

import EchoPluginAPI
import XCTest

final class URLRequest_ProxyTests: XCTestCase {

    func test_makeProxyRequest_nilReplacementBaseURL() throws {
        let originalRequest = Request(
            id: "ignored",
            url: URL(string: "https://cats.com/cats/domestic?color=gray")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "ignored",
            rawBody: Data("{}".utf8)
        )
        let proxiedRequest = try XCTUnwrap(
            URLRequest.makeProxyRequest(from: originalRequest)
        )

        XCTAssertEqual(proxiedRequest.url, originalRequest.url)
        XCTAssertEqual(proxiedRequest.httpMethod, originalRequest.httpMethod)
        XCTAssertEqual(proxiedRequest.allHTTPHeaderFields, originalRequest.headers)
        XCTAssertEqual(proxiedRequest.httpBody, originalRequest.rawBody)
    }

    func test_makeProxyRequest_emptyPath_nilReplacementBaseURL() throws {
        let originalRequest = Request(
            id: "ignored",
            url: URL(string: "https://cats.com?color=gray")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "ignored",
            rawBody: Data("{}".utf8)
        )
        let proxiedRequest = try XCTUnwrap(
            URLRequest.makeProxyRequest(from: originalRequest)
        )

        XCTAssertEqual(proxiedRequest.url, originalRequest.url)
        XCTAssertEqual(proxiedRequest.httpMethod, originalRequest.httpMethod)
        XCTAssertEqual(proxiedRequest.allHTTPHeaderFields, originalRequest.headers)
        XCTAssertEqual(proxiedRequest.httpBody, originalRequest.rawBody)
    }

    func test_makeProxyRequest_noQueryParams_nilReplacementBaseURL() throws {
        let originalRequest = Request(
            id: "ignored",
            url: URL(string: "https://cats.com/cats/domestic")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "ignored",
            rawBody: Data("{}".utf8)
        )
        let proxiedRequest = try XCTUnwrap(
            URLRequest.makeProxyRequest(from: originalRequest)
        )

        XCTAssertEqual(proxiedRequest.url, originalRequest.url)
        XCTAssertEqual(proxiedRequest.httpMethod, originalRequest.httpMethod)
        XCTAssertEqual(proxiedRequest.allHTTPHeaderFields, originalRequest.headers)
        XCTAssertEqual(proxiedRequest.httpBody, originalRequest.rawBody)
    }

    func test_makeProxyRequest_validReplacemenBasetURL() throws {
        let originalRequest = Request(
            id: "ignored",
            url: URL(string: "https://cats.com/cats/domestic?color=gray")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "ignored",
            rawBody: Data("{}".utf8)
        )
        let replacementBaseURL = URL(string: "https://proxy.example.com")!
        let proxiedRequest = try XCTUnwrap(
            URLRequest.makeProxyRequest(
                from: originalRequest,
                replacementBaseURL: replacementBaseURL
            )
        )
        XCTAssertEqual(proxiedRequest.url, URL(string: "https://proxy.example.com/cats/domestic?color=gray")!)
        XCTAssertEqual(proxiedRequest.httpMethod, originalRequest.httpMethod)
        XCTAssertEqual(proxiedRequest.allHTTPHeaderFields, originalRequest.headers)
        XCTAssertEqual(proxiedRequest.httpBody, originalRequest.rawBody)
    }

    func test_makeProxyRequest_emptyPath_validReplacemenBasetURL() throws {
        let originalRequest = Request(
            id: "ignored",
            url: URL(string: "https://cats.com?color=gray")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "ignored",
            rawBody: Data("{}".utf8)
        )
        let replacementBaseURL = URL(string: "https://proxy.example.com")!
        let proxiedRequest = try XCTUnwrap(
            URLRequest.makeProxyRequest(
                from: originalRequest,
                replacementBaseURL: replacementBaseURL
            )
        )
        XCTAssertEqual(proxiedRequest.url, URL(string: "https://proxy.example.com?color=gray")!)
        XCTAssertEqual(proxiedRequest.httpMethod, originalRequest.httpMethod)
        XCTAssertEqual(proxiedRequest.allHTTPHeaderFields, originalRequest.headers)
        XCTAssertEqual(proxiedRequest.httpBody, originalRequest.rawBody)
    }

    func test_makeProxyRequest_noQueryParams_validReplacementURL() throws {
        let originalRequest = Request(
            id: "ignored",
            url: URL(string: "https://cats.com/cats/domestic")!,
            httpMethod: "POST",
            headers: ["Content-Type": "application/json"],
            timestamp: Date(),
            humanReadableBody: "ignored",
            rawBody: Data("{}".utf8)
        )

        let replacementBaseURL = URL(string: "https://proxy.example.com")!
        let proxiedRequest = try XCTUnwrap(
            URLRequest.makeProxyRequest(
                from: originalRequest,
                replacementBaseURL: replacementBaseURL
            )
        )
        XCTAssertEqual(proxiedRequest.url, URL(string: "https://proxy.example.com/cats/domestic")!)
        XCTAssertEqual(proxiedRequest.httpMethod, originalRequest.httpMethod)
        XCTAssertEqual(proxiedRequest.allHTTPHeaderFields, originalRequest.headers)
        XCTAssertEqual(proxiedRequest.httpBody, originalRequest.rawBody)
    }

}
