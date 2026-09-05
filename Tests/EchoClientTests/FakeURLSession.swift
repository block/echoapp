import EchoClient
import Foundation

final class FakeURLSession: URLSessionProtocol {
    func makeWebSocketTask(for request: URLRequest) -> URLSessionWebSocketTaskProtocol {
        FakeWebSocketTask(request: request)
    }
}

final class FakeWebSocketTask: URLSessionWebSocketTaskProtocol {
    let currentRequest: URLRequest?

    init(request: URLRequest?) {
        self.currentRequest = request
    }

    func cancel() {}

    var resumeCallCount = 0
    func resume() {
        resumeCallCount += 1
    }
    
    func send(_ message: URLSessionWebSocketTask.Message) async throws {}

    var receiveCalls: [(Result<URLSessionWebSocketTask.Message, any Error>) -> Void] = []
    func receive(
        completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void
    ) {
        receiveCalls.append(completionHandler)
    }
}
