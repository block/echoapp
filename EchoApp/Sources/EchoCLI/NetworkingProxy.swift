import EchoConnection
import EchoPluginAPI
import Foundation
import Vapor

private typealias NetworkRequest = EchoPluginAPI.Request

/// Handles networking plugin proxy requests by executing the HTTP request
/// and sending the response back to the client through the WebSocket.
final class NetworkingProxy: @unchecked Sendable {

    private static let networkingPluginID = "com.echo.plugin.network"

    private let sendPayload: (PluginPayload, WebSocket?) -> Void
    private let urlSession: URLSession
    private let lock = NSLock()
    private var hasLoggedProxyMode = false

    init(sendPayload: @escaping (PluginPayload, WebSocket?) -> Void) {
        self.sendPayload = sendPayload
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: configuration)
    }

    /// Resets proxy mode detection and cancels in-flight requests.
    /// Call when a new client connects.
    func reset() {
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        lock.lock()
        hasLoggedProxyMode = false
        lock.unlock()
    }

    /// Inspects an incoming payload and, if it is a networking proxy request,
    /// executes the HTTP request and sends the response back to the client.
    func handleIfProxyRequest(_ payload: PluginPayload, from ws: WebSocket) {
        guard payload.pluginID == Self.networkingPluginID else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        guard let event = try? decoder.decode(NetworkingPluginClientEvent.self, from: payload.data) else {
            return
        }

        switch event {
        case let .request(request, proxy: isProxy):
            guard isProxy else { return }

            lock.lock()
            let shouldLog = !hasLoggedProxyMode
            hasLoggedProxyMode = true
            lock.unlock()

            if shouldLog {
                FileHandle.standardError.write(
                    "\nProxy mode detected -- echoapp will forward network requests.\n".data(using: .utf8)!
                )
            }

            if let fixtureResponse = matchFixture(for: request) {
                sendResponse(fixtureResponse, to: ws)
            } else {
                executeProxyRequest(request, replyTo: ws)
            }

        default:
            break
        }
    }

    // MARK: - Fixture Matching

    private func matchFixture(for request: NetworkRequest) -> NetworkingPluginServerEvent? {
        guard let sessionURL = SessionDirectory.currentSessionURL() else { return nil }

        let fixturesDir = FixtureCommand.fixturesDirectory(for: sessionURL)
        let endpoint = request.endpoint.path
        let relativePath = String(endpoint.dropFirst()) // drop leading slash
        let endpointDir = fixturesDir.appendingPathComponent(relativePath, isDirectory: true).standardized

        // Reject path traversal: resolved path must remain under fixturesDir
        guard endpointDir.path.hasPrefix(fixturesDir.standardized.path + "/")
                || endpointDir.path == fixturesDir.standardized.path else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: endpointDir.path) else { return nil }

        // Find the first fixture file alphabetically (regular files only, skip directories)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: endpointDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return nil }

        let jsonFiles = files
            .filter { url -> Bool in
                guard url.pathExtension == "json" else { return false }
                let keys: Set<URLResourceKey> = [.isRegularFileKey]
                let isFile = (try? url.resourceValues(forKeys: keys).isRegularFile) ?? false
                return isFile
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let fixtureURL = jsonFiles.first,
              let data = try? Data(contentsOf: fixtureURL),
              let fixture = try? JSONDecoder().decode(FixtureFile.self, from: data) else {
            return nil
        }

        let fixtureName = fixtureURL.lastPathComponent
        FileHandle.standardError.write(
            "\n[FIXTURE] \(endpoint) -> \(fixtureName) (\(fixture.statusCode))\n".data(using: .utf8)!
        )

        // Fixtures use proposedHumanReadableResponse (not rawResponse) per the
        // networking plugin protocol: the client parses the body as a string and
        // can reject it with an error event if parsing fails.
        let response = HumanReadableResponse(
            requestID: request.id,
            headers: fixture.headers,
            body: fixture.body,
            statusCode: fixture.statusCode
        )
        return .proposedHumanReadableResponse(response)
    }

    // MARK: - Proxy

    private func executeProxyRequest(_ request: NetworkRequest, replyTo ws: WebSocket) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.httpMethod
        urlRequest.allHTTPHeaderFields = request.headers
        urlRequest.httpBody = request.rawBody

        urlSession.dataTask(with: urlRequest) { [weak self] data, urlResponse, error in
            guard let self else { return }

            if let error {
                let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 502
                FileHandle.standardError.write(
                    "\nProxy request failed (\(request.url)): \(error.localizedDescription)\n".data(using: .utf8)!
                )
                let rawResponse = RawResponse(
                    requestID: request.id,
                    body: nil,
                    statusCode: statusCode
                )
                self.sendResponse(.rawResponse(rawResponse), to: ws)
                return
            }

            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                let rawResponse = RawResponse(
                    requestID: request.id,
                    body: nil,
                    statusCode: 502
                )
                self.sendResponse(.rawResponse(rawResponse), to: ws)
                return
            }

            let headers = Dictionary(uniqueKeysWithValues:
                httpResponse.allHeaderFields.compactMap { key, value in
                    (key as? String).map { ($0, "\(value)") }
                }
            )
            let rawResponse = RawResponse(
                requestID: request.id,
                headers: headers,
                body: data,
                statusCode: httpResponse.statusCode
            )
            self.sendResponse(.rawResponse(rawResponse), to: ws)
        }.resume()
    }

    private func sendResponse(_ event: NetworkingPluginServerEvent, to ws: WebSocket) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let timestamp = Int(date.timeIntervalSince1970 * 1_000)
            try container.encode(timestamp)
        }

        guard let eventData = try? encoder.encode(event) else { return }
        let payload = PluginPayload(
            pluginID: Self.networkingPluginID,
            data: eventData
        )
        sendPayload(payload, ws)
    }
}
