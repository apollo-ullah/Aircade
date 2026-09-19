import Foundation
import simd

/// The Mac owns the match. Controllers provide poses, never damage or score.
public struct SaberDuel {
    public enum Phase { case lobby, countdown, playing, paused, results }
    public struct Event {
        public enum Kind { case hit, clash }
        public let kind: Kind
        public let player: PlayerSlot
        public let point: SIMD3<Float>
    }
    public private(set) var phase: Phase = .lobby
    public private(set) var health = [5, 5]
    public private(set) var countdown = 3.0
    public private(set) var elapsed = 0.0
    public private(set) var winner: PlayerSlot?
    public private(set) var recovering = false
    public private(set) var pauseReason = ""
    public var remaining: Double { max(0, 60 - elapsed) }
    private var previous: [SaberPose]?
    private var previousSampleTimes: [Double]?
    private var lastTime: Double?
    private var missingSince: Double?
    private var latched = [false, false]
    private var cooldown = [0.0, 0.0]
    private var touchingBlades = false

    public init() {}
    public static func hilt(_ player: PlayerSlot) -> SIMD3<Float> {
        SIMD3(player == .one ? -0.8 : 0.8, -0.85, 0.15)
    }
    public static func target(_ player: PlayerSlot) -> SIMD3<Float> {
        SIMD3(player == .one ? -1.25 : 1.25, 0.3, 0)
    }
    public static let targetHalf = SIMD3<Float>(0.30, 0.43, 0.25)
    public static func pose(_ player: PlayerSlot, _ orientation: simd_quatf) -> SaberPose {
        SaberPose(position: hilt(player), orientation: orientation)
    }
    public mutating func start() {
        self = SaberDuel(); phase = .countdown
    }
    public mutating func pause(_ reason: String) {
        guard phase == .playing || phase == .countdown else { return }
        phase = .paused; pauseReason = reason; previous = nil; previousSampleTimes = nil; lastTime = nil
    }
    public mutating func resume() {
        guard phase == .paused else { return }
        phase = .countdown; countdown = 3; previous = nil; previousSampleTimes = nil; lastTime = nil; missingSince = nil; recovering = false
    }

    /// A missing pose freezes time and clears sweep history. Reconnection never
    /// draws a damaging sweep through the gap or advances the match clock.
    /// sampleTimes are host-monotonic capture estimates, not peer uptimes. A
    /// render tick may reuse a sample, but cannot shorten its measured swing.
    /// Omit them for generated poses whose sample clock is the render clock.
    public mutating func step(at time: Double, poses: [SaberPose?], sampleTimes: [Double?]? = nil) -> [Event] {
        guard time.isFinite, poses.count == 2, sampleTimes == nil || sampleTimes?.count == 2 else { return [] }
        let dt = lastTime.map { time - $0 } ?? 0
        guard dt >= 0 else { return [] }
        lastTime = time
        guard phase == .countdown || phase == .playing else { previous = nil; previousSampleTimes = nil; return [] }
        let timestamps = sampleTimes ?? [time, time]
        guard let first = poses[0], let second = poses[1],
              let firstTime = timestamps[0], let secondTime = timestamps[1],
              firstTime.isFinite, secondTime.isFinite,
              firstTime <= time, secondTime <= time,
              time - firstTime < 0.25, time - secondTime < 0.25 else {
            previous = nil; previousSampleTimes = nil; recovering = true
            if missingSince == nil { missingSince = time }
            if time - (missingSince ?? time) >= 1 {
                pause("Controller disconnected. Restore both controllers, then resume.")
            }
            return []
        }
        var current = [first, second], acceptedTimes = [firstTime, secondTime]
        if recovering {
            recovering = false; missingSince = nil; previous = current; previousSampleTimes = acceptedTimes
            return []
        }
        defer { previous = current; previousSampleTimes = acceptedTimes }
        guard let old = previous, let oldTimes = previousSampleTimes else { return [] }
        var sampleIntervals = [0.0, 0.0]
        for i in 0..<2 {
            if acceptedTimes[i] > oldTimes[i] { sampleIntervals[i] = acceptedTimes[i] - oldTimes[i] }
            else {
                // Ignore even a different orientation if its timestamp is not newer.
                current[i] = old[i]; acceptedTimes[i] = oldTimes[i]
            }
        }
        guard dt > 0, dt <= 0.15 else { return [] }
        if phase == .countdown {
            countdown = max(0, countdown - dt)
            if countdown == 0 { phase = .playing }
            return []
        }
        elapsed = min(60, elapsed + dt)
        for i in 0..<2 { cooldown[i] = max(0, cooldown[i] - dt) }
        var events: [Event] = []
        // Check both moving blades, including the arc between samples.
        let moved = sampleIntervals.map { $0 > 0 && $0 <= 0.15 }
        // A long per-device gap establishes a new baseline, not a catch-up stroke.
        let sweepStart = (0..<2).map { moved[$0] ? old[$0] : current[$0] }
        if let point = Self.clash(from: sweepStart, to: current, sampleIntervals: sampleIntervals) {
            if !touchingBlades && (cooldown.max() ?? 0) == 0 {
                events.append(Event(kind: .clash, player: .one, point: point))
                cooldown = [0.32, 0.32]
            }
            touchingBlades = true
        } else if moved.contains(true) { touchingBlades = false }
        for player in PlayerSlot.allCases {
            let i = player.rawValue
            let target = Self.target(player.other)
            let overlaps = CombatGeometry.segmentBox(from: current[i].point(0.12), to: current[i].point(CombatGeometry.bladeLength),
                center: target, half: Self.targetHalf + SIMD3(repeating: 0.045)) != nil
            if !overlaps && cooldown[i] == 0 { latched[i] = false }
            guard moved[i], !latched[i], cooldown[i] == 0,
                  let contact = CombatGeometry.sweep(from: old[i], to: current[i], dt: sampleIntervals[i], center: target, half: Self.targetHalf),
                  contact.speed >= 1.4, contact.cuttingAlignment >= 0.35 else { continue }
            health[player.other.rawValue] = max(0, health[player.other.rawValue] - 1)
            latched[i] = true; cooldown[i] = 0.55
            events.append(Event(kind: .hit, player: player, point: contact.point))
        }
        if health.contains(0) || elapsed >= 60 {
            phase = .results
            winner = health[0] == health[1] ? nil : health[0] > health[1] ? .one : .two
        }
        return events
    }

