import XCTest
import simd
@testable import MotionCore

final class NeonRushTests: XCTestCase {
    func started(_ difficulty: RushDifficulty = .arcade) -> NeonRush {
        var game = NeonRush()
        game.start(difficulty: difficulty)
        game.advance(3)
        return game
    }
    func velocity(for direction: CutDirection) -> SIMD3<Float> {
        switch direction {
        case .left: return SIMD3(-2, 0, 0)
        case .right, .any: return SIMD3(2, 0, 0)
        case .down: return SIMD3(0, -2, 0)
        }
    }
    @discardableResult
    func hit(_ target: RushTarget, in game: inout NeonRush) -> RushJudgment? {
        game.contact(id: target.id, velocity: velocity(for: target.direction), speed: 2, alignment: 1)
    }
    func arriveFirst(in game: inout NeonRush) -> RushTarget {
        game.advance(0.02)
        let target = game.targets[0]
        game.advance(target.travel)
        return target
    }
    func testCountdownPauseAndResumeFreezeDeadlines() {
        var game = NeonRush()
        game.start(difficulty: .chill)
        XCTAssertEqual(game.lives, 7)
        game.advance(2)
        XCTAssertEqual(game.phase, .countdown)
        XCTAssertEqual(game.elapsed, 0)
        game.advance(1)
        game.advance(0.5)
        let target = game.targets[0], elapsed = game.elapsed
        game.pause()
        game.advance(120)
        XCTAssertEqual(game.elapsed, elapsed)
        XCTAssertEqual(game.targets[0].deadline, target.deadline)
        game.resume()
        game.advance(1.99)
        XCTAssertEqual(game.phase, .countdown)
        XCTAssertEqual(game.elapsed, elapsed)
        game.advance(0.02)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.lives, 7)
    }
    func testEarlySlowAndGlancingContactsDoNotScoreAndCutIsOnlyOnce() {
        var game = started()
        game.advance(0.02)
        let target = game.targets[0]
        XCTAssertNil(hit(target, in: &game))
        game.advance(target.travel)
        XCTAssertNil(game.contact(id: target.id, velocity: .zero, speed: 0, alignment: 1))
        XCTAssertNil(game.contact(id: target.id, velocity: SIMD3(0, 3, 0), speed: 3, alignment: 0.1))
        XCTAssertEqual(hit(target, in: &game)?.kind, .perfect)
        XCTAssertEqual(game.score, 150)
        XCTAssertEqual(game.combo, 1)
        XCTAssertNil(hit(target, in: &game))
        XCTAssertEqual(game.score, 150)
    }
    func testMissCostsEnergyAndResetsCombo() {
        var game = started()
        let target = arriveFirst(in: &game)
        hit(target, in: &game)
        game.advance(0.1)
        let next = game.targets[0]
        let judgments = game.advance(next.deadline - game.elapsed + 0.01)
        XCTAssertEqual(judgments.first?.kind, .miss)
        XCTAssertEqual(game.lives, 4)
        XCTAssertEqual(game.combo, 0)
        XCTAssertEqual(game.bestCombo, 1)
        XCTAssertEqual(game.accuracy, 50)
    }
    func testWrongArrowConsumesTargetAndLife() {
        var game = started()
        var checked = false
        for _ in 0..<2000 {
            game.advance(0.02)
            for target in game.targets where !target.hazard && game.elapsed >= target.arrival {
                if target.direction != .any {
                    let priorLives = game.lives
                    let result = game.contact(id: target.id, velocity: -velocity(for: target.direction), speed: 2, alignment: 1)
                    XCTAssertEqual(result?.kind, .wrongDirection)
                    XCTAssertEqual(game.lives, priorLives - 1)
                    XCTAssertEqual(game.combo, 0)
                    XCTAssertFalse(game.targets.contains { $0.id == target.id })
                    checked = true
                    break
                }
                hit(target, in: &game)
            }
            if checked { break }
        }
        XCTAssertTrue(checked, "Arcade must introduce directional cuts in round two")
    }
    func testHazardEvenWithStationaryBladeCostsLife() {
        var game = started()
        var checked = false
        for _ in 0..<1500 {
            game.advance(0.02)
            for target in game.targets where game.elapsed >= target.arrival {
                if target.hazard {
                    let priorLives = game.lives
                    XCTAssertEqual(game.contact(id: target.id, velocity: .zero, speed: 0, alignment: 0)?.kind, .hazard)
                    XCTAssertEqual(game.lives, priorLives - 1)
                    checked = true
                    break
                }
                hit(target, in: &game)
            }
            if checked { break }
        }
        XCTAssertTrue(checked)
    }
    func testFullRunAvoidsHazardsAndBuildsMultiplierThenReplayResets() {
        for difficulty in RushDifficulty.allCases {
            var game = started(difficulty)
            var expectedScore = 0
            var rounds: Set<Int> = []
            var sawHazard = false
            for _ in 0..<3100 {
                let events = game.advance(0.02)
                XCTAssertTrue(events.isEmpty, "Avoided hazards must expire without penalty")
                rounds.insert(game.round)
                sawHazard = sawHazard || game.targets.contains { $0.hazard }
                for target in game.targets where !target.hazard && game.elapsed >= target.arrival {
                    expectedScore += 150 * min(4, 1 + game.cuts / 5)
                    hit(target, in: &game)
                }
                if game.phase == .results { break }
            }
            XCTAssertEqual(game.phase, .results)
            XCTAssertTrue(game.completed)
            XCTAssertTrue(sawHazard)
            XCTAssertEqual(rounds, [1, 2, 3])
            XCTAssertEqual(game.lives, difficulty.lives)
            XCTAssertEqual(game.score, expectedScore)
            XCTAssertEqual(game.multiplier, 4)
            XCTAssertEqual(game.accuracy, 100)
            XCTAssertEqual(game.rank, "S")
            XCTAssertEqual(game.remaining, 0)
            game.start(difficulty: difficulty)
            XCTAssertEqual(game.score, 0)
            XCTAssertEqual(game.cuts, 0)
            XCTAssertEqual(game.combo, 0)
            XCTAssertFalse(game.completed)
            XCTAssertTrue(game.targets.isEmpty)
            XCTAssertEqual(game.elapsed, 0)
        }
    }
    func testUnplayedRunEndsAtZeroEnergyAndStopsClock() {
        var game = started()
        for _ in 0..<2000 {
            game.advance(0.02)
            if game.phase == .results { break }
        }
        XCTAssertEqual(game.phase, .results)
        XCTAssertEqual(game.lives, 0)
        XCTAssertEqual(game.mistakes, 5)
        XCTAssertFalse(game.completed)
        XCTAssertTrue(game.targets.isEmpty)
        let elapsed = game.elapsed
        game.advance(60)
        XCTAssertEqual(game.elapsed, elapsed)
        game.quit()
        XCTAssertEqual(game.phase, .menu)
    }
    func testSameSeedProducesSameTargetsAndInvalidTimeDoesNothing() {
        var a = started(), b = started()
        a.advance(.nan); a.advance(-1); a.advance(.infinity)
        XCTAssertEqual(a.elapsed, 0)
        for _ in 0..<400 {
            a.advance(0.02); b.advance(0.02)
            XCTAssertEqual(a.targets.map { $0.x }, b.targets.map { $0.x })
            XCTAssertEqual(a.targets.map { $0.direction }, b.targets.map { $0.direction })
        }
    }
}
