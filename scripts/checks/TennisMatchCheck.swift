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
        print("PASS: tennis serve, valid swing, scoring, automatic rebound, and pause invariants")
    }
}
