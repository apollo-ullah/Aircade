import XCTest
import simd
@testable import MotionCore

final class GripCalibrationSessionTests: XCTestCase {
    let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    let leftPose = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 0, 1))
    let forwardPose = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(-1, 0, 0))

    func hold(_ session: inout GripCalibrationSession, _ q: simd_quatf, time: inout Double,
              speed: Float = 0, source: String = "Left") {
        for _ in 0..<16 {
            time += 0.03
            session.ingest(q: q, speed: speed, sensorTime: time, receivedAt: time, source: source)
        }
    }

    func testCompleteFlowUsesSameReferenceAndRequiresReturnBeforeForward() throws {
        var session = GripCalibrationSession(source: "Left"); var time = 10.0
        let start = simd_quatf(angle: 1.3, axis: simd_normalize(SIMD3<Float>(1, -3, 2)))
        let mount = simd_quatf(angle: 0.9, axis: simd_normalize(SIMD3<Float>(-2, 1, 3)))
        func sensor(_ q: simd_quatf) -> simd_quatf { start * mount.inverse * q * mount }
        hold(&session, start, time: &time)
        XCTAssertTrue(session.capture(at: time))
        hold(&session, sensor(leftPose), time: &time)
        XCTAssertEqual(session.angleDegrees(at: time)!, 30, accuracy: 0.001)
        XCTAssertTrue(session.capture(at: time))
        XCTAssertEqual(session.stage, .returnNeutral)
        hold(&session, sensor(forwardPose), time: &time)
        XCTAssertFalse(session.capture(at: time), "Forward must not skip the explicit neutral check")
        hold(&session, start, time: &time)
        XCTAssertTrue(session.capture(at: time))
        XCTAssertEqual(session.stage, .forward)
        hold(&session, sensor(forwardPose), time: &time)
        XCTAssertTrue(session.capture(at: time))
        XCTAssertEqual(session.stage, .verify)
        XCTAssertNotNil(session.proposedBasis)
        let forward = try XCTUnwrap(session.preview(at: time))
        XCTAssertLessThan(simd_distance(forward.act(SIMD3<Float>(0, 1, 0)), forwardPose.act(SIMD3<Float>(0, 1, 0))), 0.001)
        XCTAssertFalse(session.capture(at: time), "Return upright before committing")
        hold(&session, sensor(leftPose.inverse), time: &time)
        XCTAssertGreaterThan(session.preview(at: time)!.act(SIMD3<Float>(0, 1, 0)).x, 0.49)
        hold(&session, start, time: &time)
        XCTAssertTrue(session.capture(at: time))
        XCTAssertLessThan(simd_length(GripCalibration.rotationVector(reference: start, sample: session.reference!)), 0.001)
    }

    func testCannotCaptureInstantaneousOrMovingNeutral() {
        var session = GripCalibrationSession(source: "Left"); var time = 10.0
        session.ingest(q: identity, speed: 0, sensorTime: time, receivedAt: time, source: "Left")
        XCTAssertFalse(session.capture(at: time))
        hold(&session, identity, time: &time, speed: 0.8)
        XCTAssertFalse(session.capture(at: time))
        hold(&session, identity, time: &time)
        XCTAssertTrue(session.capture(at: time))
    }

    func testOrientationSpreadRejectsDriftingPoseEvenWithLowGyro() {
        var session = GripCalibrationSession(source: "Left")
        for i in 0..<16 {
            let t = 10 + Double(i) * 0.03
            session.ingest(q: simd_quatf(angle: Float(i) * .pi / 180, axis: SIMD3<Float>(0, 0, 1)),
                           speed: 0, sensorTime: t, receivedAt: t, source: "Left")
        }
        XCTAssertFalse(session.capture(at: 10.45))
    }

    func testQuaternionSignFlipsDoNotDestabilizeSteadyPose() {
        var session = GripCalibrationSession(source: "Left")
        for i in 0..<16 {
            let t = 10 + Double(i) * 0.03
            session.ingest(q: simd_quatf(vector: identity.vector * (i % 2 == 0 ? 1 : -1)),
                           speed: 0, sensorTime: t, receivedAt: t, source: "Left")
        }
        XCTAssertTrue(session.capture(at: 10.45))
        XCTAssertLessThan(simd_length(GripCalibration.rotationVector(reference: identity, sample: session.reference!)), 0.001)
    }

    func testRepeatedSensorTimestampCannotProduceSteadyOrFreshPose() {
        var session = GripCalibrationSession(source: "Left")
        for i in 0..<16 {
            session.ingest(q: identity, speed: 0, sensorTime: 10, receivedAt: 10 + Double(i) * 0.03, source: "Left")
        }
        XCTAssertFalse(session.isFresh(at: 10.45))
        XCTAssertFalse(session.capture(at: 10.45))
    }

    func testStaleCaptureCannotSaveAndGapInvalidatesReference() {
        var session = GripCalibrationSession(source: "Left"); var time = 10.0
        hold(&session, identity, time: &time)
        XCTAssertFalse(session.capture(at: time + 0.3))
        XCTAssertTrue(session.capture(at: time))
        time += 0.6
        session.ingest(q: leftPose, speed: 0, sensorTime: time, receivedAt: time, source: "Left")
        XCTAssertNotNil(session.interruption)
        XCTAssertNil(session.reference)
        XCTAssertFalse(session.capture(at: time))
    }

    func testSourceChangeInvalidatesTrialEvenWhenOriginalSourceReturns() {
        var session = GripCalibrationSession(source: "Left"); var time = 10.0
        hold(&session, identity, time: &time)
        XCTAssertTrue(session.capture(at: time))
        hold(&session, leftPose, time: &time, source: "Right")
        hold(&session, leftPose, time: &time)
        XCTAssertNotNil(session.interruption)
        XCTAssertNil(session.reference)
        XCTAssertNil(session.proposedBasis)
        XCTAssertFalse(session.capture(at: time))
    }

    func testSixDegreeTiltAndRepeatedAxisCannotAdvance() {
        var session = GripCalibrationSession(source: "Left"); var time = 10.0
        hold(&session, identity, time: &time); XCTAssertTrue(session.capture(at: time))
        hold(&session, simd_quatf(angle: .pi / 30, axis: SIMD3<Float>(0, 0, 1)), time: &time)
        XCTAssertEqual(session.angleDegrees(at: time)!, 6, accuracy: 0.001)
        XCTAssertFalse(session.capture(at: time))
        hold(&session, leftPose, time: &time); XCTAssertTrue(session.capture(at: time))
        hold(&session, identity, time: &time); XCTAssertTrue(session.capture(at: time))
        hold(&session, leftPose.inverse, time: &time)
        XCTAssertEqual(session.assessment(at: time)?.issue, .sameAxis)
        XCTAssertFalse(session.capture(at: time))
        XCTAssertNil(session.proposedBasis)
    }

    func testThirtyDegreesUnderArbitraryNeutralMountAndQuaternionScale() {
        for index in 1...40 {
            let neutral = simd_quatf(angle: Float(index) * 0.17, axis: simd_normalize(SIMD3<Float>(1, 2, -3)))
            let mount = simd_quatf(angle: Float(index) * 0.27, axis: simd_normalize(SIMD3<Float>(-1, 4, 2)))
            let raw = neutral * mount.inverse * leftPose * mount
            let sample = simd_quatf(vector: raw.vector * (index % 2 == 0 ? -2 : 3))
            let vector = GripCalibration.rotationVector(reference: neutral, sample: sample)
            XCTAssertEqual(simd_length(vector) * 180 / .pi, 30, accuracy: 0.001)
        }
    }

    func testCrossingEulerWrapMeasuresSmallPhysicalRotation() {
        let a = simd_quatf(angle: 179 * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
        let b = simd_quatf(angle: -179 * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(simd_length(GripCalibration.rotationVector(reference: a, sample: b)) * 180 / .pi, 2, accuracy: 0.001)
    }

    func testSourceLockOnlyChangesByExplicitAdoption() {
        var lock = MotionSourceLock()
        XCTAssertFalse(lock.observe("Unknown")); XCTAssertNil(lock.selected)
        XCTAssertTrue(lock.observe("Left")); XCTAssertEqual(lock.selected, "Left")
        XCTAssertFalse(lock.observe("Right")); XCTAssertEqual(lock.selected, "Left")
        XCTAssertEqual(lock.reported, "Right"); XCTAssertFalse(lock.matches)
        XCTAssertTrue(lock.adoptReported()); XCTAssertEqual(lock.selected, "Right")
        XCTAssertTrue(lock.observe("Right"))
        XCTAssertFalse(lock.observe("Unknown")); XCTAssertFalse(lock.adoptReported())
        XCTAssertEqual(lock.selected, "Right")
    }
}
