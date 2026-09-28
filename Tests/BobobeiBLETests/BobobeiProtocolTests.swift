import XCTest
@testable import BobobeiBLE

final class BobobeiProtocolTests: XCTestCase {
    func testControlPackets() {
        let packets = BobobeiProtocol.packets(for: .init(motion: 35, vibration: 20, rotation: 8))
        XCTAssertEqual(Array(packets[0]), [1, 1, 0, 2, 0, 7, 17, 35, 0, 8, 17, 1])
        XCTAssertEqual(Array(packets[1]), [1, 1, 0, 2, 0, 1, 17, 20, 0, 2, 17, 1])
        XCTAssertEqual(Array(packets[2]), [1, 1, 0, 2, 0, 3, 17, 8, 0, 4, 17, 1])
    }

    func testLevelsAreClamped() {
        XCTAssertEqual(BobobeiProtocol.Levels(motion: -1, vibration: 101, rotation: 50),
                       .init(motion: 0, vibration: 100, rotation: 50))
    }

    func testKeepAliveUsesOneActiveChannel() {
        let packet = BobobeiProtocol.keepAlivePacket(for: .init(motion: 0, vibration: 42, rotation: 9))
        XCTAssertEqual(Array(packet), [1, 1, 0, 2, 0, 1, 17, 42, 0, 2, 17, 1])
    }
}
