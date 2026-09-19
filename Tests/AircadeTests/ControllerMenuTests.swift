import XCTest
import simd
@testable import Aircade

final class ControllerMenuTests: XCTestCase {
    func testHoldSelectsOnceAndLeavingRearmsIt() {
        var dwell = MenuDwell(); let a = UUID(), b = UUID()
        XCTAssertNil(dwell.update(target: a, time: 1, allowed: true))
        XCTAssertNil(dwell.update(target: a, time: 1.9, allowed: true))
        XCTAssertEqual(dwell.update(target: a, time: 2.1, allowed: true), a)
        XCTAssertNil(dwell.update(target: a, time: 8, allowed: true))
        XCTAssertNil(dwell.update(target: b, time: 9, allowed: true))
        XCTAssertEqual(dwell.update(target: b, time: 10.1, allowed: true), b)
    }

    func testLossOrDisabledTargetCancelsANearlyCompleteHold() {
        var dwell = MenuDwell(); let id = UUID()
        _ = dwell.update(target: id, time: 1, allowed: true)
        _ = dwell.update(target: id, time: 1.9, allowed: true)
        XCTAssertNil(dwell.update(target: id, time: 2, allowed: false))
        XCTAssertEqual(dwell.progress, 0)
        XCTAssertNil(dwell.update(target: id, time: 3, allowed: true))
        XCTAssertNil(dwell.update(target: nil, time: 4.1, allowed: true))
        XCTAssertNil(dwell.target)
    }

    private let session = UUID(), device = UUID()
    private func sample(_ time: Double, point: CGPoint, age: Double = 0) -> ControllerSnapshot {
        let x = Float((point.x * 2 - 1) * 22.5 * .pi / 180)
        let y = Float((1 - point.y * 2) * 13 * .pi / 180)
        let up = simd_normalize(SIMD3<Float>(tan(x), 1, tan(y)))
        return ControllerSnapshot(device: .airPod, controllerID: device, sessionID: session, sequence: UInt64(time * 1000),
            source: "Test AirPod", orientation: simd_quatf(from: SIMD3<Float>(0, 1, 0), to: up), receivedAt: time - age,
            capturedAt: time - age, ready: true, simulated: true)
    }

    @MainActor
    func testCalibratedTiltAndHoldInvokesTheActualTargetAndCannotClickDuringGameplay() {
        let menu = ControllerMenu(playSound: { _ in }); menu.size = CGSize(width: 1000, height: 1000)
        let id = UUID(); var clicks = 0
        menu.setTargets([ControllerMenuTarget(id: id, frame: CGRect(x: 700, y: 100, width: 250, height: 300), enabled: true, action: { clicks += 1 })])
        let centre = CGPoint(x: 0.5, y: 0.5), target = CGPoint(x: 0.8, y: 0.2)
        menu.update(sample: sample(1, point: centre), time: 1, context: "home", enabled: true)
        for time in stride(from: 1.1, through: 3, by: 0.1) {
            menu.update(sample: sample(time, point: target), time: time, context: "home", enabled: true)
        }
        XCTAssertEqual(menu.hovered, id); XCTAssertEqual(clicks, 1)
        for time in stride(from: 3.1, through: 6, by: 0.1) {
            menu.update(sample: sample(time, point: target), time: time, context: "playing", enabled: false)
        }
        XCTAssertEqual(clicks, 1); XCTAssertFalse(menu.active)
        // A newly opened menu must not activate just because the hand was already resting there.
        for time in stride(from: 6.1, through: 8, by: 0.1) {
            menu.update(sample: sample(time, point: target), time: time, context: "results", enabled: true)
        }
        XCTAssertEqual(clicks, 1)
    }

    @MainActor
    func testStaleMotionAndMouseMovementCancelSelection() {
        let menu = ControllerMenu(playSound: { _ in }); menu.size = CGSize(width: 1000, height: 1000)
        var clicks = 0
        menu.setTargets([ControllerMenuTarget(id: UUID(), frame: CGRect(x: 700, y: 100, width: 250, height: 300), enabled: true, action: { clicks += 1 })])
        let target = CGPoint(x: 0.8, y: 0.2)
        menu.update(sample: sample(1, point: CGPoint(x: 0.5, y: 0.5)), time: 1, context: "home", enabled: true)
        for time in stride(from: 1.1, through: 2.2, by: 0.1) { menu.update(sample: sample(time, point: target), time: time, context: "home", enabled: true) }
        menu.update(sample: sample(2.5, point: target, age: 0.3), time: 2.5, context: "home", enabled: true)
        XCTAssertEqual(clicks, 0); XCTAssertEqual(menu.progress, 0)
        menu.mouse(.zero, time: 3); menu.mouse(CGPoint(x: 0.2, y: 0.2), time: 3.1)
        menu.update(sample: sample(3.2, point: target), time: 3.2, context: "home", enabled: true)
        XCTAssertFalse(menu.active); XCTAssertEqual(clicks, 0)
    }
}