    private static func clash(from old: [SaberPose], to current: [SaberPose], sampleIntervals: [Double]) -> SIMD3<Float>? {
        let travel = (0..<2).map { i in
            2 * acos(min(1, abs(simd_dot(old[i].orientation.vector, current[i].orientation.vector)))) * CombatGeometry.bladeLength
        }
        let speeds = (0..<2).map { i in
            sampleIntervals[i] > 0 && sampleIntervals[i] <= 0.15 ? travel[i] / Float(sampleIntervals[i]) : 0
        }
        guard max(speeds[0], speeds[1]) >= 1.4 else { return nil }
        let steps = max(1, min(128, Int(ceil((travel[0] + travel[1]) / 0.035))))
        for step in 0...steps {
            let f = Float(step) / Float(steps)
            let poses = (0..<2).map { i in SaberPose(position: current[i].position,
                orientation: simd_slerp(old[i].orientation, current[i].orientation, f)) }
            let direction0 = poses[0].orientation.act(SIMD3<Float>(0, 1, 0))
            let direction1 = poses[1].orientation.act(SIMD3<Float>(0, 1, 0))
            // Nearly parallel blades can slide past one another; crossed blades block.
            guard simd_length(simd_cross(direction0, direction1)) >= 0.35 else { continue }
            let closest = closestPoints(poses[0].point(0.18), poses[0].point(CombatGeometry.bladeLength),
                                        poses[1].point(0.18), poses[1].point(CombatGeometry.bladeLength))
            if simd_distance(closest.0, closest.1) < 0.13 { return (closest.0 + closest.1) / 2 }
        }
        return nil
    }

    /// Closest points on two finite line segments, including parallel segments.
    static func closestPoints(_ p: SIMD3<Float>, _ q: SIMD3<Float>, _ r: SIMD3<Float>, _ s: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let d1 = q - p, d2 = s - r, offset = p - r
        let a = simd_dot(d1, d1), e = simd_dot(d2, d2), b = simd_dot(d1, d2)
        let c = simd_dot(d1, offset), f = simd_dot(d2, offset)
        let denominator = a * e - b * b
        var t: Float = denominator > 0.000001 ? min(1, max(0, (b * f - c * e) / denominator)) : 0
        var u = (b * t + f) / e
        if u < 0 { u = 0; t = min(1, max(0, -c / a)) }
        else if u > 1 { u = 1; t = min(1, max(0, (b - c) / a)) }
        return (p + d1 * t, r + d2 * u)
    }
}
