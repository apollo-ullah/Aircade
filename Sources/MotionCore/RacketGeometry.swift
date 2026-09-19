import Foundation
import simd

/// Local coordinates match the tennis equipment beneath SaberScene's controller pivot.
/// The strings lie in XY, centred above the handle, with their normal along local Z.
public enum RacketDimensions {
    public static let faceCenter = SIMD3<Float>(0, 1.17, 0)
    public static let frameRadius: Float = 0.53
    public static let frameTubeRadius: Float = 0.055
    public static let frameScale = SIMD3<Float>(0.76, 1, 1.13)
    public static let faceHalfWidth = frameRadius * frameScale.x
    public static let faceHalfHeight = frameRadius * frameScale.z
    public static let ballRadius: Float = 0.15
}

public struct RacketContact {
    /// Position on the racket face (or its elliptical boundary), in world coordinates.
    public let point: SIMD3<Float>
    /// Unit local +Z transformed into world coordinates. Both sides of the face can hit.
    public let normal: SIMD3<Float>
    /// Local XY offset from the middle of the string bed, in scene units.
    public let faceCoordinates: SIMD2<Float>
    /// Velocity of the contacting material point on the racket, in scene units/second.
    public let velocity: SIMD3<Float>
    /// Racket contact velocity minus the ball's velocity over this sample.
    public let relativeVelocity: SIMD3<Float>
    /// Racket speed alone: a fast incoming ball must not turn a stationary racket into a swing.
    public let swingSpeed: Float
    /// Contact time within the previous/current sample, from zero to one.
    public let fraction: Float
}

public enum RacketGeometry {
    public static let maximumSampleInterval: Double = 0.15
    public static let maximumSweepIterations = 128
    private static let contactTolerance: Float = 0.0005

    /// Sweep a spherical ball against the finite elliptical racket face. Both ball and
    /// hilt translate linearly; orientation follows the shortest quaternion arc. Conservative
    /// advancement uses an upper bound on relative surface travel, so it cannot step over
    /// a face contact, even when neither endpoint overlaps. Work is bounded; pathological
    /// grazing samples that exhaust the budget fail closed rather than inventing a hit.
    ///
    /// This reports geometry, including stationary overlap. Apply TennisShotResponse's
    /// deliberate-swing gate and latch a successful return by incoming ball identity in
    /// the game. Clear pose/ball history on pauses, tracking gaps and ball replacement.
    public static func sweep(from previous: SaberPose, to current: SaberPose, dt: Double,
                             ballFrom: SIMD3<Float>, ballTo: SIMD3<Float>,
                             ballRadius: Float = RacketDimensions.ballRadius) -> RacketContact? {
        guard dt.isFinite, dt > 0, dt <= maximumSampleInterval,
              Float(dt) > 0, ballRadius.isFinite, ballRadius > 0,
              finite(previous.position), finite(current.position), finite(ballFrom), finite(ballTo),
              let previousOrientation = validOrientation(previous.orientation),
              let currentOrientation = validOrientation(current.orientation) else { return nil }

        let translation = current.position - previous.position
        let ballTravel = ballTo - ballFrom
        var rotation = simd_normalize(currentOrientation * previousOrientation.inverse)
        if rotation.real < 0 { rotation = simd_quatf(vector: -rotation.vector) }
        let angle = 2 * atan2(simd_length(rotation.imag), max(0, rotation.real))
        let reach = simd_length(RacketDimensions.faceCenter) + RacketDimensions.faceHalfHeight
        let travelBound = simd_length(ballTravel - translation) + angle * reach
        let linearVelocity = translation / Float(dt)
        let ballVelocity = ballTravel / Float(dt)
        let angularVelocity = simd_length(rotation.imag) > 0.000001
            ? simd_normalize(rotation.imag) * (angle / Float(dt)) : .zero
        guard travelBound.isFinite, finite(linearVelocity), finite(ballVelocity), finite(angularVelocity) else { return nil }

        var fraction: Float = 0
        for _ in 0..<maximumSweepIterations {
            let orientation = simd_slerp(previousOrientation, currentOrientation, fraction)
            let position = previous.position + translation * fraction
            let ball = ballFrom + ballTravel * fraction
            let localBall = orientation.inverse.act(ball - position) - RacketDimensions.faceCenter
            guard finite(localBall) else { return nil }
            let face = closestFacePoint(SIMD2<Float>(localBall.x, localBall.y))
            let localContact = RacketDimensions.faceCenter + SIMD3<Float>(face.x, face.y, 0)
            let separation = simd_length(localBall - SIMD3<Float>(face.x, face.y, 0)) - ballRadius
            guard separation.isFinite else { return nil }
            if separation <= contactTolerance {
                let offset = orientation.act(localContact)
                let velocity = linearVelocity + simd_cross(angularVelocity, offset)
                let relativeVelocity = velocity - ballVelocity
                let speed = simd_length(velocity)
                guard finite(velocity), finite(relativeVelocity), speed.isFinite else { return nil }
                return RacketContact(point: position + offset,
                                     normal: orientation.act(SIMD3<Float>(0, 0, 1)),
                                     faceCoordinates: face, velocity: velocity,
                                     relativeVelocity: relativeVelocity, swingSpeed: speed,
                                     fraction: fraction)
            }
            guard travelBound > 0, fraction < 1 else { return nil }
            let step = separation / travelBound
            // The bound proves that a larger gap cannot close in the remaining sample.
            guard step <= 1 - fraction + contactTolerance / travelBound else { return nil }
            let next = min(1, fraction + step)
            guard next > fraction else { return nil }
            fraction = next
        }
        return nil
    }

