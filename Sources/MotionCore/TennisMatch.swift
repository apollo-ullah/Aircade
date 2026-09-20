import Foundation
import simd

public enum TennisPhase: String, Equatable { case menu, countdown, playing, paused, results }
public enum TennisBallDirection: Equatable { case towardPlayer, towardOpponent }
public enum TennisStroke: String, Equatable { case forehand, backhand }

public struct TennisBallFlight {
    public let id: Int
    public let born: Double
    public let duration: Double
    public let from: SIMD3<Float>
    public let to: SIMD3<Float>
    public let arcHeight: Float
    public let direction: TennisBallDirection
    public let bounce: SIMD3<Float>?
    public let bounceProgress: Float
    public let defenderContactX: Float?
    public var arrival: Double { born + duration }
    public var bounceTime: Double? { bounce.map { _ in born + duration * Double(bounceProgress) } }

    public init(id: Int = 0, born: Double, duration: Double, from: SIMD3<Float>, to: SIMD3<Float>,
                arcHeight: Float, direction: TennisBallDirection, bounce: SIMD3<Float>? = nil,
                bounceProgress: Float = 0.5, defenderContactX: Float? = nil) {
        self.id = id; self.born = born; self.duration = duration
        self.from = from; self.to = to; self.arcHeight = arcHeight; self.direction = direction
        self.bounce = bounce; self.bounceProgress = bounceProgress; self.defenderContactX = defenderContactX
    }

    public func position(at time: Double) -> SIMD3<Float> {
        let progress = Float(min(1, max(0, (time - born) / duration)))
        guard let bounce else {
            let linear = simd_mix(from, to, SIMD3<Float>(repeating: progress))
            return linear + SIMD3<Float>(0, sin(progress * .pi) * arcHeight, 0)
        }
        if progress <= bounceProgress {
            let leg = progress / bounceProgress
            let linear = simd_mix(from, bounce, SIMD3<Float>(repeating: leg))
            return linear + SIMD3<Float>(0, sin(leg * .pi) * arcHeight, 0)
        }
        let leg = (progress - bounceProgress) / (1 - bounceProgress)
        let linear = simd_mix(bounce, to, SIMD3<Float>(repeating: leg))
        return linear + SIMD3<Float>(0, sin(leg * .pi) * arcHeight * 0.62, 0)
    }
}

public struct TennisOpponentReturn {
    public let targetX: Float
    public let flightDuration: Double
    public let delay: Double
    public let stroke: TennisStroke
    public init(targetX: Float, flightDuration: Double, delay: Double, stroke: TennisStroke = .forehand) {
        self.targetX = targetX
        self.flightDuration = flightDuration
        self.delay = delay
        self.stroke = stroke
    }

    /// Strategy output is a suggestion, never permission to put NaN or an
    /// impossible flight into the deterministic match.
    public func validated(fallback: TennisOpponentReturn) -> TennisOpponentReturn {
        guard targetX.isFinite, flightDuration.isFinite, delay.isFinite else { return fallback }
        // Automatic court coverage makes the full legal shot lanes reachable.
        return TennisOpponentReturn(targetX: min(3.5, max(-3.5, targetX)),
                                    flightDuration: min(4, max(0.85, flightDuration)),
                                    delay: min(0.8, max(0.18, delay)), stroke: stroke)
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
                                    flightDuration: max(2.35, 2.9 - Double(min(rally, 10)) * 0.04),
                                    delay: 0.42,
                                    stroke: sequence.isMultiple(of: 2) ? .forehand : .backhand)
    }
}

public enum TennisEvent {
    case opponentPreparing(contactX: Float, stroke: TennisStroke, delay: Double)
    case opponentReturn(contactX: Float, stroke: TennisStroke)
    case playerReturn(points: Int)
    case opponentMiss(ballX: Float, attemptedX: Float, points: Int)
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
    public private(set) var opponentMisses = 0
    public private(set) var completed = false
    public private(set) var ball: TennisBallFlight?
    private var nextOpponentReturn: Double?
    private var pendingPlan: TennisOpponentReturn?
    private var opponentContactX: Float = 0
    public var assistedOpponent = false
    private var manualOpponentX: Float?
    private var manualOpponentSwingAt: Double?
    private var sequence = 0

