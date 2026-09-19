import XCTest
import simd
import MotionCore
@testable import Aircade

/// Repeated or out-of-order transport samples must not replace the last valid
/// collision pose. Every hit below goes through a game's production update path.
final class CollisionTimestampIntegrationTests: XCTestCase {
    private final class Storage {
        let suite = "com.aircade.collision-timestamps.\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: suite)! }
        deinit { defaults.removePersistentDomain(forName: suite) }
    }

    private let upright = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    func testEqualTimestampCannotEraseNeonRushSwingHistory() throws {
        try checkRushHistory(replayedOffset: 0)
    }

    func testOlderTimestampCannotReplaceNeonRushSwingHistory() throws {
        try checkRushHistory(replayedOffset: -0.01)
    }

    func testEqualTimestampCannotEraseTennisSwingHistory() throws {
        try checkTennisHistory(replayedOffset: 0)
    }

    func testOlderTimestampCannotReplaceTennisSwingHistory() throws {
        try checkTennisHistory(replayedOffset: -0.01)
    }

    private func checkRushHistory(replayedOffset: Double) throws {
        let storage = Storage()
        var time = 100.0
        let game = ArcadeGame(scene: SaberScene(), automaticTimer: false,
                              clock: { time }, scoreDefaults: storage.defaults)
        game.sound = false
        game.renderingEnabled = false
        let parked = SaberPose(position: SIMD3<Float>(5, -0.5, 0), orientation: upright)
        game.update(pose: parked, time: time, ready: true)
        game.start(demo: true, seed: 42)
        for _ in 0..<400 {
            time += 1.0 / 60
            game.update(pose: parked, time: time, ready: true)
            game.tick()
            if let target = game.state.targets.first, game.state.elapsed >= target.arrival + 0.02 { break }
        }
        XCTAssertEqual(game.state.phase, .playing)
        let target = try XCTUnwrap(game.state.targets.first)
        XCTAssertGreaterThanOrEqual(game.state.elapsed, target.arrival)
        let before = SaberPose(position: SIMD3<Float>(target.x + 0.8, -0.5, 0), orientation: upright)
        let after = SaberPose(position: SIMD3<Float>(target.x - 0.8, -0.5, 0), orientation: upright)
        time += 0.02
        game.update(pose: before, time: time, ready: true)
        XCTAssertEqual(game.state.cuts, 0)

        // Changed coordinates on an equal/older timestamp are not a new motion
        // segment. The following fresh sample must still sweep from `before`.
        game.update(pose: after, time: time + replayedOffset, ready: true)
        XCTAssertEqual(game.state.cuts, 0)
        time += 0.02
        game.update(pose: after, time: time, ready: true)
        XCTAssertEqual(game.state.cuts, 1)
        XCTAssertGreaterThan(game.state.score, 0)
        XCTAssertEqual(game.state.phase, .playing)
        game.update(pose: after, time: time, ready: true)
        XCTAssertEqual(game.state.cuts, 1, "A repeated result sample cannot cut the same target twice")
        XCTAssertEqual(storage.defaults.integer(forKey: "neonRush.best.Arcade"), 0)
    }

    private func checkTennisHistory(replayedOffset: Double) throws {
        let storage = Storage()
        var time = 100.0
        let game = TennisGame(scene: SaberScene(), automaticTimer: false,
                              clock: { time }, scoreDefaults: storage.defaults)
        game.enabled = true
        game.sound = false
        let parked = SaberPose(position: SIMD3<Float>(0, 10, 2), orientation: upright)
        game.update(pose: parked, time: time, ready: true)
        game.start(demo: true)
        for _ in 0..<400 {
            time += 1.0 / 60
            game.update(pose: parked, time: time, ready: true)
            game.tick()
            if let ball = game.state.ball, game.state.elapsed >= ball.arrival - 0.14 { break }
        }
        XCTAssertEqual(game.state.phase, .playing)
        let incoming = try XCTUnwrap(game.state.ball)
        XCTAssertEqual(incoming.direction, .towardPlayer)
        XCTAssertGreaterThanOrEqual(game.state.elapsed, incoming.arrival - 0.32)
        let centre = incoming.position(at: game.state.elapsed)
        let hilt = centre - RacketDimensions.faceCenter
        let before = SaberPose(position: hilt + SIMD3<Float>(0, 0, 0.3), orientation: upright)
        let after = SaberPose(position: hilt - SIMD3<Float>(0, 0, 0.3), orientation: upright)
        time += 0.02
        game.update(pose: before, time: time, ready: true)
        XCTAssertEqual(game.state.returns, 0)

        game.update(pose: after, time: time + replayedOffset, ready: true)
        XCTAssertEqual(game.state.returns, 0)
        time += 0.02
        game.update(pose: after, time: time, ready: true)
        XCTAssertEqual(game.state.returns, 1)
        XCTAssertGreaterThan(game.state.score, 0)
        XCTAssertEqual(game.state.ball?.direction, .towardOpponent)
        game.update(pose: after, time: time, ready: true)
        XCTAssertEqual(game.state.returns, 1, "A repeated sample cannot score the same ball twice")
        XCTAssertEqual(storage.defaults.integer(forKey: "tennis.best"), 0)
    }
}
