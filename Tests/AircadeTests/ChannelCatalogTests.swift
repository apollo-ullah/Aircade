import XCTest
@testable import Aircade

final class ChannelCatalogTests: XCTestCase {
    func testTheGridHoldsExactlySixChannelsInTheSpecifiedOrder() {
        XCTAssertEqual(ChannelCatalog.all.map(\.route),
                       [.tennis, .neonRush, .duel, .controller, .profile, .lab])
    }

    func testEveryChannelHasANameThatFitsOnOneLine() {
        for channel in ChannelCatalog.all {
            XCTAssertFalse(channel.title.isEmpty)
            XCTAssertLessThanOrEqual(channel.title.count, 16, "\(channel.title) will wrap its name strip")
        }
    }

    func testAPointInsideATileSelectsThatChannel() {
        let frames: [Route: CGRect] = [
            .neonRush: CGRect(x: 0, y: 0, width: 100, height: 100),
            .duel: CGRect(x: 120, y: 0, width: 100, height: 100)
        ]
        let size = CGSize(width: 240, height: 100)
        let hit = ChannelCatalog.channel(at: CGPoint(x: 0.7, y: 0.5), frames: frames, in: size)
        XCTAssertEqual(hit, .duel)
    }

    func testAPointInTheGapBetweenTilesSelectsNothing() {
        let frames: [Route: CGRect] = [
            .neonRush: CGRect(x: 0, y: 0, width: 100, height: 100),
            .duel: CGRect(x: 120, y: 0, width: 100, height: 100)
        ]
        let size = CGSize(width: 240, height: 100)
        XCTAssertNil(ChannelCatalog.channel(at: CGPoint(x: 0.458, y: 0.5), frames: frames, in: size))
    }
}
