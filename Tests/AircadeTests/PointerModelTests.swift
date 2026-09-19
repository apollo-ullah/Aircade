import XCTest
import simd
@testable import Aircade

final class PointerModelTests: XCTestCase {
    private let centred = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    func testFreshMotionTakesOverAndCentresTheCursor() {
        let model = PointerModel()
        model.ingestMotion(orientation: centred, sampleAge: 0, speed: 0, time: 1)
        XCTAssertEqual(model.source, .motion)
        XCTAssertEqual(model.unitPoint.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.unitPoint.y, 0.5, accuracy: 0.001)
    }

    func testPitchingUpMovesTheCursorUpTheScreen() {
        let model = PointerModel()
        let up = simd_quatf(angle: 13 * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
        model.ingestMotion(orientation: up, sampleAge: 0, speed: 0, time: 1)
        XCTAssertLessThan(model.unitPoint.y, 0.1, "screen y runs downward, so pitching up must lower it")
    }

    func testStaleMotionHandsControlBackToTheMouse() {
        let model = PointerModel()
        model.ingestMotion(orientation: centred, sampleAge: 0, speed: 0, time: 1)
        model.ingestMotion(orientation: centred, sampleAge: 0.9, speed: 0, time: 2)
        XCTAssertEqual(model.source, .mouse)
        XCTAssertTrue(model.isLost)
    }

    func testMouseTemporarilyOverridesControllerAndReacquisitionCannotClick() {
        let model = PointerModel()
        model.ingestMotion(orientation: centred, sampleAge: 0, speed: 0, time: 1)
        model.ingestMouse(CGPoint(x: 0.9, y: 0.9), time: 2)
        XCTAssertFalse(model.ingestMotion(orientation: centred, sampleAge: 0, speed: 9, time: 3))
        XCTAssertEqual(model.source, .mouse)
        XCTAssertEqual(model.unitPoint.x, 0.9, accuracy: 0.001)
        XCTAssertFalse(model.ingestMotion(orientation: centred, sampleAge: 0, speed: 9, time: 4.1))
        XCTAssertEqual(model.source, .motion)
    }

    func testAFlickWhileReacquiringInputDoesNotSelectAnything() {
        let model = PointerModel()
        // First sample after a loss: the motion of reconnecting must not click.
        let clicked = model.ingestMotion(orientation: centred, sampleAge: 0, speed: 9, time: 1)
        XCTAssertFalse(clicked)
    }

    func testAFlickAfterTheBlackoutSelects() {
        let model = PointerModel()
        model.ingestMotion(orientation: centred, sampleAge: 0, speed: 0, time: 1)
        let clicked = model.ingestMotion(orientation: centred, sampleAge: 0, speed: 9, time: 1.8)
        XCTAssertTrue(clicked)
    }

    func testASlowSweepIsNotAFlick() {
        let model = PointerModel()
        model.ingestMotion(orientation: centred, sampleAge: 0, speed: 0, time: 1)
        let clicked = model.ingestMotion(orientation: centred, sampleAge: 0, speed: 0.4, time: 1.8)
        XCTAssertFalse(clicked)
    }
}
