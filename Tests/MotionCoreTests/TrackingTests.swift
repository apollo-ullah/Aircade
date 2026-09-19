import XCTest
import simd
@testable import MotionCore

final class TrackingTests: XCTestCase {
    let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    func testRecenterAndKnownRotation() {
        var tracker = OrientationTracker()
        let initial = simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 1, 0))
        tracker.recenter(initial)
        let delta = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let result = tracker.update(initial * delta, basis: identity, delta: 0.02, smoothing: 0)
        XCTAssertEqual(abs(simd_dot(result.vector, delta.vector)), 1, accuracy: 0.0001)
        tracker.recenter(initial * delta)
        XCTAssertEqual(tracker.displayed.real, 1, accuracy: 0.0001)
    }
    func testBasisChangesAxisAndPreservesAngle() {
        var tracker = OrientationTracker()
        tracker.recenter(identity)
        let rotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        let basis = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let result = tracker.update(rotation, basis: basis, delta: 0.02, smoothing: 0)
        let expected = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(abs(simd_dot(result.vector, expected.vector)), 1, accuracy: 0.0001)
    }
    func testQuaternionSignDoesNotMakeFullTurn() {
        var tracker = OrientationTracker()
        tracker.recenter(identity)
        let result = tracker.update(simd_quatf(vector: -identity.vector), basis: identity, delta: 0.02, smoothing: 0.05)
        XCTAssertEqual(abs(result.real), 1, accuracy: 0.0001)
    }
    func testSmoothingIndependentOfSampleRate() {
        var a = OrientationTracker(); var b = OrientationTracker()
        a.recenter(identity); b.recenter(identity)
        let goal = simd_quatf(angle: 1, axis: SIMD3<Float>(0, 1, 0))
        for _ in 0..<50 { _ = a.update(goal, basis: identity, delta: 0.02, smoothing: 0.1) }
        for _ in 0..<100 { _ = b.update(goal, basis: identity, delta: 0.01, smoothing: 0.1) }
        XCTAssertEqual(abs(simd_dot(a.displayed.vector, b.displayed.vector)), 1, accuracy: 0.0001)
    }
    func testContinuityCannotPassWithDuplicatesGapsOrSourceSwitch() {
        var tracker = ContinuityTracker()
        for i in 0...6000 { tracker.ingest(time: Double(i) * 0.02, source: "Left") }
        XCTAssertEqual(tracker.current, 120, accuracy: 0.001)
        XCTAssertFalse(tracker.ingest(time: 120, source: "Left"))
        XCTAssertEqual(tracker.liveStreak(at: 121), 0)
        tracker.ingest(time: 121, source: "Left")
        XCTAssertEqual(tracker.current, 0)
        XCTAssertEqual(tracker.gaps, 1)
        tracker.ingest(time: 121.02, source: "Right")
        XCTAssertEqual(tracker.current, 0)
        XCTAssertEqual(tracker.switches, 1)
        XCTAssertEqual(tracker.longest, 120, accuracy: 0.001)
    }
    func testSwingNeedsReleaseAndCooldown() {
        var detector = SwingDetector()
        XCTAssertTrue(detector.update(speed: 4, time: 1, threshold: 3))
        XCTAssertFalse(detector.update(speed: 5, time: 2, threshold: 3))
        XCTAssertFalse(detector.update(speed: 0, time: 2.1, threshold: 3))
        XCTAssertTrue(detector.update(speed: 4, time: 2.2, threshold: 3))
        XCTAssertFalse(detector.update(speed: 0, time: 2.3, threshold: 3))
        XCTAssertFalse(detector.update(speed: 4, time: 2.4, threshold: 3))
    }
}
