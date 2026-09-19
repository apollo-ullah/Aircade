import Foundation
import simd

public enum SaberScript: String, CaseIterable, Identifiable {
    case perfectRun = "Win the full game"
    case stationary = "Stationary contact"
    case slowTouch = "Slow touch"
    case thrust = "Thrust along blade"
    case wrongWay = "Wrong-way cuts"
    case hazards = "Hit red hazards"
    case missAll = "Miss every block"
    public var id: String { rawValue }
    public var expectation: String {
        switch self {
        case .perfectRun: return "Clear all three rounds, follow arrows and avoid red hazards."
        case .stationary: return "A parked blade must not cut a block that reaches it."
        case .slowTouch: return "Slow contact must not score or shatter the block."
        case .thrust: return "Movement along the blade must not count as a slash."
        case .wrongWay: return "Follow normal blocks; deliberately reverse cyan arrows."
        case .hazards: return "Cut normal blocks and deliberately touch red hazards."
        case .missAll: return "Leave every block alone; energy should reach zero."
        }
    }
}

/// Supplies poses only. Scoring, collision, target selection, expiry and the win
/// condition all run through the same game code as a real controller.
public struct ScriptedSaber {
    public let script: SaberScript
    private var target: RushTarget?
    private var finished: Set<Int> = []
    public static let parked = SaberPose(position: SIMD3<Float>(0, -1.4, 3),
                                         orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)))
    public init(_ script: SaberScript) { self.script = script }

    public mutating func pose(for game: NeonRush) -> SaberPose {
        // A new round reuses target IDs. Reset here so every launch path, including
        // the results screen and Space shortcut, can replay the same controller.
        if game.phase == .countdown && game.elapsed == 0 {
            target = nil; finished.removeAll(keepingCapacity: true)
        }
        guard game.phase == .playing else { return Self.parked }
        if script == .missAll { return Self.parked }
        let passive = script == .stationary || script == .slowTouch || script == .thrust
        if let target, game.elapsed > (passive ? target.deadline + 0.05 : target.arrival + 0.65) {
            finished.insert(target.id); self.target = nil
        }
        if target == nil {
            target = game.targets.first { !finished.contains($0.id) && (!$0.hazard || script == .hazards) }
        }
        guard let target else { return Self.parked }
        let t = game.elapsed - target.arrival
        let upright = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        if passive {
            // The target approaches the blade. No fake contact/velocity is injected.
            if script == .stationary {
                return SaberPose(position: SIMD3(target.x, -0.5, 0), orientation: upright)
            }
            if script == .thrust {
                let y = -0.5 + Float(max(0, min(0.6, t))) * 2
                return SaberPose(position: SIMD3(target.x, y, 0), orientation: upright)
            }
            let x = target.x + 0.43 - Float(max(0, min(0.8, t))) * 0.28
            return SaberPose(position: SIMD3(x, -0.5, 0), orientation: upright)
        }
        if target.hazard {
            return SaberPose(position: SIMD3(target.x, -0.5, 0), orientation: upright)
        }
        var direction = target.direction
        if direction == .any { direction = target.id % 2 == 0 ? .left : .right }
        let wrong = script == .wrongWay && target.direction != .any
        let down = direction == .down
        let sign: Float = (direction == .left || direction == .down ? -1 : 1) * (wrong ? -1 : 1)
        let progress = Float(min(1, max(0, (t - 0.12) / 0.22)))
        let across = sign * (-0.52 + progress * 1.04)
        // The downward-cut blade points into the screen so it cannot span adjacent lanes.
        let orientation = down ? simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0)) : upright
        let cutDepth: Float = down ? 1.2 : 0
        let approach = Float(min(1, max(0, t / 0.10)))
        let retract = Float(min(1, max(0, (t - 0.36) / 0.12)))
        let z = 3 + (cutDepth - 3) * approach * (1 - retract)
        return SaberPose(position: SIMD3(down ? target.x : target.x + across,
                                        down ? target.y + across : -0.5, z), orientation: orientation)
    }
}