    public var remaining: Double { max(0, Self.duration - elapsed) }
    public var accuracy: Int {
        returns + misses == 0 ? 0 : Int((Double(returns) / Double(returns + misses) * 100).rounded())
    }
    public var rank: String {
        if !completed { return "KEEP SWINGING" }
        if longestRally >= 10 && accuracy >= 90 { return "S" }
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

    public mutating func updateOpponentControl(positionX: Float?, didSwing: Bool) {
        manualOpponentX = positionX.map { max(-6, min(6, $0)) }
        if positionX == nil { manualOpponentSwingAt = nil }
        else if didSwing { manualOpponentSwingAt = elapsed }
    }

    @discardableResult
    public mutating func advance(_ delta: Double, opponent: any TennisOpponentStrategy) -> [TennisEvent] {
        guard delta.isFinite, delta > 0 else { return [] }
        if phase == .countdown {
            countdown = max(0, countdown - delta)
            if countdown == 0 {
                phase = .playing
                if ball == nil && nextOpponentReturn == nil { scheduleOpponentReturn(after: 0.25) }
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
                let manuallyControlled = manualOpponentX != nil
                let attemptedX = manualOpponentX ?? flight.defenderContactX ?? flight.to.x
                let manualSwingValid = !manuallyControlled || manualOpponentSwingAt.map {
                    assistedOpponent ? $0 >= flight.born : ($0 >= flight.arrival - 0.72 && $0 <= flight.arrival + 0.08)
                } == true
                manualOpponentSwingAt = nil
                let missed = manuallyControlled
                    ? abs(attemptedX - flight.to.x) > 1.0 || !manualSwingValid
                    : abs(attemptedX - flight.to.x) > 0.04
                if missed {
                    opponentContactX = attemptedX
                    opponentMisses += 1
                    rally = 0
                    let points = 300
                    score += points
                    events.append(.opponentMiss(ballX: flight.to.x, attemptedX: attemptedX, points: points))
                    scheduleOpponentReturn(after: 0.9)
                    if elapsed >= Self.duration {
                        completed = true; phase = .results; nextOpponentReturn = nil; pendingPlan = nil
                        events.append(.finished)
                    }
                    return events
                }
                opponentContactX = flight.to.x
                let plan = validatedPlan(opponent)
                let prepared = TennisOpponentReturn(targetX: plan.targetX, flightDuration: plan.flightDuration,
                                                    delay: plan.delay,
                                                    stroke: plan.stroke)
                pendingPlan = prepared
                nextOpponentReturn = elapsed + prepared.delay
                events.append(.opponentPreparing(contactX: opponentContactX, stroke: prepared.stroke, delay: prepared.delay))
            }
        }

        if let launchTime = nextOpponentReturn, elapsed >= launchTime, ball == nil {
            nextOpponentReturn = nil
            let plan = pendingPlan ?? validatedPlan(opponent)
            pendingPlan = nil
            sequence += 1
            ball = TennisBallFlight(id: sequence, born: elapsed, duration: plan.flightDuration,
                                    from: SIMD3<Float>(opponentContactX, 0.05, -18),
                                    to: SIMD3<Float>(plan.targetX, -0.1, 0),
                                    arcHeight: 2.25, direction: .towardPlayer,
                                    bounce: SIMD3<Float>(plan.targetX * 0.72, -1.48, -4.2),
                                    bounceProgress: 0.72)
            events.append(.opponentReturn(contactX: opponentContactX, stroke: plan.stroke))
        }

        if ballsLeft == 0 || elapsed >= Self.duration {
            completed = elapsed >= Self.duration
            phase = .results
            ball = nil
            nextOpponentReturn = nil
            pendingPlan = nil
            events.append(.finished)
        }
        return events
    }

    /// Returns nil unless the incoming ball is inside its strike window.
    @discardableResult
    public mutating func playerHit(speed: Float, horizontalDirection: Float) -> TennisEvent? {
        guard horizontalDirection.isFinite else { return nil }
        return playerHit(speed: speed, targetX: horizontalDirection * 1.25,
                         flightDuration: max(2.35, 3.05 - Double(min(speed, 4)) * 0.10))
    }

    /// The scene adapter supplies a tested face contact and bounded shot response.
    @discardableResult
    public mutating func playerHit(speed: Float, targetX: Float, flightDuration: Double,
                                   contactPoint: SIMD3<Float>? = nil) -> TennisEvent? {
        guard speed.isFinite, targetX.isFinite, flightDuration.isFinite else { return nil }
        if let contactPoint, !contactPoint.indices.allSatisfy({ contactPoint[$0].isFinite }) { return nil }
        guard phase == .playing, let incoming = ball, incoming.direction == .towardPlayer else { return nil }
        guard elapsed >= incoming.arrival - 0.32, elapsed <= incoming.arrival + 0.38, speed >= 0.75 else { return nil }
        let contact = contactPoint ?? incoming.position(at: elapsed)
        rally += 1
        returns += 1
        longestRally = max(longestRally, rally)
        let points = 100 + min(250, rally * 15) + Int(min(150, speed * 28))
        score += points
        // RacketGeometry emits a normalized lane (-1.1...1.1); expand that
        // across the visible court while preserving the direct strategy API.
        let aim = max(-4.6, min(4.6, targetX * 4.18))
        let duration = min(4, max(0.85, flightDuration))
        let distance = abs(aim - opponentContactX)
        let movement = Float(duration) * 1.35
        let attemptedX: Float
        if let manualOpponentX {
            attemptedX = manualOpponentX
            manualOpponentSwingAt = nil
        } else {
            attemptedX = distance <= movement + 1
                ? aim : opponentContactX + (aim < opponentContactX ? -1 : 1) * movement
        }
        ball = TennisBallFlight(id: incoming.id, born: elapsed, duration: duration,
                                from: contact, to: SIMD3<Float>(aim, 0.05, -18),
                                arcHeight: 2.05, direction: .towardOpponent,
                                bounce: SIMD3<Float>(aim * 0.78, -1.48, -13.8),
                                bounceProgress: 0.68, defenderContactX: attemptedX)
        return .playerReturn(points: points)
    }

    private mutating func scheduleOpponentReturn(after delay: Double) {
        pendingPlan = nil
        nextOpponentReturn = elapsed + delay
    }

    private func validatedPlan(_ opponent: any TennisOpponentStrategy) -> TennisOpponentReturn {
        let fallback = AutomaticReboundOpponent().returnPlan(rally: rally, sequence: sequence)
        return opponent.returnPlan(rally: rally, sequence: sequence).validated(fallback: fallback)
    }
}
