import XCTest
import simd
import MotionCore
@testable import Aircade

/// These checks submit controller poses through TennisGame.update; they never call
/// TennisMatch.playerHit or mutate a score. Each rig owns its clock and score store.
final class TennisIntegrationTests: XCTestCase {
    func testNormalRallyRemainsRankableAndPracticeIsOptIn() {
        let rig = Rig(demo: false)
        XCTAssertFalse(rig.game.codexPractice)
        XCTAssertFalse(rig.game.manualOpponentEnabled)
        XCTAssertFalse(rig.game.state.assistedOpponent)
        XCTAssertFalse(rig.game.isDemo)
        XCTAssertEqual(rig.starts, [false])

        rig.game.leave()
        rig.game.codexPractice = true
        rig.game.update(pose: rig.parked, time: rig.clock.time, ready: true)
        rig.game.start(demo: false)
        XCTAssertTrue(rig.game.manualOpponentEnabled)
        XCTAssertTrue(rig.game.state.assistedOpponent)
        XCTAssertTrue(rig.game.isDemo)
        XCTAssertEqual(rig.starts, [false, true])
    }

    final class Clock { var time = 100.0 }

    final class Rig {
        let clock = Clock()
        let defaults: UserDefaults
        let suite = "com.aircade.tennis-tests.\(UUID().uuidString)"
        let game: TennisGame
        var starts: [Bool] = []
        var finishes: [(state: TennisMatch, demo: Bool, id: String?)] = []
        var abandoned: [String?] = []
        var returnIDs: [Int] = []
        var permitLocalBest = true
        let hilt = SIMD3<Float>(0, -0.5, 0)
        var parked: SaberPose {
            SaberPose(position: hilt, orientation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)))
        }

        init(demo: Bool = true) {
            defaults = UserDefaults(suiteName: suite)!
            let clock = self.clock
            game = TennisGame(scene: SaberScene(), automaticTimer: false, clock: { clock.time }, scoreDefaults: defaults)
            game.enabled = true
            game.sound = false
            game.onRunStarted = { [weak self] demo in
                guard let self else { return nil }
                self.starts.append(demo)
                return "tennis-run-\(self.starts.count)"
            }
            game.onRunFinished = { [weak self] state, demo, id in
                guard let self else { return false }
                self.finishes.append((state, demo, id))
                return self.permitLocalBest
            }
            game.onRunAbandoned = { [weak self] in self?.abandoned.append($0) }
            game.onJudgment = { [weak self] event in
                guard let self else { return }
                if case .playerReturn = event, let id = self.game.state.ball?.id { self.returnIDs.append(id) }
            }
            game.update(pose: parked, time: clock.time, ready: true)
            game.start(demo: demo)
        }

        deinit { defaults.removePersistentDomain(forName: suite) }

        func step(_ dt: Double = 1.0 / 60, pose: SaberPose? = nil) {
            clock.time += dt
            game.update(pose: pose ?? parked, time: clock.time, ready: true)
            game.tick()
        }

        func run(dt: Double = 1.0 / 60, returning: Bool = false, until predicate: () -> Bool) {
            for _ in 0..<Int(80 / dt) {
                if predicate() || game.state.phase == .results || game.state.phase == .paused { return }
                step(dt, pose: returning ? returnPose(dt: dt) : nil)
            }
        }

        /// An orientation-only backswing then forward stroke at a fixed hilt. The
        /// upcoming ball's position is only used by this deterministic test driver.
        func returnPose(dt: Double) -> SaberPose {
            guard let ball = game.state.ball, ball.direction == .towardPlayer else { return parked }
            let contactTime = ball.arrival - 0.14
            let target = simd_quatf(from: SIMD3<Float>(0, 1, 0),
                                   to: simd_normalize(ball.position(at: contactTime) - hilt))
            let q = game.state.elapsed < contactTime
                ? simd_quatf(angle: Float(4.8 * dt), axis: SIMD3<Float>(1, 0, 0)) * target : target
            return SaberPose(position: hilt, orientation: q)
        }

        /// Face translation isolates angle/strength response from the orientation-only
        /// full-run driver. Both still pass through the production swept-face collision.
        func firstReturn(yaw: Float, speed: Float, dt: Double = 1.0 / 60) -> TennisBallFlight? {
            run(dt: dt, until: { self.game.state.ball != nil })
            guard let incoming = game.state.ball else { return nil }
            let contactTime = incoming.arrival - 0.14
            let q = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let start = incoming.position(at: contactTime) - q.act(RacketDimensions.faceCenter) + SIMD3<Float>(0, 0, 0.02)
            var swung = false
            for _ in 0..<180 {
                let shouldSwing = game.state.elapsed >= contactTime
                let offset = shouldSwing ? SIMD3<Float>(0, 0, -speed * Float(dt)) : .zero
                step(dt, pose: SaberPose(position: start + offset, orientation: q))
                if game.state.ball?.direction == .towardOpponent { return game.state.ball }
                if shouldSwing && swung { return nil }
                swung = shouldSwing
            }
            return nil
        }
    }

    func testFullMinuteRalliesAt30And60HzUsingOnlyControllerPoses() {
        for dt in [1.0 / 30, 1.0 / 60] {
            let rig = Rig()
            rig.run(dt: dt, returning: true, until: { rig.game.state.phase == .results })
            XCTAssertEqual(rig.game.state.phase, .results)
            XCTAssertTrue(rig.game.state.completed, "Frame interval \(dt), misses \(rig.game.state.misses)")
            XCTAssertEqual(rig.game.state.elapsed, TennisMatch.duration)
            XCTAssertEqual(rig.game.state.ballsLeft, TennisMatch.startingBalls)
            XCTAssertEqual(rig.game.state.misses, 0)
            XCTAssertGreaterThanOrEqual(rig.game.state.returns, 10)
            XCTAssertEqual(rig.game.state.longestRally, rig.game.state.returns)
            XCTAssertEqual(rig.game.state.accuracy, 100)
            XCTAssertEqual(rig.game.state.rank, "S")
            XCTAssertEqual(rig.returnIDs.count, rig.game.state.returns)
            XCTAssertEqual(Set(rig.returnIDs).count, rig.returnIDs.count, "Each incoming ball scores once.")
            XCTAssertEqual(rig.finishes.count, 1)
            XCTAssertEqual(rig.finishes.first?.id, "tennis-run-1")
            XCTAssertEqual(rig.defaults.integer(forKey: "tennis.best"), 0)
            XCTAssertFalse(rig.game.newRecord)
        }
    }

    func testFiveMissesFinishAndReplayClearsStateAndCanComplete() {
        let rig = Rig()
        rig.run(until: { rig.game.state.phase == .results })
        XCTAssertEqual(rig.game.state.phase, .results)
        XCTAssertFalse(rig.game.state.completed)
        XCTAssertEqual(rig.game.state.misses, 5)
        XCTAssertEqual(rig.game.state.ballsLeft, 0)
        XCTAssertEqual(rig.game.state.score, 0)
        XCTAssertEqual(rig.finishes.count, 1)
        rig.game.start(demo: true)
        XCTAssertEqual(rig.game.state.phase, .countdown)
        XCTAssertEqual(rig.game.state.elapsed, 0)
        XCTAssertEqual(rig.game.state.misses, 0)
        XCTAssertEqual(rig.game.state.ballsLeft, 5)
        XCTAssertNil(rig.game.state.ball)
        rig.run(returning: true, until: { rig.game.state.phase == .results })
        XCTAssertTrue(rig.game.state.completed)
        XCTAssertEqual(rig.finishes.count, 2)
        XCTAssertEqual(rig.finishes.last?.id, "tennis-run-2")
    }

    func testStationaryFaceAndMovingShaftCannotScore() {
        for useShaft in [false, true] {
            let rig = Rig()
            rig.run(until: { rig.game.state.ball != nil })
            let incoming = rig.game.state.ball!
            let target = incoming.position(at: incoming.arrival - 0.14)
            let q = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            let baseline = target - SIMD3<Float>(0, useShaft ? 0.2 : RacketDimensions.faceCenter.y, 0)
            for frame in 0..<260 {
                if rig.game.state.misses > 0 { break }
                let z: Float = useShaft && rig.game.state.elapsed >= incoming.arrival - 0.25
                    ? Float(frame % 2 == 0 ? 0.15 : -0.15) : 0
                rig.step(pose: SaberPose(position: baseline + SIMD3<Float>(0, 0, z), orientation: q))
            }
            XCTAssertEqual(rig.game.state.returns, 0, useShaft ? "Shaft-only movement" : "Stationary face")
            XCTAssertEqual(rig.game.state.misses, 1)
            XCTAssertEqual(rig.game.state.score, 0)
            XCTAssertEqual(rig.game.state.phase, .playing)
        }
    }

    func testActualOutgoingShotChangesWithFaceAngleAndStrength() throws {
        let left = try XCTUnwrap(Rig().firstReturn(yaw: .pi / 6, speed: 2))
        let right = try XCTUnwrap(Rig().firstReturn(yaw: -.pi / 6, speed: 2))
        let gentle = try XCTUnwrap(Rig().firstReturn(yaw: 0, speed: 0.8))
        let strong = try XCTUnwrap(Rig().firstReturn(yaw: 0, speed: 6.5))
        XCTAssertLessThan(left.to.x, -0.6)
        XCTAssertGreaterThan(right.to.x, 0.6)
        XCTAssertEqual(gentle.to.x, 0, accuracy: 0.001)
        XCTAssertGreaterThan(gentle.duration - strong.duration, 0.4)
        XCTAssertEqual(gentle.direction, .towardOpponent)
        XCTAssertEqual(strong.direction, .towardOpponent)
    }

    func testRepeatedContactCannotScoreSameBallTwice() throws {
        let rig = Rig()
        let outgoing = try XCTUnwrap(rig.firstReturn(yaw: 0, speed: 2))
        let score = rig.game.state.score
        for frame in 0..<30 {
            let center = outgoing.position(at: rig.game.state.elapsed)
            let pose = SaberPose(position: center - RacketDimensions.faceCenter + SIMD3<Float>(0, 0, frame % 2 == 0 ? 0.03 : -0.03),
                                  orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)))
            rig.step(pose: pose)
        }
        XCTAssertEqual(rig.game.state.returns, 1)
        XCTAssertEqual(rig.game.state.score, score)
        XCTAssertEqual(rig.returnIDs, [outgoing.id])
    }

    func testShortGapsFreezeTimeAndClearConnectingSwingWithoutPausing() throws {
        for gap in [0, 0.28, 0.280104, 0.65] {
            let rig = Rig()
            rig.run(until: { rig.game.state.ball != nil })
            let flight = try XCTUnwrap(rig.game.state.ball)
            let strikeTime = flight.arrival - 0.14
            let target = simd_quatf(from: SIMD3<Float>(0, 1, 0),
                to: simd_normalize(flight.position(at: strikeTime) - rig.hilt))
            let before = SaberPose(position: rig.hilt, orientation: simd_quatf(angle: 0.08, axis: SIMD3<Float>(1, 0, 0)) * target)
            for _ in 0..<260 {
                if rig.game.state.elapsed >= strikeTime { break }
                rig.step(pose: before)
            }
            let elapsed = rig.game.state.elapsed
            XCTAssertEqual(rig.game.state.returns, 0, "The stationary backswing must not score before the gap.")
            let after = SaberPose(position: rig.hilt, orientation: target)
            if gap == 0 {
                rig.step(pose: after)
                XCTAssertEqual(rig.game.state.returns, 1, "Positive control: this exact stroke must hit without a gap.")
                continue
            }
            rig.clock.time += gap
            rig.game.tick()
            XCTAssertEqual(rig.game.state.phase, .playing)
            XCTAssertTrue(rig.game.recoveringInput)
            XCTAssertEqual(rig.game.state.elapsed, elapsed)
            rig.step(pose: after)
            XCTAssertFalse(rig.game.recoveringInput)
            XCTAssertEqual(rig.game.state.elapsed, elapsed)
            XCTAssertEqual(rig.game.state.returns, 0, "No swing may connect across a packet gap.")
            rig.step(pose: after)
            XCTAssertEqual(rig.game.state.returns, 0)
            XCTAssertGreaterThan(rig.game.state.elapsed, elapsed)
        }
    }

    func testCountdownGapFreezesCountdownAndManualPauseNeverAutoResumes() {
        let rig = Rig()
        let countdown = rig.game.state.countdown
        rig.clock.time += 0.32
        rig.game.tick()
        XCTAssertEqual(rig.game.state.phase, .countdown)
        XCTAssertEqual(rig.game.state.countdown, countdown)
        XCTAssertTrue(rig.game.recoveringInput)
        rig.step()
        XCTAssertEqual(rig.game.state.countdown, countdown)
        XCTAssertFalse(rig.game.recoveringInput)
        rig.game.pause("User paused")
        for _ in 0..<10 { rig.step() }
        XCTAssertEqual(rig.game.state.phase, .paused)
        XCTAssertEqual(rig.game.pauseReason, "User paused")
    }

    func testSustainedLossPausesAndRequiresExplicitResumeWithoutReplacingBall() throws {
        let rig = Rig()
        rig.run(until: { rig.game.state.ball != nil })
        let ball = try XCTUnwrap(rig.game.state.ball)
        let elapsed = rig.game.state.elapsed
        rig.clock.time += 1.05
        rig.game.tick()
        XCTAssertEqual(rig.game.state.phase, .paused)
        XCTAssertEqual(rig.game.state.elapsed, elapsed)
        XCTAssertTrue(rig.game.pauseReason.contains("1 second"))
        for _ in 0..<3 { rig.step() }
        XCTAssertEqual(rig.game.state.phase, .paused)
        rig.game.resume()
        XCTAssertEqual(rig.game.state.phase, .countdown)
        rig.run(until: { rig.game.state.phase == .playing })
        XCTAssertEqual(rig.game.state.ball?.id, ball.id)
        XCTAssertEqual(rig.game.state.ball?.born, ball.born)
        XCTAssertEqual(rig.game.state.elapsed, elapsed)
        rig.step()
        XCTAssertGreaterThan(rig.game.state.elapsed, elapsed)
    }

    func testResultsCallbackAndLocalBestHonorRunProvenanceExactlyOnce() {
        for scenario in 0..<4 {
            let demoAtStart = scenario == 1
            let rig = Rig(demo: demoAtStart)
            rig.permitLocalBest = scenario != 3
            rig.run(returning: true, until: { rig.game.state.returns >= 1 })
            if scenario == 2 {
                rig.game.observeSimulatedInput(true)
                rig.game.observeSimulatedInput(false) // Returning to real input cannot restore eligibility.
            }
            rig.run(returning: true, until: { rig.game.state.phase == .results })
            let demoAtFinish = scenario == 1 || scenario == 2
            XCTAssertEqual(rig.starts, [demoAtStart])
            XCTAssertEqual(rig.finishes.count, 1)
            XCTAssertEqual(rig.finishes.first?.demo, demoAtFinish)
            XCTAssertEqual(rig.finishes.first?.id, "tennis-run-1")
            XCTAssertEqual(rig.finishes.first?.state.score, rig.game.state.score)
            XCTAssertGreaterThan(rig.game.state.score, 0)
            let saved = scenario == 0 ? rig.game.state.score : 0
            XCTAssertEqual(rig.defaults.integer(forKey: "tennis.best"), saved)
            XCTAssertEqual(rig.game.bestScore, saved)
            XCTAssertEqual(rig.game.newRecord, scenario == 0)
            for _ in 0..<10 { rig.step() }
            XCTAssertEqual(rig.finishes.count, 1)
        }
    }

    func testAbandonedRunNeverFinishesAndReplayGetsNewIdentity() {
        let rig = Rig(demo: false)
        rig.run(returning: true, until: { rig.game.state.returns > 0 })
        rig.game.leave()
        XCTAssertEqual(rig.game.state.phase, .menu)
        XCTAssertNil(rig.game.runID)
        XCTAssertEqual(rig.abandoned.compactMap { $0 }, ["tennis-run-1"])
        XCTAssertTrue(rig.finishes.isEmpty)
        XCTAssertEqual(rig.defaults.integer(forKey: "tennis.best"), 0)
        rig.step()
        rig.game.start(demo: true)
        XCTAssertEqual(rig.game.runID, "tennis-run-2")
        XCTAssertEqual(rig.game.state.score, 0)
    }
}
