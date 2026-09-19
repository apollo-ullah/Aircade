import XCTest
import simd
@testable import MotionCore

final class SaberDuelTests: XCTestCase {
    let upright = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    let openGuard = simd_quatf(angle: -1.2, axis: SIMD3<Float>(1, 0, 0))
    func poses(_ first: Float = 0, guardQ: simd_quatf? = nil) -> [SaberPose?] {
        [SaberDuel.pose(.one, simd_quatf(angle: first, axis: SIMD3(0, 0, 1))),
         SaberDuel.pose(.two, guardQ ?? openGuard)]
    }
    func begin(_ game: inout SaberDuel, _ time: inout Double, guardQ: simd_quatf? = nil) {
        game.start()
        for _ in 0..<185 { time += 1.0 / 60; _ = game.step(at: time, poses: poses(guardQ: guardQ)) }
        XCTAssertEqual(game.phase, .playing)
    }
    func testIndependentPosesCanFinishAFullMatchAndReplayResets() {
        for hz in [30.0, 60.0] {
            var game = SaberDuel(), time = 100.0
            begin(&game, &time)
            var events: [SaberDuel.Event] = []
            for i in 0..<Int(15 * hz) {
                let t = (Double(i) / hz).truncatingRemainder(dividingBy: 1.6)
                let angle: Float = t < 0.3 ? Float(t / 0.3) * -1.15 : t < 0.5 ? -1.15 : t < 0.9 ? -1.15 * Float(1 - (t - 0.5) / 0.4) : 0
                time += 1 / hz; events += game.step(at: time, poses: poses(angle))
                if game.phase == .results { break }
            }
            XCTAssertEqual(game.phase, .results)
            XCTAssertEqual(game.winner, .one)
            XCTAssertEqual(game.health, [5, 0])
            XCTAssertEqual(events.filter { $0.kind == .hit }.count, 5)
            for _ in 0..<100 { time += 0.02; XCTAssertTrue(game.step(at: time, poses: poses(-1)).isEmpty) }
            game.start(); XCTAssertEqual(game.health, [5, 5]); XCTAssertNil(game.winner); XCTAssertEqual(game.elapsed, 0)
        }
    }
    func testStationaryOverlapAndSlowTouchNeverDamage() {
        var game = SaberDuel(), time = 0.0
        begin(&game, &time)
        // A slow approach, then a stationary blade embedded in the target.
        for i in 0..<800 {
            time += 1 / 60
            let angle = -min(1.15, Float(i) * 0.002)
            XCTAssertTrue(game.step(at: time, poses: poses(angle)).isEmpty)
        }
        XCTAssertEqual(game.health, [5, 5]); XCTAssertEqual(game.phase, .playing)
    }
    func testCrossedBladesParryInsteadOfDamagingTheTarget() {
        var game = SaberDuel(), time = 0.0
        begin(&game, &time, guardQ: upright)
        var events: [SaberDuel.Event] = []
        for i in 0...20 {
            time += 1 / 60; events += game.step(at: time, poses: poses(-Float(i) / 20 * 1.15, guardQ: upright))
        }
        XCTAssertTrue(events.contains { $0.kind == .clash })
        XCTAssertFalse(events.contains { $0.kind == .hit })
        XCTAssertEqual(game.health, [5, 5])
    }
    func testLostInputFreezesAndCannotBecomeAReconnectionSlash() {
        var game = SaberDuel(), time = 100.0
        begin(&game, &time)
        let elapsed = game.elapsed
        time += 0.3; _ = game.step(at: time, poses: [nil, poses()[1]])
        time += 0.2; _ = game.step(at: time, poses: poses(-1.15))
        XCTAssertEqual(game.elapsed, elapsed); XCTAssertEqual(game.health, [5, 5])
        time += 0.1; _ = game.step(at: time, poses: poses(-1.15))
        XCTAssertEqual(game.health, [5, 5]); XCTAssertEqual(game.phase, .playing)
        time += 0.3; _ = game.step(at: time, poses: [nil, nil])
        time += 1.01; _ = game.step(at: time, poses: [nil, nil])
        XCTAssertEqual(game.phase, .paused)
        let frozen = game.elapsed
        time += 1; _ = game.step(at: time, poses: poses())
        XCTAssertEqual(game.phase, .paused); XCTAssertEqual(game.elapsed, frozen)
        game.resume(); XCTAssertEqual(game.phase, .countdown)
    }
    func testTimeoutDrawAndNoCatchUpAfterLongFrames() {
        var game = SaberDuel(), time = 0.0
        begin(&game, &time)
        let elapsed = game.elapsed
        time += 4; _ = game.step(at: time, poses: poses(-1.15))
        XCTAssertEqual(game.elapsed, elapsed); XCTAssertEqual(game.health, [5, 5])
        for _ in 0..<3700 { time += 1 / 60; _ = game.step(at: time, poses: poses(-1.15)) }
        XCTAssertEqual(game.phase, .results); XCTAssertNil(game.winner)
    }
    func testPhonePortraitAxesAndRecenterAreIndependentOfStartingAttitude() {
        var phone = PhoneOrientation()
        let initial = simd_quatf(angle: 1.2, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
        XCTAssertNil(phone.calibrated(initial))
        phone.recenter(initial)
        let left = phone.calibrated(initial * simd_quatf(angle: 0.5, axis: SIMD3(0, 0, 1)))!
        XCTAssertLessThan(left.act(SIMD3<Float>(0, 1, 0)).x, -0.4)
        let forward = phone.calibrated(initial * simd_quatf(angle: -0.5, axis: SIMD3(1, 0, 0)))!
        XCTAssertLessThan(forward.act(SIMD3<Float>(0, 1, 0)).z, -0.4)
        phone.recenter(initial * left)
        XCTAssertLessThan(abs(phone.calibrated(initial * left)!.angle), 0.001)
    }
}
