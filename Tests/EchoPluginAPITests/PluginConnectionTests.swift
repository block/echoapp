
import Combine
import EchoPluginAPI
import XCTest

final class PluginConnectionTests: XCTestCase {

    func test_dateEncoding() throws {
        var sentData: [PluginMessage] = []

        let connection = PluginConnection(
            incomingMessages: Empty().eraseToAnyPublisher(),
            send: { sentData.append($0) }
        )

        let message = Date(timeIntervalSince1970: 1701972283.4831234)
        try connection.send(message)

        XCTAssertEqual(sentData.count, 1)
        XCTAssertEqual(
            sentData.first.flatMap { String(data: $0.data, encoding: .utf8) },
            "1701972283483"
        )
    }

    func test_dateDecoding() throws {
        let incomingMessages = PassthroughSubject<PluginMessage, Never>()

        let connection = PluginConnection(
            incomingMessages: incomingMessages.eraseToAnyPublisher(),
            send: { _ in }
        )

        var receivedMessage: Date?
        let cancellable = connection.receive(Date.self).sink {
            receivedMessage = $0
        }

        incomingMessages.send(PluginMessage(command: nil, data: "1701972283483".data(using: .utf8)!))
        XCTAssertEqual(
            receivedMessage?.timeIntervalSince1970, 
            1701972283.483 // `Swift.Date` normalizes to seconds with ms after the decimal
        )
        cancellable.cancel()
    }

}
