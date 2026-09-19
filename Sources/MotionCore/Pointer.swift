import Foundation
import simd

/// Turns a controller orientation into a normalised screen point in -1...1.
///
/// Consumes the same reference-relative, grip-corrected quaternion the blade
/// uses, so grip calibration and recentering apply to the cursor unchanged.
/// Uses the upright blade axis: the calibrated left tilt (+Z) points left,
/// and the calibrated forward tilt (-X, toward the screen) points up.
public struct PointerTracker {
    /// Half-width of the pointing cone, in radians.
    public var yawSpan: Double
    public var pitchSpan: Double
    /// Angular movement below this is treated as tremor and ignored.
    public var deadZone: Double

    public private(set) var point = SIMD2<Double>(0, 0)
    public private(set) var isLost = false

    public init(yawSpan: Double = 22.5 * .pi / 180,
                pitchSpan: Double = 13 * .pi / 180,
                deadZone: Double = 0.35 * .pi / 180) {
        self.yawSpan = yawSpan
        self.pitchSpan = pitchSpan
        self.deadZone = deadZone
    }

    /// Screen tilts of the upright controller. Twisting its stem does not aim.
    public static func angles(_ orientation: simd_quatf) -> (yaw: Double, pitch: Double) {
        let up = orientation.act(SIMD3<Float>(0, 1, 0))
        let yaw = atan2(Double(up.x), Double(up.y))
        let pitch = atan2(Double(-up.z), Double(up.y))
        return (yaw, pitch)
    }

    @discardableResult
    public mutating func update(orientation: simd_quatf,
                                sampleAge: Double,
                                staleAfter: Double = 0.5) -> SIMD2<Double> {
        guard sampleAge.isFinite, sampleAge >= 0, sampleAge <= staleAfter,
              orientation.vector.indices.allSatisfy({ orientation.vector[$0].isFinite }) else {
            // Hold the last point: snapping to centre on every dropout would
            // throw the cursor across the screen during brief packet gaps.
            isLost = true
            return point
        }
        isLost = false
        let (yaw, pitch) = Self.angles(orientation)
        let target = SIMD2(clamped(yaw / yawSpan), clamped(pitch / pitchSpan))
        let movedYaw = abs(target.x - point.x) * yawSpan
        let movedPitch = abs(target.y - point.y) * pitchSpan
        if movedYaw > deadZone || movedPitch > deadZone { point = target }
        return point
    }

    public mutating func reset() {
        point = SIMD2<Double>(0, 0)
        isLost = false
    }

    private func clamped(_ value: Double) -> Double { min(1, max(-1, value)) }
}
