import Foundation
import simd

public enum RushDifficulty: String, CaseIterable, Codable {
    case chill = "Chill", arcade = "Arcade"
    public var lives: Int { self == .chill ? 7 : 5 }
}
public enum RushPhase: String { case menu, countdown, playing, paused, results }
public enum CutDirection: String { case any = "Any", left = "Left", right = "Right", down = "Down" }

public struct RushTarget: Identifiable {
    public let id: Int
    public let born: Double
    public let travel: Double
    public let window: Double
    public let x: Float
    public let y: Float
    public let hazard: Bool
    public let direction: CutDirection
    public var arrival: Double { born + travel }
    public var deadline: Double { arrival + window }
    public func position(at time: Double) -> SIMD3<Float> {
        let progress = Float(min(1, max(0, (time - born) / travel)))
        return SIMD3<Float>(x, y, -8 * (1 - progress))
    }
}
public struct RushJudgment {
    public enum Kind { case cut, perfect, wrongDirection, hazard, miss }
    public let target: RushTarget
    public let kind: Kind
    public let points: Int
}

/// Deterministic round state. Time only advances through `advance`; pauses freeze targets and deadlines.
public struct NeonRush {
    public static let duration: Double = 60
    public private(set) var phase: RushPhase = .menu
    public private(set) var difficulty: RushDifficulty = .arcade
    public private(set) var elapsed = 0.0
    public private(set) var countdown = 3.0
    public private(set) var lives = 5
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var bestCombo = 0
    public private(set) var cuts = 0
    public private(set) var perfects = 0
    public private(set) var mistakes = 0
    public private(set) var targets: [RushTarget] = []
    public private(set) var completed = false
    private var nextSpawn = 0.0
    private var nextID = 0
    private var random: UInt64 = 42
    private var priorLane = 0
    public var remaining: Double { max(0, Self.duration - elapsed) }
    public var round: Int { min(3, Int(elapsed / 20) + 1) }
    public var roundName: String { ["IGNITE", "FLOW", "OVERDRIVE"][round - 1] }
    public var multiplier: Int { min(4, 1 + combo / 5) }
    public var accuracy: Int { cuts + mistakes == 0 ? 0 : Int((Double(cuts) / Double(cuts + mistakes) * 100).rounded()) }
    public var rank: String {
        if !completed { return "KEEP GOING" }
        if accuracy >= 95 && bestCombo >= 15 { return "S" }
        if accuracy >= 85 { return "A" }
        if accuracy >= 70 { return "B" }
        return "C"
    }
    public init() {}
    public mutating func start(difficulty: RushDifficulty, seed: UInt64 = 42) {
        self = NeonRush()
        self.difficulty = difficulty; lives = difficulty.lives
        random = seed; phase = .countdown
    }
    public mutating func pause() {
        guard phase == .playing || phase == .countdown else { return }
        phase = .paused
    }
    public mutating func resume() {
        guard phase == .paused else { return }
        phase = .countdown; countdown = 2
    }
    public mutating func quit() { self = NeonRush() }

    @discardableResult
    public mutating func advance(_ delta: Double) -> [RushJudgment] {
        guard delta.isFinite && delta > 0 else { return [] }
        if phase == .countdown {
            countdown = max(0, countdown - delta)
            if countdown == 0 { phase = .playing }
            return []
        }
        guard phase == .playing else { return [] }
        elapsed = min(Self.duration, elapsed + delta)
        var events: [RushJudgment] = []
        for target in targets where elapsed > target.deadline {
            if !target.hazard {
                loseLife()
                events.append(RushJudgment(target: target, kind: .miss, points: 0))
            }
        }
        targets.removeAll { elapsed > $0.deadline }
        if lives <= 0 { phase = .results; targets = []; return events }
        if elapsed >= Self.duration { completed = true; phase = .results; targets = []; return events }
        // Stop new spawns in time for every remaining target's deadline to precede the finish.
        if elapsed >= nextSpawn && elapsed < Self.duration - 3 {
            spawn()
            let intervals: [Double] = difficulty == .chill ? [1.7, 1.45, 1.2] : [1.45, 1.15, 0.9]
            nextSpawn = elapsed + intervals[round - 1]
        }
        return events
    }

    /// One target can be judged only once. Contact alone on a stationary blade never scores a cut.
    public mutating func contact(id: Int, velocity: SIMD3<Float>, speed: Float, alignment: Float) -> RushJudgment? {
        guard phase == .playing, let index = targets.firstIndex(where: { $0.id == id }) else { return nil }
        let target = targets[index]
        guard elapsed >= target.arrival - 0.13 else { return nil }
        if target.hazard {
            targets.remove(at: index); loseLife()
            if lives <= 0 { phase = .results; targets = [] }
            return RushJudgment(target: target, kind: .hazard, points: 0)
        }
        guard speed >= 0.8, alignment >= 0.35 else { return nil }
        let xy = SIMD2<Float>(velocity.x, velocity.y)
        let desired: SIMD2<Float> = target.direction == .left ? SIMD2(-1, 0) : target.direction == .right ? SIMD2(1, 0) : SIMD2(0, -1)
        let correct = target.direction == .any || (simd_length(xy) > 0.1 && simd_dot(simd_normalize(xy), desired) >= 0.55)
        targets.remove(at: index)
        if !correct {
            loseLife()
            if lives <= 0 { phase = .results; targets = [] }
            return RushJudgment(target: target, kind: .wrongDirection, points: 0)
        }
        let perfect = alignment >= 0.85 && speed >= 1.8
        let points = (perfect ? 150 : 100) * multiplier
        cuts += 1; combo += 1; bestCombo = max(bestCombo, combo); score += points
        if perfect { perfects += 1 }
        return RushJudgment(target: target, kind: perfect ? .perfect : .cut, points: points)
    }
    private mutating func loseLife() { lives = max(0, lives - 1); combo = 0; mistakes += 1 }
    private mutating func rand(_ upper: Int) -> Int {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return Int((random >> 32) % UInt64(upper))
    }
    private mutating func spawn() {
        nextID += 1
        var lane = rand(3) - 1
        if lane == priorLane { lane = (lane + 2) % 3 - 1 }
        let hazard = elapsed >= 15 && nextID % (difficulty == .chill ? 9 : 6) == 0
        if hazard && lane == 0 { lane = rand(2) == 0 ? -1 : 1 }
        priorLane = lane
        var direction: CutDirection = .any
        if !hazard && difficulty == .arcade && round >= 2 && nextID % 3 == 0 {
            direction = lane < 0 ? .left : lane > 0 ? .right : .down
        }
        targets.append(RushTarget(id: nextID, born: elapsed,
                                  travel: difficulty == .chill ? 1.7 : 1.4 - Double(round - 1) * 0.15,
                                  window: difficulty == .chill ? 1.3 : 1.1 - Double(round - 1) * 0.12,
                                  x: Float(lane) * 0.95, y: nextID % 4 == 0 ? 0.55 : 1.1,
                                  hazard: hazard, direction: direction))
    }
}
