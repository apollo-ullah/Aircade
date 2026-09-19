import Foundation
import simd

public struct TennisControlCommand: Codable {
    public var run: String
    public var rally: Int
    public var sequence: Int
    public var frame: Int
    public var x: Float
    public var swing: Bool
    public init(run: String, rally: Int, sequence: Int, frame: Int, x: Float, swing: Bool) {
        self.run = run; self.rally = rally; self.sequence = sequence; self.frame = frame; self.x = x; self.swing = swing
    }
}

/// All movement is input-driven. A click executes one fixed stroke; there is no ball lookup.
public struct TennisOpponentController {
    public private(set) var x: Float = 0
    public private(set) var target: Float = 0
    public private(set) var strokeTime: Double = 4
    public static let strokeDuration = 3.0
    public var swinging: Bool { strokeTime < Self.strokeDuration }
    public var pose: SaberPose {
        // Strings face the near court. One forward stroke traverses three scene units.
        let z: Float = swinging ? -19.2 + Float(strokeTime) * 1.05 : -19.2
        return SaberPose(position: SIMD3<Float>(x, -1.12, z), orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)))
    }
    public init() {}
    public mutating func input(x: Float, swing: Bool) {
        guard x.isFinite else { return }
        target = min(4.6, max(-4.6, x))
        if swing && !swinging { strokeTime = 0 }
    }
    public mutating func release() { target = x; strokeTime = 4 }
    public mutating func advance(_ dt: Double) {
        guard dt.isFinite, dt > 0, dt <= 0.1 else { return }
        let step = Float(dt) * 3
        x += min(step, max(-step, target - x))
        strokeTime += dt
    }
}

/// Separate rules and scores from the assisted GLM rally. Flights take eight real seconds
/// in either direction; waiting for inference never changes simulation speed.
public struct AIChallengeMatch {
    public static let flightDuration = 8.0
    public static let duration = 60.0
    public private(set) var phase: TennisPhase = .menu
    public private(set) var run = UUID().uuidString
    public private(set) var rally = 0
    public private(set) var elapsed = 0.0
    public private(set) var humanPoints = 0
    public private(set) var aiPoints = 0
    public private(set) var aiReturns = 0
    public private(set) var humanReturns = 0
    public private(set) var ball: TennisBallFlight?
    public private(set) var controller = TennisOpponentController()
    public private(set) var lastSequence = -1
    private var nextServe = 0.5
    private var flightID = 0
    private var serveSeed = 0
    public var remaining: Double { max(0, Self.duration - elapsed) }
    public var winner: String { humanPoints == aiPoints ? "Draw" : humanPoints > aiPoints ? "You win!" : "Astra wins!" }
    public init() {}
    public mutating func start(seed: Int = 0) { self = Self(); serveSeed = abs(seed % 3); phase = .playing }
    public mutating func pause() { if phase == .playing { phase = .paused; controller.release() } }
    public mutating func resume() { if phase == .paused { phase = .playing } }
    public mutating func stop() { phase = .menu; ball = nil; controller.release() }
    public mutating func apply(_ command: TennisControlCommand, observationAge: Double) -> Bool {
        guard phase == .playing, command.run == run, command.rally == rally,
              command.sequence > lastSequence, command.frame >= 0, command.x.isFinite,
              observationAge.isFinite, observationAge >= 0, observationAge <= 6 else { return false }
        lastSequence = command.sequence
        controller.input(x: command.x, swing: command.swing)
        return true
    }
    public mutating func advance(_ dt: Double) -> RacketContact? {
        guard phase == .playing, dt.isFinite, dt > 0, dt <= 0.1 else { return nil }
        let oldTime = elapsed, previous = controller.pose, wasSwinging = controller.swinging
        elapsed = min(Self.duration, elapsed + dt)
        controller.advance(dt)
        if elapsed >= Self.duration { phase = .results; ball = nil; controller.release(); return nil }
        if let flight = ball {
            if flight.direction == .towardOpponent, wasSwinging,
               let contact = RacketGeometry.sweep(from: previous, to: controller.pose, dt: dt,
                   ballFrom: flight.position(at: oldTime), ballTo: flight.position(at: elapsed)), contact.swingSpeed >= 0.75 {
                aiReturns += 1
                // Fixed face orientation aims straight; lateral controller velocity adds modest aim.
                launch(from: contact.point, x: max(-0.9, min(0.9, contact.velocity.x * 0.25)), direction: .towardPlayer)
                return contact
            }
            if elapsed > flight.arrival + 0.45 {
                if flight.direction == .towardPlayer { aiPoints += 1 } else { humanPoints += 1 }
                rally += 1; ball = nil; nextServe = elapsed + 1
                controller.release()
            }
        } else if elapsed >= nextServe {
            let toAI = rally % 2 == 0
            let lanes: [Float] = [-2.5, 0, 2.5]
            launch(from: SIMD3<Float>(0, 0.05, toAI ? 0 : -18),
                   x: toAI ? lanes[(rally / 2 + serveSeed) % lanes.count] : 0, direction: toAI ? .towardOpponent : .towardPlayer)
        }
        return nil
    }
    public mutating func humanContact(from previous: SaberPose, to current: SaberPose, dt: Double,
                                       ballFrom: SIMD3<Float>, flightID: Int) -> RacketContact? {
        guard phase == .playing, let flight = ball, flight.id == flightID, flight.direction == .towardPlayer,
              let contact = RacketGeometry.sweep(from: previous, to: current, dt: dt, ballFrom: ballFrom, ballTo: flight.position(at: elapsed)),
              let shot = TennisShotResponse.make(contact: contact) else { return nil }
        humanReturns += 1
        launch(from: contact.point, x: shot.targetX * 4.18, direction: .towardOpponent)
        return contact
    }
    private mutating func launch(from: SIMD3<Float>, x: Float, direction: TennisBallDirection) {
        flightID += 1
        let far = direction == .towardOpponent
        ball = TennisBallFlight(id: flightID, born: elapsed, duration: Self.flightDuration,
            from: from, to: SIMD3<Float>(x, 0.05, far ? -18 : 0), arcHeight: 2.1, direction: direction,
            bounce: SIMD3<Float>(x * 0.8, -1.48, far ? -13.8 : -4.2), bounceProgress: 0.68)
    }
}
