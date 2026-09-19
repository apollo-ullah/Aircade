import XCTest
import MotionCore
@testable import Aircade

final class ScriptedGameTests: XCTestCase {
    final class Rig {
        var time = 100.0
        let game: ArcadeGame
        var controller: ScriptedSaber
        var judgments: [RushJudgment] = []
        let defaults: UserDefaults
        let suite: String
        init(_ script: SaberScript, difficulty: RushDifficulty = .arcade, seed: UInt64 = 42) {
            suite = "com.aircade.game-tests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            controller = ScriptedSaber(script)
            // The production update() path performs geometric sweeps and judgments.
            // Rendering/audio are disabled only in these accelerated checks.
            var readTime: () -> Double = { 100 }
            game = ArcadeGame(scene: SaberScene(), automaticTimer: false, clock: { readTime() }, scoreDefaults: defaults)
            readTime = { [unowned self] in self.time }
            game.renderingEnabled = false; game.sound = false; game.difficulty = difficulty
            game.onJudgment = { [weak self] in self?.judgments.append($0) }
            game.update(pose: ScriptedSaber.parked, time: time, ready: true)
            game.start(demo: true, seed: seed)
        }
        deinit { defaults.removePersistentDomain(forName: suite) }
        func step(_ dt: Double = 1.0 / 60) {
            time += dt
            game.update(pose: controller.pose(for: game.state), time: time, ready: true)
            game.tick()
        }
        func run(until predicate: () -> Bool, dt: Double = 1.0 / 60) {
            for _ in 0..<Int(75 / dt) {
                step(dt)
                if predicate() || game.state.phase == .results || game.state.phase == .paused { return }
            }
        }
    }

    func testStationarySlowAndThrustContactsDoNotCutThroughProductionGeometry() {
        for script in [SaberScript.stationary, .slowTouch, .thrust] {
            let rig = Rig(script)
            rig.run(until: { !rig.judgments.isEmpty })
            XCTAssertEqual(rig.judgments.first?.kind, .miss, script.rawValue)
            XCTAssertEqual(rig.game.state.score, 0, script.rawValue)
            XCTAssertEqual(rig.game.state.cuts, 0, script.rawValue)
            XCTAssertEqual(rig.game.state.lives, 4, script.rawValue)
            XCTAssertEqual(rig.game.state.phase, .playing, "A miss must not pause the game")
        }
    }

    func testScriptWinsBothDifficultiesAcrossSeedsAndFrameRatesUsingOnlyPoses() {
        for difficulty in RushDifficulty.allCases {
            for (seed, dt) in [(UInt64(42), 1.0 / 60), (UInt64(991), 1.0 / 30)] {
                let rig = Rig(.perfectRun, difficulty: difficulty, seed: seed)
                rig.run(until: { rig.game.state.phase == .results }, dt: dt)
                XCTAssertTrue(rig.game.state.completed, "\(difficulty) seed \(seed): \(rig.judgments.map { String(describing: $0.kind) })")
                XCTAssertEqual(rig.game.state.lives, difficulty.lives)
                XCTAssertEqual(rig.game.state.mistakes, 0)
                XCTAssertGreaterThan(rig.game.state.cuts, 25)
                XCTAssertEqual(rig.game.state.rank, "S")
                XCTAssertEqual(rig.game.state.remaining, 0)
                XCTAssertEqual(rig.game.state.cuts, rig.judgments.count)
                XCTAssertEqual(Set(rig.judgments.map { $0.target.id }).count, rig.judgments.count, "A block scores once")
                var expected = 0
                for (index, judgment) in rig.judgments.enumerated() {
                    XCTAssertEqual(judgment.kind, .perfect)
                    let points = 150 * min(4, 1 + index / 5)
                    XCTAssertEqual(judgment.points, points)
                    expected += points
                }
                XCTAssertEqual(rig.game.state.score, expected)
                XCTAssertEqual(rig.defaults.integer(forKey: "neonRush.best.\(difficulty.rawValue)"), 0, "Scripted tests cannot save high scores")
            }
        }
    }

    func testWrongWayAndHazardScriptsLoseExactlyOneLifePerJudgment() {
        for (script, kind) in [(SaberScript.wrongWay, RushJudgment.Kind.wrongDirection), (.hazards, .hazard)] {
            let rig = Rig(script)
            rig.run(until: { rig.judgments.contains { $0.kind == kind } })
            XCTAssertEqual(rig.judgments.last?.kind, kind)
            XCTAssertEqual(rig.judgments.last?.points, 0)
            XCTAssertEqual(rig.game.state.lives, 4)
            XCTAssertEqual(rig.game.state.combo, 0)
            XCTAssertEqual(rig.game.state.mistakes, 1)
            XCTAssertEqual(rig.game.state.phase, .playing)
        }
    }