    private static func closestFacePoint(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let radii = SIMD2<Float>(RacketDimensions.faceHalfWidth, RacketDimensions.faceHalfHeight)
        let normalized = point / radii
        if simd_length_squared(normalized) <= 1 { return point }
        // Closest point on an ellipse via its nonnegative Lagrange multiplier. The
        // upper bound brackets the root; fixed bisection keeps per-sample work bounded.
        let squared = radii * radii
        var low: Float = 0
        var high = simd_length(radii * point)
        for _ in 0..<28 {
            let middle = (low + high) / 2
            let candidate = radii * point / (squared + SIMD2<Float>(repeating: middle))
            if simd_length_squared(candidate) > 1 { low = middle } else { high = middle }
        }
        return squared * point / (squared + SIMD2<Float>(repeating: high))
    }

    private static func validOrientation(_ orientation: simd_quatf) -> simd_quatf? {
        let vector = orientation.vector
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite else { return nil }
        let length = simd_length(vector)
        guard length.isFinite, length > 0.000001 else { return nil }
        return simd_quatf(vector: vector / length)
    }

    private static func finite(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}

public struct TennisShot {
    public let targetX: Float
    public let flightDuration: Double
    public let swingSpeed: Float
}

/// A deliberately forgiving arcade response, independent of frame rate and ball speed.
/// Opponent court is -Z. Face tilt controls most of the aim; swing direction adds only
/// a small adjustment. Flight duration changes substantially across gentle/strong shots.
public enum TennisShotResponse {
    public static let minimumSwingSpeed: Float = 0.75
    public static let maximumTargetX: Float = 1.1
    public static let minimumFlightDuration: Double = 0.78
    public static let maximumFlightDuration: Double = 1.35

    public static func make(contact: RacketContact) -> TennisShot? {
        let normalLength = simd_length(contact.normal)
        let speed = simd_length(contact.velocity)
        guard normalLength.isFinite, normalLength > 0.000001,
              speed.isFinite, speed >= minimumSwingSpeed,
              contact.swingSpeed.isFinite, contact.swingSpeed >= minimumSwingSpeed else { return nil }
        var facing = contact.normal / normalLength
        if facing.z > 0 { facing = -facing }
        let lateralSwing = contact.velocity.x / speed
        let target = max(-maximumTargetX, min(maximumTargetX, facing.x * 1.55 + lateralSwing * 0.28))
        let strength = Double(min(1, max(0, (speed - minimumSwingSpeed) / 6)))
        let duration = maximumFlightDuration - strength * (maximumFlightDuration - minimumFlightDuration)
        return TennisShot(targetX: target, flightDuration: duration, swingSpeed: min(speed, 12))
    }
}
