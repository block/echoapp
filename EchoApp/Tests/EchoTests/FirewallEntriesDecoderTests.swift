import Echo
import XCTest

final class FirewallEntriesDecoderTests: XCTestCase {

    func test_decode_validInput() throws {
        let input = """
        ALF: total number of apps = 299

        1 :  /System/Library/CoreServices/ControlCenter.app
              ( Allow incoming connections )

        2 :  /usr/libexec/sharingd
              ( Allow incoming connections )

        3 :  /usr/sbin/netbiosd
              ( Block incoming connections )

        """
        let entries = FirewallEntriesDecoder.decode(from: input)
        XCTAssertEqual(
            entries,
            [
                FirewallEntry(path: "/System/Library/CoreServices/ControlCenter.app", allowed: true),
                FirewallEntry(path: "/usr/libexec/sharingd", allowed: true),
                FirewallEntry(path: "/usr/sbin/netbiosd", allowed: false),
            ]
        )
    }

    func test_decode_invalidInput() {
        let input = """
        invalid data
        """
        let entries = FirewallEntriesDecoder.decode(from: input)
        XCTAssert(entries.isEmpty)
    }

}
