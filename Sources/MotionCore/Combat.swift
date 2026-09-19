import Foundation
import simd

public struct SaberPose {
    public var position: SIMD3<Float>
    public var orientation: simd_quatf
    public init(position: SIMD3<Float>, orientation: simd_quatf) {
        self.position = position; self.orientation = orientation
    }
    public func point(_ distance: Float) -> SIMD3<Float> {
        position + orientation.act(SIMD3<Float>(0, distance, 0))
    }
}

public struct BladeContact {
    public let point: SIMD3<Float>
    public let velocity: SIMD3<Float>
    public let speed: Float
    /// 1 = broadside cut, 0 = travelling along the blade (a thrust).
    public let cuttingAlignment: Float
}

public enum CombatGeometry {
    public static let bladeLength: Float = 2.35
    public static func segmentBox(from a: SIMD3<Float>, to b: SIMD3<Float>,
                                  center: SIMD3<Float>, half: SIMD3<Float>) -> Float? {
        var low: Float = 0; var high: Float = 1
        let delta = b - a
        for i in 0..<3 {
            if abs(delta[i]) < 0.000001 {
                if a[i] < center[i] - half[i] || a[i] > center[i] + half[i] { return nil }
            } else {
                let t1 = (center[i] - half[i] - a[i]) / delta[i]
                let t2 = (center[i] + half[i] - a[i]) / delta[i]
                low = max(low, min(t1, t2)); high = min(high, max(t1, t2))
                if low > high { return nil }
            }
        }
        return low
    }

    /// Subdivide both rotational and translational motion so fast strokes do not tunnel through a block.
    public static func sweep(from previous: SaberPose, to current: SaberPose, dt: Double,
                             center: SIMD3<Float>, half: SIMD3<Float>, length: Float = bladeLength) -> BladeContact? {
        guard dt > 0, dt <= 0.15 else { return nil }
        let angle = 2 * acos(min(1, abs(simd_dot(previous.orientation.vector, current.orientation.vector))))
        let travel = simd_distance(previous.position, current.position) + angle * length
        let steps = max(1, min(256, Int(ceil(travel / 0.035))))
        for i in 0...steps {
            let f = Float(i) / Float(steps)
            let pose = SaberPose(position: simd_mix(previous.position, current.position, SIMD3<Float>(repeating: f)),
                                 orientation: simd_slerp(previous.orientation, current.orientation, f))
            if let along = segmentBox(from: pose.point(0.12), to: pose.point(length),
                                      center: center, half: half + SIMD3<Float>(repeating: 0.045)) {
                let distance = 0.12 + along * (length - 0.12)
                let velocity = (current.point(distance) - previous.point(distance)) / Float(dt)
                let speed = simd_length(velocity)
                let direction = pose.orientation.act(SIMD3<Float>(0, 1, 0))
                let dot = speed > 0.001 ? abs(simd_dot(direction, velocity / speed)) : 1
                return BladeContact(point: pose.point(distance), velocity: velocity, speed: speed,
                                    cuttingAlignment: sqrt(max(0, 1 - dot * dot)))
            }
        }
        return nil
    }

    public static func distanceToBlade(_ point: SIMD3<Float>, pose: SaberPose) -> Float {
        let a = pose.point(0.12); let b = pose.point(bladeLength); let ab = b - a
        let t = min(1, max(0, simd_dot(point - a, ab) / simd_dot(ab, ab)))
        return simd_distance(point, a + ab * t)
    }

    public static func validGuard(pose: SaberPose, target: SIMD3<Float>, horizontal: Bool) -> Bool {
        let direction = pose.orientation.act(SIMD3<Float>(0, 1, 0))
        let alignment = horizontal ? abs(direction.x) : abs(direction.y)
        return alignment >= cos(Float.pi * 35 / 180) && distanceToBlade(target, pose: pose) <= 0.48
    }
}

/// Measure two deliberate tilts from the same neutral pose, then build a proper rotation basis.
public enum GripCalibration {
    public enum TiltIssue { case invalid, tooSmall, tooLarge, sameAxis }
    public struct TiltAssessment {
        public let degrees: Float
        public let separationDegrees: Float?
        public let issue: TiltIssue?
        public var isValid: Bool { issue == nil }
    }
    /// Report the same acceptance limits used by the capture flow before the user presses Save.
    public static func assessTilt(_ vector: SIMD3<Float>, comparedTo left: SIMD3<Float>? = nil) -> TiltAssessment {
        let angle = simd_length(vector)
        guard angle.isFinite else { return TiltAssessment(degrees: 0, separationDegrees: nil, issue: .invalid) }
        let degrees = angle * 180 / .pi
        guard angle > 0.25 else { return TiltAssessment(degrees: degrees, separationDegrees: nil, issue: .tooSmall) }
        guard angle < 1.9 else { return TiltAssessment(degrees: degrees, separationDegrees: nil, issue: .tooLarge) }
        guard let left else { return TiltAssessment(degrees: degrees, separationDegrees: nil, issue: nil) }
        guard simd_length(left).isFinite, simd_length(left) > 0.25 else {
            return TiltAssessment(degrees: degrees, separationDegrees: nil, issue: .invalid)
        }
        let similarity = min(1, abs(simd_dot(simd_normalize(left), simd_normalize(vector))))
        let separation = acos(similarity) * 180 / .pi
        return TiltAssessment(degrees: degrees, separationDegrees: separation, issue: similarity >= 0.75 ? .sameAxis : nil)
    }
    public static func rotationVector(reference: simd_quatf, sample: simd_quatf) -> SIMD3<Float> {
        var delta = simd_normalize(reference.inverse * sample)
        if delta.real < 0 { delta = simd_quatf(vector: -delta.vector) }
        let angle = 2 * acos(min(1, max(-1, delta.real)))
        let axis = SIMD3<Float>(delta.imag.x, delta.imag.y, delta.imag.z)
        return simd_length(axis) < 0.0001 ? .zero : simd_normalize(axis) * angle
    }
    public static func basis(left: SIMD3<Float>, forward: SIMD3<Float>) -> simd_quatf? {
        guard simd_length(left) > 0.25, simd_length(forward) > 0.25 else { return nil }
        let a = simd_normalize(left)
        let b0 = simd_normalize(forward)
        guard abs(simd_dot(a, b0)) < 0.75 else { return nil }
        let b = simd_normalize(b0 - a * simd_dot(a, b0))
        let c = simd_cross(a, b)
        let source = simd_float3x3(columns: (a, b, c))
        // A left tilt rotates the upright blade around +Z; a forward tilt rotates around -X.
        let target = simd_float3x3(columns: (SIMD3<Float>(0, 0, 1), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, -1, 0)))
        return simd_normalize(simd_quatf(target * source.transpose))
    }
}
