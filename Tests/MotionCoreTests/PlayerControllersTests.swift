import XCTest
import simd
@testable import MotionCore

final class PlayerControllersTests: XCTestCase {
    let p1 = UUID(), p2 = UUID(), session = UUID()
    func frame(_ id: UUID, _ sequence: UInt64, session: UUID? = nil, angle: Float = 0,
               ready: Bool = true, age: Double = 0) -> PlayerControllerFrame {
        PlayerControllerFrame(controllerID: id, sessionID: session ?? self.session, sequence: sequence,
                              source: "Right", orientation: simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1)),
                              ready: ready, sampleAge: age)
    }
    func testTwoRightEarbudsCanDriveDifferentPlayersWithoutCrossTalk() {
        var players = PlayerControllers()
        XCTAssertTrue(players.assign(.one, controllerID: p1, sessionID: session))
        XCTAssertTrue(players.assign(.two, controllerID: p2, sessionID: session))
        XCTAssertTrue(players.receive(frame(p1, 1, angle: 0.5), for: .one, at: 100))
        XCTAssertTrue(players.receive(frame(p2, 1, angle: -0.5), for: .two, at: 100))
        XCTAssertLessThan(players[.one]!.orientation!.act(SIMD3<Float>(0, 1, 0)).x, 0)
        XCTAssertGreaterThan(players[.two]!.orientation!.act(SIMD3<Float>(0, 1, 0)).x, 0)
        XCTAssertFalse(players.assign(.two, controllerID: p1, sessionID: session))
        XCTAssertFalse(players.receive(frame(p1, 2), for: .two, at: 100.01))
    }
    func testDuplicateReorderedAndPreviousSessionPacketsCannotRefreshInput() {
        var players = PlayerControllers()
        players.assign(.one, controllerID: p1, sessionID: session)
        players.receive(frame(p1, 3), for: .one, at: 100)
        XCTAssertFalse(players.receive(frame(p1, 3), for: .one, at: 100.2))
        XCTAssertFalse(players.receive(frame(p1, 2), for: .one, at: 100.2))
        XCTAssertFalse(players.receive(frame(p1, 4, session: UUID()), for: .one, at: 100.2))
        XCTAssertFalse(players[.one]!.isFresh(at: 100.3))
        XCTAssertTrue(players.receive(frame(p1, 4), for: .one, at: 100.31))
        XCTAssertTrue(players[.one]!.isFresh(at: 100.32))
    }
    func testSenderAgeAndDisconnectInvalidateOnlyThatPlayer() {
        var players = PlayerControllers()
        players.assign(.one, controllerID: p1, sessionID: session)
        players.assign(.two, controllerID: p2, sessionID: session)
        players.receive(frame(p1, 1, age: 0.3), for: .one, at: 100)
        players.receive(frame(p2, 1), for: .two, at: 100)
        XCTAssertFalse(players[.one]!.isFresh(at: 100.01))
        XCTAssertTrue(players[.two]!.isFresh(at: 100.01))
        players.receive(frame(p2, 2, ready: false), for: .two, at: 100.02)
        XCTAssertFalse(players[.two]!.isFresh(at: 100.02))
        players.remove(.two)
        XCTAssertNil(players[.two])
        XCTAssertNotNil(players[.one])
    }
    func testWireRoundTripAndMalformedFrameRejection() throws {
        let original = frame(p1, 1, angle: 0.3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlayerControllerFrame.self, from: data)
        XCTAssertTrue(decoded.isValid)
        XCTAssertEqual(decoded.orientation, original.orientation)
        var invalid = decoded; invalid.version = 99
        var players = PlayerControllers()
        players.assign(.one, controllerID: p1, sessionID: session)
        XCTAssertFalse(players.receive(invalid, for: .one, at: 100))
        XCTAssertFalse(players.receive(frame(p1, 2, age: -1), for: .one, at: 100))
        XCTAssertFalse(players.receive(frame(p1, 2), for: .one, at: .nan))
    }

    func testCaptureTimeIsStableAndInvalidationRetainsSequenceWatermark() {
        var players = PlayerControllers()
        players.assign(.one, controllerID: p1, sessionID: session)
        players.receive(frame(p1, 8, age: 0.04), for: .one, at: 100)
        XCTAssertEqual(players[.one]!.capturedAt!, 99.96, accuracy: 0.000001)
        XCTAssertEqual(players[.one]!.sampleAge(at: 100.15), 0.19, accuracy: 0.000001)
        XCTAssertFalse(players[.one]!.isFresh(at: 99.99))
        players.invalidate(.one)
        XCTAssertFalse(players[.one]!.isFresh(at: 100.1))
        XCTAssertFalse(players.receive(frame(p1, 8), for: .one, at: 100.1))
        XCTAssertTrue(players.receive(frame(p1, 9), for: .one, at: 100.11))
    }
}
