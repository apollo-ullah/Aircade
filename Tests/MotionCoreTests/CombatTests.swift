import XCTest
import simd
@testable import MotionCore

final class CombatTests: XCTestCase {
    let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    func pose(_ angle: Float, x: Float = 0) -> SaberPose {
        SaberPose(position: SIMD3<Float>(x, 0, 0), orientation: simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1)))
    }
    func testFastSwingHitsBetweenSamples() {
        let a = pose(-0.65), b = pose(0.65)
        let center = SIMD3<Float>(0, 1.5, 0), half = SIMD3<Float>(repeating: 0.2)
        XCTAssertNil(CombatGeometry.segmentBox(from: a.point(0), to: a.point(2.35), center: center, half: half))
        XCTAssertNil(CombatGeometry.segmentBox(from: b.point(0), to: b.point(2.35), center: center, half: half))
        let hit = CombatGeometry.sweep(from: a, to: b, dt: 0.02, center: center, half: half)
        XCTAssertNotNil(hit)
        XCTAssertLessThan(hit!.velocity.x, 0)
        XCTAssertGreaterThan(hit!.cuttingAlignment, 0.7)
    }
    func testWebcamTranslationCanHitWithoutRotation() {
        let hit = CombatGeometry.sweep(from: pose(0, x: -0.8), to: pose(0, x: 0.8), dt: 0.08,
                                      center: SIMD3<Float>(0, 1.5, 0), half: SIMD3<Float>(repeating: 0.2))
        XCTAssertNotNil(hit)
        XCTAssertGreaterThan(hit!.velocity.x, 0)
        XCTAssertEqual(hit!.cuttingAlignment, 1, accuracy: 0.001)
    }
    func testStationaryContactHasNoCutSpeed() {
        let hit = CombatGeometry.sweep(from: pose(0), to: pose(0), dt: 0.02,
                                      center: SIMD3<Float>(0, 1.5, 0), half: SIMD3<Float>(repeating: 0.2))
        XCTAssertEqual(hit?.speed, 0)
    }
    func testStalePoseCannotCreateTeleportHit() {
        XCTAssertNil(CombatGeometry.sweep(from: pose(-0.65), to: pose(0.65), dt: 0.6,
                                         center: SIMD3<Float>(0, 1.5, 0), half: SIMD3<Float>(repeating: 0.2)))
    }
    func testNearbySwingThatNeverTouchesDoesNotHit() {
        XCTAssertNil(CombatGeometry.sweep(from: pose(-0.2), to: pose(0.2), dt: 0.02,
                                         center: SIMD3<Float>(4, 1.5, 0), half: SIMD3<Float>(repeating: 0.2)))
    }
    func testGuardRequiresPositionAndAngle() {
        let horizontal = pose(-.pi / 2)
        XCTAssertTrue(CombatGeometry.validGuard(pose: horizontal, target: SIMD3<Float>(1, 0, 0), horizontal: true))
        XCTAssertFalse(CombatGeometry.validGuard(pose: horizontal, target: SIMD3<Float>(1, 0, 0), horizontal: false))
        XCTAssertFalse(CombatGeometry.validGuard(pose: horizontal, target: SIMD3<Float>(1, 2, 0), horizontal: true))
        XCTAssertTrue(CombatGeometry.validGuard(pose: pose(0), target: SIMD3<Float>(0, 1, 0), horizontal: false))
    }
    func testTwoTiltCalibrationMapsAnArbitraryGrip() {
        let mount = simd_quatf(angle: 1.1, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
        let left = mount.inverse.act(SIMD3<Float>(0, 0, 0.7))
        let forward = mount.inverse.act(SIMD3<Float>(-0.6, 0, 0))
        let basis = GripCalibration.basis(left: left, forward: forward)!
        XCTAssertLessThan(simd_distance(basis.act(simd_normalize(left)), SIMD3<Float>(0, 0, 1)), 0.001)
        XCTAssertLessThan(simd_distance(basis.act(simd_normalize(forward)), SIMD3<Float>(-1, 0, 0)), 0.001)
        XCTAssertEqual(simd_determinant(simd_float3x3(basis)), 1, accuracy: 0.001)
    }
    func testCalibrationRejectsTranslationOnlyAndRepeatedAxis() {
        XCTAssertNil(GripCalibration.basis(left: .zero, forward: SIMD3<Float>(0, 1, 0)))
        XCTAssertNil(GripCalibration.basis(left: SIMD3<Float>(1, 0, 0), forward: SIMD3<Float>(1, 0.1, 0)))
    }
    func testRotationVectorIgnoresQuaternionSign() {
        let q = simd_quatf(angle: 0.5, axis: SIMD3<Float>(0, 0, 1))
        let a = GripCalibration.rotationVector(reference: identity, sample: q)
        let b = GripCalibration.rotationVector(reference: identity, sample: simd_quatf(vector: -q.vector))
        XCTAssertLessThan(simd_distance(a, b), 0.001)
    }

    func testCalibrationExplainsInsufficientAndExcessiveTilt() {
        XCTAssertEqual(GripCalibration.assessTilt(SIMD3(0, 0, 0.1)).issue, .tooSmall)
        XCTAssertEqual(GripCalibration.assessTilt(SIMD3(0, 0, 2)).issue, .tooLarge)
        XCTAssertEqual(GripCalibration.assessTilt(SIMD3(.nan, 0, 0)).issue, .invalid)
    }

    func testFinalPoseExplainsRepeatedAxisIncludingOppositeTilt() {
        let left = SIMD3<Float>(0, 0, .pi / 4)
        XCTAssertEqual(GripCalibration.assessTilt(left, comparedTo: left).issue, .sameAxis)
        XCTAssertEqual(GripCalibration.assessTilt(-left, comparedTo: left).issue, .sameAxis)
        let forward = SIMD3<Float>(-.pi / 4, 0, 0)
        let good = GripCalibration.assessTilt(forward, comparedTo: left)
        XCTAssertTrue(good.isValid)
        XCTAssertEqual(good.degrees, 45, accuracy: 0.01)
        XCTAssertEqual(good.separationDegrees!, 90, accuracy: 0.01)
        XCTAssertNotNil(GripCalibration.basis(left: left, forward: forward))
    }
}
