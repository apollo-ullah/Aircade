import Foundation
import simd

public struct OrientationTracker {
    public private(set) var reference: simd_quatf?
    public private(set) var displayed = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    public init() {}

    public mutating func recenter(_ orientation: simd_quatf) {
        reference = simd_normalize(orientation)
        displayed = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }

    public mutating func update(_ orientation: simd_quatf, basis: simd_quatf,
                                delta: Double, smoothing: Double) -> simd_quatf {
        guard let reference else { return displayed }
        let relative = simd_normalize(reference.inverse * orientation)
        let target = simd_normalize(basis * relative * basis.inverse)
        let weight = smoothing <= 0 ? 1 : 1 - exp(-max(0, delta) / smoothing)
        displayed = simd_slerp(displayed, target, Float(weight))
        return displayed
    }
}

/// A gap or sensor-source change breaks continuity; receiving old data never advances it.
public struct ContinuityTracker {
    public let gapLimit: Double
    public private(set) var lastTime: Double?
    public private(set) var source: String?
    public private(set) var streakStart: Double?
    public private(set) var current: Double = 0
    public private(set) var longest: Double = 0
    public private(set) var gaps = 0
    public private(set) var switches = 0
    public private(set) var count = 0
    public init(gapLimit: Double = 0.5) { self.gapLimit = gapLimit }

    @discardableResult
    public mutating func ingest(time: Double, source newSource: String) -> Bool {
        if let lastTime, time <= lastTime { return false }
        let gap = lastTime.map { time - $0 > gapLimit } ?? false
        let changed = source.map { $0 != newSource } ?? false
        if gap { gaps += 1 }
        if changed { switches += 1 }
        if streakStart == nil || gap || changed { streakStart = time }
        lastTime = time
        source = newSource
        count += 1
        current = time - (streakStart ?? time)
        longest = max(longest, current)
        return true
    }

    public func liveStreak(at time: Double) -> Double {
        guard let lastTime, time - lastTime <= gapLimit else { return 0 }
        return current
    }
}

public struct SwingDetector {
    private var armed = true
    private var lastSwing = -Double.infinity
    public init() {}
    public mutating func update(speed: Double, time: Double, threshold: Double) -> Bool {
        if speed < threshold * 0.55 { armed = true }
        if armed && speed >= threshold && time - lastSwing > 0.3 {
            armed = false
            lastSwing = time
            return true
        }
        return false
    }
}
