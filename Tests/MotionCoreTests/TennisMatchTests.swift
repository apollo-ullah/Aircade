import XCTest
@testable import MotionCore

final class TennisMatchTests: XCTestCase {
    let opponent = AutomaticReboundOpponent()

    func started() -> TennisMatch {
        var match = TennisMatch()
        match.start()
        match.advance(3, opponent: opponent)
        match.advance(0.25, opponent: opponent)
        return match
    }

    func testAutomaticOpponentLaunchesAndReturnsEveryValidShot() {
        var match = started()
        XCTAssertEqual(match.ball?.direction, .towardPlayer)
        XCTAssertGreaterThan(match.ball!.duration, 2)
        XCTAssertNotNil(match.ball!.bounce)
        XCTAssertEqual(match.ball!.position(at: match.ball!.bounceTime!), match.ball!.bounce!)
        match.advance(match.ball!.duration, opponent: opponent)
        XCTAssertNotNil(match.playerHit(speed: 2, horizontalDirection: 1))
        XCTAssertEqual(match.returns, 1)
        XCTAssertGreaterThan(match.score, 100)
        let outgoing = match.ball!
        XCTAssertNotNil(outgoing.bounce)
        XCTAssertEqual(outgoing.position(at: outgoing.bounceTime!), outgoing.bounce!)
        match.advance(outgoing.duration + 0.39, opponent: opponent)
        XCTAssertNil(match.ball)
        match.advance(0.42, opponent: opponent)
        XCTAssertEqual(match.ball?.direction, .towardPlayer)
        XCTAssertEqual(match.rally, 1)
    }

    func testOpponentDecisionIsReusedBetweenPreparationAndContact() {
        final class CountingOpponent: TennisOpponentStrategy {
            var calls = 0
            func returnPlan(rally: Int, sequence: Int) -> TennisOpponentReturn {
                calls += 1
                return TennisOpponentReturn(targetX: 0.6, flightDuration: 1.2, delay: 0.3, stroke: .forehand)
            }
        }
        let counting = CountingOpponent()
        var match = TennisMatch()
        match.start()
        match.advance(3, opponent: counting)
        match.advance(0.25, opponent: counting)
        XCTAssertEqual(counting.calls, 1) // opening serve
        match.advance(match.ball!.duration, opponent: counting)
        XCTAssertNotNil(match.playerHit(speed: 2, horizontalDirection: -1))
        match.advance(match.ball!.duration + 0.01, opponent: counting)
        XCTAssertEqual(counting.calls, 2)
        match.advance(0.3, opponent: counting)
        XCTAssertEqual(counting.calls, 2)
        XCTAssertEqual(match.ball?.direction, .towardPlayer)
    }

    func testWidePlayerShotCanBeatOpponentReach() {
        var match = started()
        match.advance(match.ball!.duration, opponent: opponent)
        XCTAssertNotNil(match.playerHit(speed: 2, horizontalDirection: -10))
        let firstWideShot = match.ball!
        XCTAssertEqual(firstWideShot.to.x, -4.6, accuracy: 0.001)
        match.advance(firstWideShot.duration + 0.01, opponent: opponent)
        match.advance(0.42, opponent: opponent)
        XCTAssertEqual(match.ball?.direction, .towardPlayer)
        match.advance(match.ball!.duration, opponent: opponent)

        XCTAssertNotNil(match.playerHit(speed: 2, horizontalDirection: 10))
        let outgoing = match.ball!
        XCTAssertEqual(outgoing.to.x, 4.6, accuracy: 0.001)
        let events = match.advance(outgoing.duration + 0.01, opponent: opponent)
        XCTAssertTrue(events.contains { event in
            if case .opponentMiss(let ballX, let attemptedX, let points) = event {
                return ballX > attemptedX && points == 300
            }
            return false
        })
        XCTAssertEqual(match.opponentMisses, 1)
        XCTAssertNil(match.ball)
        XCTAssertGreaterThanOrEqual(match.score, 400)
    }

    func testEarlyOrSlowSwingDoesNotReturnBallAndMissCostsABall() {
        var match = started()
        XCTAssertNil(match.playerHit(speed: 3, horizontalDirection: 0))
        match.advance(match.ball!.duration, opponent: opponent)
        XCTAssertNil(match.playerHit(speed: 0.2, horizontalDirection: 0))
        match.advance(0.39, opponent: opponent)
        XCTAssertEqual(match.misses, 1)
        XCTAssertEqual(match.ballsLeft, TennisMatch.startingBalls - 1)
        XCTAssertEqual(match.rally, 0)
    }

    func testPauseFreezesBallAndResumeUsesCountdown() {
        var match = started()
        let elapsed = match.elapsed
        let position = match.ball!.position(at: elapsed)
        match.pause()
        match.advance(20, opponent: opponent)
        XCTAssertEqual(match.elapsed, elapsed)
        XCTAssertEqual(match.ball!.position(at: match.elapsed), position)
        match.resume()
        match.advance(1.99, opponent: opponent)
        XCTAssertEqual(match.phase, .countdown)
        match.advance(0.02, opponent: opponent)
        XCTAssertEqual(match.phase, .playing)
    }

    func testFiveMissesEndRunAndRestartResetsState() {
        var match = started()
        for _ in 0..<TennisMatch.startingBalls {
            let flight = match.ball!
            match.advance(flight.duration + 0.39, opponent: opponent)
            if match.phase == .results { break }
            match.advance(0.9, opponent: opponent)
        }
        XCTAssertEqual(match.phase, .results)
        XCTAssertEqual(match.ballsLeft, 0)
        XCTAssertFalse(match.completed)
        match.start()
        XCTAssertEqual(match.ballsLeft, TennisMatch.startingBalls)
        XCTAssertEqual(match.score, 0)
        XCTAssertEqual(match.phase, .countdown)
    }
}
