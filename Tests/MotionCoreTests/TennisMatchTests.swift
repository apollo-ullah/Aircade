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
        match.advance(match.ball!.duration, opponent: opponent)
        XCTAssertNotNil(match.playerHit(speed: 2, horizontalDirection: 1))
        XCTAssertEqual(match.returns, 1)
        XCTAssertGreaterThan(match.score, 100)
        let outgoing = match.ball!
        match.advance(outgoing.duration + 0.39, opponent: opponent)
        XCTAssertNil(match.ball)
        match.advance(0.42, opponent: opponent)
        XCTAssertEqual(match.ball?.direction, .towardPlayer)
        XCTAssertEqual(match.rally, 1)
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
