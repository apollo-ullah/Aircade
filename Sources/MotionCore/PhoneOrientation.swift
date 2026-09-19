import simd

/// Portrait phone: X is screen-right, Y is the top edge, Z faces the player.
/// This matches the arena axes, so a single neutral capture is sufficient.
public struct PhoneOrientation {
    public private(set) var reference: simd_quatf?
    public init() {}
    public mutating func recenter(_ orientation: simd_quatf) {
        guard Self.valid(orientation) else { return }
        reference = simd_normalize(orientation)
    }
    public func calibrated(_ orientation: simd_quatf) -> simd_quatf? {
        guard let reference, Self.valid(orientation) else { return nil }
        return simd_normalize(reference.inverse * orientation)
    }
    private static func valid(_ q: simd_quatf) -> Bool {
        q.vector.indices.allSatisfy { q.vector[$0].isFinite } && simd_length(q.vector) > 0.001
    }
}
