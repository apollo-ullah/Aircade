import Foundation
import MotionCore

@main struct TennisMatchCheck {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "TennisMatchCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() throws {
        let opponent = AutomaticReboundOpponent()
        var match = TennisMatch()
        match.start()
        match.advance(3, opponent: opponent)
        match.advance(0.25, opponent: opponent)
        try require(match.ball?.direction == .towardPlayer, "Automatic opponent did not serve")
        try require(match.ball?.bounce != nil, "Opponent serve did not bounce")

        match.advance(match.ball!.duration, opponent: opponent)
        try require(match.playerHit(speed: 2.2, horizontalDirection: 0.8) != nil, "Valid racket swing was rejected")
        try require(match.returns == 1 && match.rally == 1 && match.score > 100, "Return did not update rally score")

        let outgoing = match.ball!
        match.advance(outgoing.duration + 0.39, opponent: opponent)
        match.advance(0.42, opponent: opponent)
        try require(match.ball?.direction == .towardPlayer, "Opponent failed to rebound the valid shot")

        let beforePause = match.elapsed
        match.pause()
        match.advance(30, opponent: opponent)
        try require(match.elapsed == beforePause, "Paused tennis match advanced")

        var winner = TennisMatch()
        winner.start()
        winner.advance(3, opponent: opponent)
        winner.advance(0.25, opponent: opponent)
        winner.advance(winner.ball!.duration, opponent: opponent)
        try require(winner.playerHit(speed: 2, horizontalDirection: -10) != nil, "First sideline swing was rejected")
        let firstWideShot = winner.ball!
        try require(firstWideShot.to.x < -3, "First shot did not reach the left outer lane")
        winner.advance(firstWideShot.duration + 0.01, opponent: opponent)
        winner.advance(0.42, opponent: opponent)
        try require(winner.ball?.direction == .towardPlayer, "Opponent did not return the first sideline shot")
        winner.advance(winner.ball!.duration, opponent: opponent)

        try require(winner.playerHit(speed: 2, horizontalDirection: 10) != nil, "Opposite sideline swing was rejected")
        let wideShot = winner.ball!
        try require(wideShot.to.x > 3, "Opposite shot did not reach the right outer lane")
        let events = winner.advance(wideShot.duration + 0.01, opponent: opponent)
        let opponentMissed = events.contains { event in
            if case .opponentMiss(let ballX, let attemptedX, _) = event { return ballX > attemptedX }
            return false
        }
        try require(opponentMissed && winner.opponentMisses == 1, "Out-of-reach shot did not beat the opponent")

        var manual = TennisMatch()
        manual.start()
        manual.advance(3, opponent: opponent)
        manual.advance(0.25, opponent: opponent)
        manual.updateOpponentControl(positionX: 0, didSwing: false)
        manual.advance(manual.ball!.duration, opponent: opponent)
        try require(manual.playerHit(speed: 2, horizontalDirection: 0) != nil, "Manual-control setup swing was rejected")
        let manualShot = manual.ball!
        manual.advance(manualShot.duration - 0.2, opponent: opponent)
        manual.updateOpponentControl(positionX: 0, didSwing: true)
        let manualEvents = manual.advance(0.21, opponent: opponent)
        try require(manualEvents.contains { if case .opponentPreparing = $0 { return true }; return false }, "Aligned manual opponent swing did not return the ball")
        var practice = TennisMatch()
        practice.start()
        practice.assistedOpponent = true
        practice.updateOpponentControl(positionX: 0, didSwing: false)
        practice.advance(3, opponent: opponent)
        practice.advance(0.25, opponent: opponent)
        practice.advance(practice.ball!.duration, opponent: opponent)
        try require(practice.playerHit(speed: 2, horizontalDirection: 0) != nil, "Practice setup failed")
        practice.updateOpponentControl(positionX: 0, didSwing: true)
        let practiceEvents = practice.advance(practice.ball!.duration + 0.01, opponent: opponent)
        try require(practiceEvents.contains { if case .opponentPreparing = $0 { return true }; return false }, "Buffered practice swing did not return the moving ball")
        print("PASS: tennis serve, bounce, valid swing, scoring, reachable rebound, wide-shot miss, manual opponent, and pause invariants")
    }
}
