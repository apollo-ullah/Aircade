import XCTest
import simd
@testable import MotionCore

final class PointerTests: XCTestCase {
    private let centred = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private func yaw(_ degrees: Float) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
    }
    private func pitch(_ degrees: Float) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
    }

    func testCentredOrientationPointsAtTheCentre() {
        var tracker = PointerTracker()
        let point = tracker.update(orientation: centred, sampleAge: 0)
        XCTAssertEqual(point.x, 0, accuracy: 0.001)
        XCTAssertEqual(point.y, 0, accuracy: 0.001)
        XCTAssertFalse(tracker.isLost)
    }

    func testTurningRightByTheYawSpanReachesTheRightEdge() {
        var tracker = PointerTracker()
        let point = tracker.update(orientation: yaw(-22.5), sampleAge: 0)
        XCTAssertEqual(point.x, 1, accuracy: 0.01)
        XCTAssertEqual(point.y, 0, accuracy: 0.01)
    }

    func testTurningPastTheSpanClampsToTheEdgeInBothDirections() {
        var tracker = PointerTracker()
        XCTAssertEqual(tracker.update(orientation: yaw(-70), sampleAge: 0).x, 1, accuracy: 0.001)
        XCTAssertEqual(tracker.update(orientation: yaw(70), sampleAge: 0).x, -1, accuracy: 0.001)
    }

    func testPitchingUpByThePitchSpanReachesTheTopEdge() {
        var tracker = PointerTracker()
        XCTAssertEqual(tracker.update(orientation: pitch(13), sampleAge: 0).y, 1, accuracy: 0.01)
    }

    func testStaleInputMarksThePointerLostAndHoldsItsLastPoint() {
        var tracker = PointerTracker()
        _ = tracker.update(orientation: yaw(-22.5), sampleAge: 0)
        let held = tracker.update(orientation: centred, sampleAge: 0.8)
        XCTAssertTrue(tracker.isLost)
        XCTAssertEqual(held.x, 1, accuracy: 0.01, "a lost pointer holds its last point rather than snapping to centre")
    }

    func testFreshInputAfterALossClearsTheLostFlag() {
        var tracker = PointerTracker()
        _ = tracker.update(orientation: centred, sampleAge: 0.8)
        XCTAssertTrue(tracker.isLost)
        _ = tracker.update(orientation: centred, sampleAge: 0.01)
        XCTAssertFalse(tracker.isLost)
    }

    func testTremorInsideTheDeadZoneDoesNotMoveThePoint() {
        var tracker = PointerTracker()
        _ = tracker.update(orientation: centred, sampleAge: 0)
        let point = tracker.update(orientation: yaw(-0.2), sampleAge: 0)
        XCTAssertEqual(point.x, 0, accuracy: 0.0001)
    }

    func testResetReturnsToTheCentre() {
        var tracker = PointerTracker()
        _ = tracker.update(orientation: yaw(-22.5), sampleAge: 0)
        tracker.reset()
        XCTAssertEqual(tracker.point.x, 0, accuracy: 0.001)
        XCTAssertFalse(tracker.isLost)
    }
}
