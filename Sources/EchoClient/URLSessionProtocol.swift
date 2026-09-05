import Foundation

/// Protocol for ``URLSession`` for easier testing
public protocol URLSessionProtocol {
    func makeWebSocketTask(for request: URLRequest) -> URLSessionWebSocketTaskProtocol
}

extension URLSession: URLSessionProtocol {
    public func makeWebSocketTask(for request: URLRequest) -> URLSessionWebSocketTaskProtocol {
        let task = webSocketTask(with: request)
        task.maximumMessageSize = .max
        return task
    }
}

// MARK: -

/// Protocol for ``URLSessionWebSocketTask`` for easier testing
public protocol URLSessionWebSocketTaskProtocol: AnyObject {
    var currentRequest: URLRequest? { get }
    func cancel()
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive(
        completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void
    )
}

extension URLSessionWebSocketTask: URLSessionWebSocketTaskProtocol {}
