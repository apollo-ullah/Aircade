import XCTest
import simd
@testable import MotionCore

final class AIChallengeTests: XCTestCase {
    func command(_ m: AIChallengeMatch, x: Float = 0, swing: Bool = false, sequence: Int = 1) -> TennisControlCommand {
        TennisControlCommand(run: m.run, rally: m.rally, sequence: sequence, frame: 1, x: x, swing: swing)
    }
    func testIdentityExpiryAndReplay() {
        var m = AIChallengeMatch(); m.start()
        XCTAssertFalse(m.apply(command(m), observationAge: 6.01))
        XCTAssertTrue(m.apply(command(m), observationAge: 0.5))
        XCTAssertFalse(m.apply(command(m), observationAge: 0.5))
        var wrong = command(m, sequence: 2); wrong.run = "old"
        XCTAssertFalse(m.apply(wrong, observationAge: 0))
        wrong.run = m.run; wrong.rally = 99
        XCTAssertFalse(m.apply(wrong, observationAge: 0))
        m.pause(); XCTAssertFalse(m.apply(command(m, sequence: 2), observationAge: 0))
    }
    func testMovementAndNoAutomaticStroke() {
        var controller = TennisOpponentController(); controller.input(x: 100, swing: false)
        controller.advance(0.1)
        XCTAssertEqual(controller.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(controller.target, 4.6)
        XCTAssertFalse(controller.swinging)
        controller.advance(.infinity); XCTAssertEqual(controller.x, 0.3, accuracy: 0.001)
        controller.input(x: 0, swing: true); controller.advance(0.1)
        XCTAssertTrue(controller.swinging)
        XCTAssertEqual(controller.pose.position.z, -19.095, accuracy: 0.001)
    }
    func testIdleMissesOnceAndAlternatingServe() {
        var m = AIChallengeMatch(); m.start()
        for _ in 0..<550 { _ = m.advance(1.0 / 60) }
        XCTAssertEqual(m.humanPoints, 1); XCTAssertEqual(m.aiPoints, 0)
        XCTAssertEqual(m.aiReturns, 0); XCTAssertEqual(m.rally, 1)
        for _ in 0..<90 { _ = m.advance(1.0 / 60) }
        XCTAssertEqual(m.ball?.direction, .towardPlayer)
    }
    func testRealControllerContactAndWrongLaneMiss() {
        for shouldHit in [true, false] {
            var m = AIChallengeMatch(); m.start(); var sent = false
            for _ in 0..<570 {
                if !sent, m.elapsed >= 6.7 {
                    XCTAssertTrue(m.apply(command(m, x: shouldHit ? -2.5 : 2.5, swing: true), observationAge: 0)); sent = true
                }
                _ = m.advance(1.0 / 60)
            }
            XCTAssertEqual(m.aiReturns, shouldHit ? 1 : 0)
            XCTAssertEqual(m.humanPoints, shouldHit ? 0 : 1)
        }
    }
    func testHumanFaceReturnsThroughSameGeometryAndCannotHitFlightTwice() {
        var m = AIChallengeMatch(); m.start()
        while m.ball?.direction != .towardPlayer { _ = m.advance(1.0 / 60) }
        let flight = m.ball!
        while m.elapsed < flight.arrival - 0.05 { _ = m.advance(1.0 / 60) }
        let centre = flight.position(at: m.elapsed), dt = 1.0 / 60
        let orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let base = centre - RacketDimensions.faceCenter
        let before = SaberPose(position: base + SIMD3<Float>(0, 0, 0.1), orientation: orientation)
        let after = SaberPose(position: base - SIMD3<Float>(0, 0, 0.1), orientation: orientation)
        XCTAssertNotNil(m.humanContact(from: before, to: after, dt: dt, ballFrom: flight.position(at: m.elapsed - dt), flightID: flight.id))
        XCTAssertEqual(m.humanReturns, 1); XCTAssertEqual(m.ball?.direction, .towardOpponent)
        XCTAssertNil(m.humanContact(from: before, to: after, dt: dt, ballFrom: centre, flightID: flight.id))
        XCTAssertEqual(m.humanReturns, 1)
    }

    func testResultsAndPauseClock() {
        var m = AIChallengeMatch(); m.start(); m.pause()
        _ = m.advance(0.1); XCTAssertEqual(m.elapsed, 0)
        m.resume()
        for _ in 0..<3601 { _ = m.advance(1.0 / 60) }
        XCTAssertEqual(m.phase, .results); XCTAssertEqual(m.elapsed, 60)
        let score = m.humanPoints + m.aiPoints
        _ = m.advance(0.1); XCTAssertEqual(m.humanPoints + m.aiPoints, score)
        m.start(); XCTAssertEqual(m.humanPoints, 0); XCTAssertEqual(m.winner, "Draw")
    }
}