    func testMissAllReachesDefeatAndReplayResetsTheGame() {
        let rig = Rig(.missAll)
        rig.run(until: { rig.game.state.phase == .results })
        XCTAssertEqual(rig.game.state.lives, 0)
        XCTAssertFalse(rig.game.state.completed)
        XCTAssertEqual(rig.judgments.count, 5)
        XCTAssertEqual(rig.game.state.score, 0)
        XCTAssertEqual(rig.game.state.phase, .results)
        rig.game.start(demo: true, seed: 42)
        rig.controller = ScriptedSaber(.perfectRun)
        XCTAssertEqual(rig.game.state.lives, 5)
        XCTAssertEqual(rig.game.state.mistakes, 0)
        XCTAssertEqual(rig.game.state.elapsed, 0)
        rig.run(until: { rig.game.state.phase == .results })
        XCTAssertTrue(rig.game.state.completed)
        let score = rig.game.state.score
        // Replay via the production game entry point without replacing the controller.
        rig.game.start(demo: true, seed: 42)
        rig.run(until: { rig.game.state.phase == .results })
        XCTAssertTrue(rig.game.state.completed)
        XCTAssertEqual(rig.game.state.score, score)
    }

    func testFreshInputAfterASlowFrameDoesNotOpenThePauseScreenOrSkipTargets() {
        let rig = Rig(.perfectRun)
        rig.run(until: { rig.game.state.elapsed > 1 })
        let elapsed = rig.game.state.elapsed
        rig.step(0.45)
        XCTAssertEqual(rig.game.state.phase, .playing)
        XCTAssertGreaterThan(rig.game.state.elapsed, elapsed)
        XCTAssertLessThanOrEqual(rig.game.state.elapsed - elapsed, 0.10 + 0.00001)
        XCTAssertEqual(rig.game.state.mistakes, 0)
    }

    func testActualTrackingLossAndExplicitPauseStillFreezeGameTime() {
        let rig = Rig(.perfectRun)
        rig.run(until: { rig.game.state.elapsed > 1 })
        let elapsed = rig.game.state.elapsed
        rig.time += 1.05 // Sustained loss, not a brief Bluetooth gap.
        rig.game.tick()
        XCTAssertEqual(rig.game.state.phase, .paused)
        XCTAssertEqual(rig.game.state.elapsed, elapsed)
        rig.step()
        rig.game.resume()
        rig.run(until: { rig.game.state.phase == .playing })
        rig.game.pause("User paused")
        let paused = rig.game.state.elapsed
        for _ in 0..<100 { rig.step() }
        XCTAssertEqual(rig.game.state.elapsed, paused)
        XCTAssertEqual(rig.game.state.phase, .paused)
    }

    func testShortGapCannotCreateAConnectingSlashOrCatchUpGameTime() {
        let rig = Rig(.missAll)
        rig.run(until: { rig.game.state.elapsed > 1.55 })
        let target = rig.game.state.targets[0]
        let before = SaberPose(position: SIMD3(target.x - 0.7, -0.5, 0), orientation: ScriptedSaber.parked.orientation)
        let after = SaberPose(position: SIMD3(target.x + 0.7, -0.5, 0), orientation: before.orientation)
        rig.time += 0.02
        rig.game.update(pose: before, time: rig.time, ready: true)
        rig.game.tick()
        let elapsed = rig.game.state.elapsed
        rig.time += 0.27; rig.game.tick()
        XCTAssertTrue(rig.game.recoveringInput)
        XCTAssertEqual(rig.game.state.elapsed, elapsed)
        rig.time += 0.01
        rig.game.update(pose: after, time: rig.time, ready: true); rig.game.tick()
        XCTAssertFalse(rig.game.recoveringInput)
        XCTAssertEqual(rig.game.state.phase, .playing)
        XCTAssertEqual(rig.game.state.elapsed, elapsed)
        XCTAssertEqual(rig.game.state.cuts, 0, "Moving across the block while packets were missing is not a cut")
        rig.time += 0.02
        rig.game.update(pose: after, time: rig.time, ready: true); rig.game.tick()
        XCTAssertEqual(rig.game.state.cuts, 0)
        XCTAssertGreaterThan(rig.game.state.elapsed, elapsed)
    }

    func testCountdownGapRecoversButExplicitPauseNeverAutoResumes() {
        let rig = Rig(.perfectRun)
        let countdown = rig.game.state.countdown
        rig.time += 0.3; rig.game.tick()
        XCTAssertEqual(rig.game.state.phase, .countdown)
        XCTAssertEqual(rig.game.state.countdown, countdown)
        XCTAssertTrue(rig.game.recoveringInput)
        rig.step()
        XCTAssertEqual(rig.game.state.countdown, countdown)
        XCTAssertFalse(rig.game.recoveringInput)
        rig.game.pause("User paused")
        for _ in 0..<60 { rig.step() }
        XCTAssertEqual(rig.game.state.phase, .paused)
        XCTAssertEqual(rig.game.pauseReason, "User paused")
    }
}
