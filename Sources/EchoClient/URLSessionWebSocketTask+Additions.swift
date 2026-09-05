import Combine
import Foundation

extension URLSessionWebSocketTaskProtocol {

    public func publisher() -> AnyPublisher<URLSessionWebSocketTask.Message, Error> {
        let subject = PassthroughSubject<URLSessionWebSocketTask.Message, Error>()

        self.continuallyReceive { result in
            switch result {
            case let .success(message):
                subject.send(message)
            case let .failure(error):
                subject.send(completion: .failure(error))
            }
        }
        return subject.eraseToAnyPublisher()
    }

    public func continuallyReceive(
        _ handler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) {
        self.receive { [weak self] result in
            handler(result)

            if case .success = result {
                self?.continuallyReceive(handler)
            }
        }
    }

}

// MARK: -

extension URLSessionWebSocketTask.Message {

    public var data: Data {
        switch self {
        case let .data(data): return data
        case let .string(string): return string.data(using: .utf8)!
        default: fatalError("Unknown URLSessionWebSocketTask.Message case")
        }
    }

}
