import Foundation
import simd

public enum TennisPhase: String, Equatable { case menu, countdown, playing, paused, results }
public enum TennisBallDirection: Equatable { case towardPlayer, towardOpponent }

public struct TennisBallFlight {
    public let born: Double
    public let duration: Double
    public let from: SIMD3<Float>
    public let to: SIMD3<Float>
    public let arcHeight: Float
    public let direction: TennisBallDirection
    public var arrival: Double { born + duration }

    public func position(at time: Double) -> SIMD3<Float> {
        let progress = Float(min(1, max(0, (time - born) / duration)))
        let linear = simd_mix(from, to, SIMD3<Float>(repeating: progress))
        return linear + SIMD3<Float>(0, sin(progress * .pi) * arcHeight, 0)
    }
}

public struct TennisOpponentReturn {
    public let targetX: Float
    public let flightDuration: Double
    public let delay: Double
    public init(targetX: Float, flightDuration: Double, delay: Double) {
        self.targetX = targetX
        self.flightDuration = flightDuration
        self.delay = delay
    }
}

/// Replace this strategy with a model-backed implementation later. The match owns
/// timing and validation; an opponent only chooses its next return.
public protocol TennisOpponentStrategy {
    func returnPlan(rally: Int, sequence: Int) -> TennisOpponentReturn
}

public struct AutomaticReboundOpponent: TennisOpponentStrategy {
    public init() {}
    public func returnPlan(rally: Int, sequence: Int) -> TennisOpponentReturn {
        let lanes: [Float] = [0, -0.72, 0.62, -0.36, 0.82, 0.28]
        let lane = lanes[sequence % lanes.count]
        return TennisOpponentReturn(targetX: lane,
                                    flightDuration: max(1.05, 1.55 - Double(min(rally, 10)) * 0.035),
                                    delay: 0.42)
    }
}

public enum TennisEvent {
    case opponentReturn
    case playerReturn(points: Int)
    case miss
    case finished
}

/// A one-minute rally challenge. The opponent returns every valid ball; the player
/// builds score by keeping the rally alive. This state is deterministic and has no
/// rendering or sensor dependencies.
public struct TennisMatch {
    public static let duration: Double = 60
    public static let startingBalls = 5
    public private(set) var phase: TennisPhase = .menu
    public private(set) var elapsed = 0.0
    public private(set) var countdown = 3.0
    public private(set) var ballsLeft = Self.startingBalls
    public private(set) var score = 0
    public private(set) var returns = 0
    public private(set) var rally = 0
    public private(set) var longestRally = 0
    public private(set) var misses = 0
    public private(set) var completed = false
    public private(set) var ball: TennisBallFlight?
    private var nextOpponentReturn: Double?
    private var sequence = 0

    public var remaining: Double { max(0, Self.duration - elapsed) }
    public var accuracy: Int {
        returns + misses == 0 ? 0 : Int((Double(returns) / Double(returns + misses) * 100).rounded())
    }
    public var rank: String {
        if !completed { return "KEEP SWINGING" }
        if longestRally >= 12 && accuracy >= 90 { return "S" }
        if longestRally >= 8 && accuracy >= 80 { return "A" }
        if longestRally >= 4 { return "B" }
        return "C"
    }

    public init() {}

    public mutating func start() {
        self = TennisMatch()
        phase = .countdown
    }

    public mutating func pause() {
        guard phase == .playing || phase == .countdown else { return }
        phase = .paused
    }

    public mutating func resume() {
        guard phase == .paused else { return }
        phase = .countdown
        countdown = 2
    }

    public mutating func quit() { self = TennisMatch() }

    @discardableResult
    public mutating func advance(_ delta: Double, opponent: any TennisOpponentStrategy) -> [TennisEvent] {
        guard delta.isFinite, delta > 0 else { return [] }
        if phase == .countdown {
            countdown = max(0, countdown - delta)
            if countdown == 0 {
                phase = .playing
                scheduleOpponentReturn(after: 0.25)
            }
            return []
        }
        guard phase == .playing else { return [] }
        elapsed = min(Self.duration, elapsed + delta)
        var events: [TennisEvent] = []

        if let flight = ball,
           (flight.direction == .towardOpponent ? elapsed >= flight.arrival : elapsed > flight.arrival + 0.38) {
            if flight.direction == .towardPlayer {
                ball = nil
                ballsLeft = max(0, ballsLeft - 1)
                misses += 1
                rally = 0
                events.append(.miss)
                scheduleOpponentReturn(after: 0.9)
            } else {
                ball = nil
                let plan = opponent.returnPlan(rally: rally, sequence: sequence)
                nextOpponentReturn = elapsed + plan.delay
            }
        }

        if let launchTime = nextOpponentReturn, elapsed >= launchTime, ball == nil {
            nextOpponentReturn = nil
            let plan = opponent.returnPlan(rally: rally, sequence: sequence)
            sequence += 1
            ball = TennisBallFlight(born: elapsed, duration: plan.flightDuration,
                                    from: SIMD3<Float>(0, 0.05, -10.5),
                                    to: SIMD3<Float>(plan.targetX, -0.1, 0),
                                    arcHeight: 2.15, direction: .towardPlayer)
            events.append(.opponentReturn)
        }

        if ballsLeft == 0 || elapsed >= Self.duration {
            completed = elapsed >= Self.duration
            phase = .results
            ball = nil
            nextOpponentReturn = nil
            events.append(.finished)
        }
        return events
    }

    /// Returns nil unless the incoming ball is inside its strike window.
    @discardableResult
    public mutating func playerHit(speed: Float, horizontalDirection: Float) -> TennisEvent? {
        guard phase == .playing, let incoming = ball, incoming.direction == .towardPlayer else { return nil }
        guard elapsed >= incoming.arrival - 0.32, elapsed <= incoming.arrival + 0.38, speed >= 0.75 else { return nil }
        let contact = incoming.position(at: elapsed)
        rally += 1
        returns += 1
        longestRally = max(longestRally, rally)
        let points = 100 + min(250, rally * 15) + min(150, Int(speed * 28))
        score += points
        let aim = max(-1.1, min(1.1, horizontalDirection * 0.34))
        ball = TennisBallFlight(born: elapsed, duration: max(0.9, 1.3 - Double(min(speed, 4)) * 0.06),
                                from: contact, to: SIMD3<Float>(aim, 0.05, -10.5),
                                arcHeight: 1.8, direction: .towardOpponent)
        return .playerReturn(points: points)
    }

    private mutating func scheduleOpponentReturn(after delay: Double) {
        nextOpponentReturn = elapsed + delay
    }
}
