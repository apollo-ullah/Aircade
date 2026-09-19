import simd

/// The original three manual snapshots, without angle targets, steady-hold
/// windows, a return-to-neutral gate, or a preview/confirmation stage.
public struct SimpleGripCalibration {
    public private(set) var step = 1
    public private(set) var reference: simd_quatf?
    public private(set) var left: SIMD3<Float>?
    public private(set) var basis: simd_quatf?
    public private(set) var error = ""
    public init() {}

    @discardableResult public mutating func capture(_ q: simd_quatf) -> Bool {
        error = ""
        guard q.vector.indices.allSatisfy({ q.vector[$0].isFinite }), simd_length(q.vector) > 0.001 else {
            error = "No usable sensor reading. Reconnect the AirPods."
            return false
        }
        if step == 1 {
            reference = simd_normalize(q); step = 2
            return true
        }
        guard let reference else { return false }
        let vector = GripCalibration.rotationVector(reference: reference, sample: q)
        // Only reject a direction too close to zero to normalize. Even 1° is fine.
        guard simd_length(vector) > 0.0001 else {
            error = "The selected earbud hasn't rotated since upright. Move that earbud, then capture again."
            return false
        }
        if step == 2 {
            left = vector; step = 3
            return true
        }
        guard step == 3, let left else { return false }
        let a = simd_normalize(left)
        let forward = simd_normalize(vector)
        let perpendicular = forward - a * simd_dot(a, forward)
        // Two collinear directions cannot define a 3D basis. No quality/angle gate.
        guard simd_length(perpendicular) > 0.0001 else {
            error = "These two tilts point along the same axis. Return upright, then tip toward your Mac."
            return false
        }
        let b = simd_normalize(perpendicular)
        let sensorAxes = simd_float3x3(columns: (a, b, simd_cross(a, b)))
        let gameAxes = simd_float3x3(columns: (SIMD3<Float>(0, 0, 1), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, -1, 0)))
        basis = simd_normalize(simd_quatf(gameAxes * sensorAxes.transpose))
        return true
    }
}
