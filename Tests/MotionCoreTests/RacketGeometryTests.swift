import XCTest
import simd
@testable import MotionCore

final class RacketGeometryTests: XCTestCase {
    private let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var head: SIMD3<Float> { RacketDimensions.faceCenter }
    private func pose(_ position: SIMD3<Float> = .zero, _ orientation: simd_quatf? = nil) -> SaberPose {
        SaberPose(position: position, orientation: orientation ?? identity)
    }

    func testMovingBallCrossesStationaryFaceBetweenFramesAt30And60Hz() throws {
        for fps in [30.0, 60.0] {
            let contact = try XCTUnwrap(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / fps,
                ballFrom: head + SIMD3<Float>(0, 0, -0.5), ballTo: head + SIMD3<Float>(0, 0, 0.5)))
            XCTAssertEqual(contact.point.y, head.y, accuracy: 0.001)
            XCTAssertEqual(contact.fraction, 0.35, accuracy: 0.002)
            XCTAssertEqual(contact.velocity, .zero)
            XCTAssertEqual(contact.relativeVelocity.z, -Float(fps), accuracy: 0.001)
            XCTAssertNil(TennisShotResponse.make(contact: contact), "Incoming ball speed cannot power a stationary racket.")
        }
    }

    func testTranslatingRacketCrossesBallBetweenFrames() throws {
        let contact = try XCTUnwrap(RacketGeometry.sweep(from: pose(SIMD3<Float>(0, 0, 0.5)),
            to: pose(SIMD3<Float>(0, 0, -0.5)), dt: 1 / 60,
            ballFrom: head, ballTo: head))
        XCTAssertEqual(contact.fraction, 0.35, accuracy: 0.002)
        XCTAssertGreaterThan(contact.swingSpeed, 50)
        XCTAssertNotNil(TennisShotResponse.make(contact: contact))
    }

    func testFastRotationHitsAtMidpointWhileEndpointsMiss() throws {
        for fps in [30.0, 60.0] {
            let from = pose(.zero, simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0, 0)))
            let to = pose(.zero, simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0)))
            XCTAssertNil(RacketGeometry.sweep(from: from, to: from, dt: 1 / fps, ballFrom: head, ballTo: head))
            XCTAssertNil(RacketGeometry.sweep(from: to, to: to, dt: 1 / fps, ballFrom: head, ballTo: head))
            let contact = try XCTUnwrap(RacketGeometry.sweep(from: from, to: to, dt: 1 / fps, ballFrom: head, ballTo: head))
            XCTAssertGreaterThan(contact.fraction, 0.2)
            XCTAssertLessThan(contact.fraction, 0.5)
            XCTAssertGreaterThan(contact.swingSpeed, 30)
            XCTAssertNotNil(TennisShotResponse.make(contact: contact))
        }
    }

    func testSimultaneouslyMovingRacketAndBallHitAtBothFrameRates() throws {
        for fps in [30.0, 60.0] {
            let dt = 1 / fps
            let before = pose(SIMD3<Float>(0, 0, 0.22))
            let after = pose(SIMD3<Float>(0, 0, -0.12))
            let contact = try XCTUnwrap(RacketGeometry.sweep(from: before, to: after, dt: dt,
                ballFrom: head + SIMD3<Float>(0, 0, -0.24), ballTo: head + SIMD3<Float>(0, 0, 0.10)))
            XCTAssertEqual(contact.fraction, (0.46 - 0.15) / 0.68, accuracy: 0.002)
            XCTAssertEqual(contact.relativeVelocity.z, -0.68 * Float(fps), accuracy: 0.001)
        }
    }

    func testShaftAndOutsideEllipticalFaceMiss() {
        // These were false hits with the old blade/shaft segment test.
        for center in [SIMD3<Float>(0, 0.3, 0), head + SIMD3<Float>(0.7, 0, 0), head + SIMD3<Float>(0.49, 0.65, 0)] {
            XCTAssertNil(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / 60,
                ballFrom: center + SIMD3<Float>(0, 0, -0.5), ballTo: center + SIMD3<Float>(0, 0, 0.5)))
        }
    }

    func testBallRadiusCanTouchFaceBoundaryWithoutExtendingToShaft() throws {
        let center = head + SIMD3<Float>(RacketDimensions.faceHalfWidth + 0.08, 0, 0)
        let contact = try XCTUnwrap(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / 60,
            ballFrom: center + SIMD3<Float>(0, 0, -0.4), ballTo: center + SIMD3<Float>(0, 0, 0.4)))
        XCTAssertEqual(contact.faceCoordinates.x, RacketDimensions.faceHalfWidth, accuracy: 0.001)
        XCTAssertEqual(contact.faceCoordinates.y, 0, accuracy: 0.001)
    }

    func testStationaryAndSlowOverlapsDoNotProducePoweredReturns() throws {
        let stationary = try XCTUnwrap(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / 60, ballFrom: head, ballTo: head))
        XCTAssertEqual(stationary.swingSpeed, 0)
        XCTAssertNil(TennisShotResponse.make(contact: stationary))
        let slow = try XCTUnwrap(RacketGeometry.sweep(from: pose(), to: pose(SIMD3<Float>(0, 0, -0.002)), dt: 1 / 60,
            ballFrom: head, ballTo: head))
        XCTAssertNil(TennisShotResponse.make(contact: slow))
    }

    func testInvalidSamplesFailClosed() {
        let invalidOrientations = [simd_quatf(vector: .zero), simd_quatf(vector: SIMD4<Float>(.nan, 0, 0, 1)),
                                   simd_quatf(vector: SIMD4<Float>(0, 0, 0, .infinity))]
        for orientation in invalidOrientations {
            XCTAssertNil(RacketGeometry.sweep(from: pose(.zero, orientation), to: pose(), dt: 1 / 60, ballFrom: head, ballTo: head))
            XCTAssertNil(RacketGeometry.sweep(from: pose(), to: pose(.zero, orientation), dt: 1 / 60, ballFrom: head, ballTo: head))
        }
        for dt in [0, -0.1, 0.151, Double.nan, Double.infinity, Double.leastNonzeroMagnitude] {
            XCTAssertNil(RacketGeometry.sweep(from: pose(), to: pose(), dt: dt, ballFrom: head, ballTo: head))
        }
        XCTAssertNil(RacketGeometry.sweep(from: pose(SIMD3<Float>(.nan, 0, 0)), to: pose(), dt: 1 / 60, ballFrom: head, ballTo: head))
        XCTAssertNil(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / 60, ballFrom: SIMD3<Float>(0, .infinity, 0), ballTo: head))
        for radius in [Float.nan, .infinity, -1, 0] {
            XCTAssertNil(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / 60, ballFrom: head, ballTo: head, ballRadius: radius))
        }
    }

    func testQuaternionScaleAndSignDoNotChangeContact() throws {
        let normal = try XCTUnwrap(RacketGeometry.sweep(from: pose(), to: pose(), dt: 1 / 60,
            ballFrom: head - SIMD3<Float>(0, 0, 0.5), ballTo: head + SIMD3<Float>(0, 0, 0.5)))
        let scaled = try XCTUnwrap(RacketGeometry.sweep(from: pose(.zero, simd_quatf(vector: identity.vector * 3)),
            to: pose(.zero, simd_quatf(vector: -identity.vector)), dt: 1 / 60,
            ballFrom: head - SIMD3<Float>(0, 0, 0.5), ballTo: head + SIMD3<Float>(0, 0, 0.5)))
        XCTAssertEqual(normal.fraction, scaled.fraction, accuracy: 0.0001)
        XCTAssertEqual(scaled.swingSpeed, 0)
    }

    // A deterministic hit fixture for the production TennisGame adapter: hold the
    // racket head over ballTo and sweep the hilt toward -Z at the chosen speed. Tests
    // can adapt ballTo to TennisBallFlight.position(at: match.elapsed), or choose an
    // orientation and solve hilt = ballTo - q.act(faceCenter). No score mutation needed.
    private func shot(speed: Float, yaw: Float) throws -> TennisShot {
        let orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let hilt = head - orientation.act(head)
        let contact = try XCTUnwrap(RacketGeometry.sweep(from: pose(hilt, orientation),
            to: pose(hilt + SIMD3<Float>(0, 0, -speed / 60), orientation), dt: 1 / 60,
            ballFrom: head, ballTo: head))
        return try XCTUnwrap(TennisShotResponse.make(contact: contact))
    }

    func testFaceAngleChangesAimAndStrengthChangesFlightDuration() throws {
        let left = try shot(speed: 2, yaw: .pi / 6)
        let right = try shot(speed: 2, yaw: -.pi / 6)
        let straight = try shot(speed: 2, yaw: 0)
        XCTAssertLessThan(left.targetX, -0.6)
        XCTAssertGreaterThan(right.targetX, 0.6)
        XCTAssertEqual(straight.targetX, 0, accuracy: 0.001)
        let gentle = try shot(speed: 0.8, yaw: 0)
        let strong = try shot(speed: 6.5, yaw: 0)
        XCTAssertGreaterThan(gentle.flightDuration - strong.flightDuration, 0.5)
        let extreme = try shot(speed: 100, yaw: -.pi / 2)
        XCTAssertEqual(extreme.targetX, TennisShotResponse.maximumTargetX, accuracy: 0.001)
        XCTAssertEqual(extreme.flightDuration, TennisShotResponse.minimumFlightDuration)
        XCTAssertLessThanOrEqual(extreme.swingSpeed, 12)
    }

    func testSwingDirectionIsLimitedAndCannotOverruleTilt() throws {
        let orientation = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0))
        let start = pose(.zero, orientation)
        let ball = orientation.act(head)
        let contact = try XCTUnwrap(RacketGeometry.sweep(from: start,
            to: pose(SIMD3<Float>(0.1, 0, 0), orientation), dt: 1 / 60,
            ballFrom: ball, ballTo: ball))
        let response = try XCTUnwrap(TennisShotResponse.make(contact: contact))
        XCTAssertLessThan(response.targetX, -0.4)
    }

    func testOrientationOnlyFixtureReachesEveryOpponentLaneAt30And60Hz() throws {
        let hilt = SIMD3<Float>(0, -0.5, 0)
        let opponent = AutomaticReboundOpponent()
        for fps in [30.0, 60.0] {
            let dt = 1 / fps
            for sequence in 0..<18 {
                let plan = opponent.returnPlan(rally: sequence, sequence: sequence)
                let flight = TennisBallFlight(born: 0, duration: plan.flightDuration,
                    from: SIMD3<Float>(0, 0.05, -10.5), to: SIMD3<Float>(plan.targetX, -0.1, 0),
                    arcHeight: 2.15, direction: .towardPlayer)
                // Fixed time-to-arrival makes the fixture work as the opponent speeds up.
                let time = flight.arrival - 0.14
                let ballTo = flight.position(at: time)
                let target = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(ballTo - hilt))
                let backswing = simd_quatf(angle: Float(4.8 * dt), axis: SIMD3<Float>(1, 0, 0)) * target
                let contact = try XCTUnwrap(RacketGeometry.sweep(from: pose(hilt, backswing), to: pose(hilt, target), dt: dt,
                    ballFrom: flight.position(at: time - dt), ballTo: ballTo), "Lane \(sequence), \(fps) Hz")
                XCTAssertNotNil(TennisShotResponse.make(contact: contact))
            }
        }
    }
}
