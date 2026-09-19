import Foundation
import simd

/// Core Motion chooses the hardware source. We pin the first known source until the
/// user explicitly adopts another; this does not command macOS to change earbuds.
public struct MotionSourceLock {
    public private(set) var selected: String?
    public private(set) var reported: String?
    public init() {}
    public var matches: Bool { selected != nil && selected == reported }
    public mutating func observe(_ source: String) -> Bool {
        reported = source
        guard source == "Left" || source == "Right" else { return false }
        if selected == nil { selected = source }
        return matches
    }
    public mutating func adoptReported() -> Bool {
        guard let reported, reported == "Left" || reported == "Right" else { return false }
        selected = reported
        return true
    }
}

/// A calibration is a transaction. Its proposed basis is not a saved grip until
/// the app explicitly commits it after the live preview.
public struct GripCalibrationSession {
    public enum Stage: Int { case neutral = 1, left, returnNeutral, forward, verify }
    public struct Feedback {
        public let ready: Bool
        public let message: String
    }
    private struct Sample {
        let q: simd_quatf
        let speed: Float
        let sensorTime: Double
        let receivedAt: Double
    }
    public let source: String
    public private(set) var stage = Stage.neutral
    public private(set) var reference: simd_quatf?
    public private(set) var left: SIMD3<Float>?
    public private(set) var proposedBasis: simd_quatf?
    public private(set) var interruption: String?
    private var window: [Sample] = []
    private var latest: Sample?
    public init(source: String) { self.source = source }

    public mutating func interrupt(_ reason: String) {
        // Retain the sheet and a clear reason, never silently advance or switch ears.
        interruption = reason
        reference = nil; left = nil; proposedBasis = nil
        window.removeAll(); latest = nil
    }

    public mutating func ingest(q: simd_quatf, speed: Float, sensorTime: Double,
                                receivedAt: Double, source: String) {
        guard interruption == nil else { return }
        guard source == self.source else {
            interrupt("The motion source changed. Check the selected earbud, then choose Start over.")
            return
        }
        guard q.vector.indices.allSatisfy({ q.vector[$0].isFinite }), simd_length(q.vector) > 0.001,
              speed.isFinite, speed >= 0, sensorTime.isFinite, receivedAt.isFinite else { return }
        if let latest {
            guard sensorTime > latest.sensorTime, receivedAt >= latest.receivedAt else { return }
            if receivedAt - latest.receivedAt > 0.5 || sensorTime - latest.sensorTime > 0.5 {
                interrupt("Motion was interrupted. Hold the selected earbud and choose Start over.")
                return
            }
        }
        let sample = Sample(q: simd_normalize(q), speed: speed, sensorTime: sensorTime, receivedAt: receivedAt)
        latest = sample
        window.append(sample)
        window.removeAll { receivedAt - $0.receivedAt > 0.40 }
    }

    public func isFresh(at time: Double) -> Bool {
        guard interruption == nil, let latest else { return false }
        return time >= latest.receivedAt && time - latest.receivedAt < 0.25
    }

    /// Hemisphere alignment prevents equivalent q/-q samples from cancelling.
    private func steadyPose(at time: Double) -> simd_quatf? {
        guard isFresh(at: time), let first = window.first, let last = window.last,
              window.count >= 6, last.receivedAt - first.receivedAt >= 0.30,
              last.sensorTime - first.sensorTime >= 0.30 else { return nil }
        var sum = SIMD4<Float>.zero
        for (index, sample) in window.enumerated() {
            guard sample.speed <= 0.45 else { return nil }
            if index > 0, sample.receivedAt - window[index - 1].receivedAt > 0.12 { return nil }
            sum += simd_dot(first.q.vector, sample.q.vector) < 0 ? -sample.q.vector : sample.q.vector
        }
        let average = simd_normalize(simd_quatf(vector: sum))
        for sample in window {
            let spread = simd_length(GripCalibration.rotationVector(reference: average, sample: sample.q))
            guard spread <= 3 * .pi / 180 else { return nil }
        }
        return average
    }

    public func angleDegrees(at time: Double) -> Float? {
        guard isFresh(at: time), let reference, let latest else { return nil }
        return simd_length(GripCalibration.rotationVector(reference: reference, sample: latest.q)) * 180 / .pi
    }

    public func assessment(at time: Double) -> GripCalibration.TiltAssessment? {
        guard isFresh(at: time), let reference, let latest else { return nil }
        let q = steadyPose(at: time) ?? latest.q
        return GripCalibration.assessTilt(GripCalibration.rotationVector(reference: reference, sample: q),
                                         comparedTo: stage == .forward ? left : nil)
    }

    public func preview(at time: Double) -> simd_quatf? {
        guard isFresh(at: time), let reference, let proposedBasis, let latest else { return nil }
        let relative = simd_normalize(reference.inverse * latest.q)
        return simd_normalize(proposedBasis * relative * proposedBasis.inverse)
    }

    public func feedback(at time: Double) -> Feedback {
        func blocked(_ text: String) -> Feedback { Feedback(ready: false, message: text) }
        if let interruption { return blocked(interruption) }
        guard isFresh(at: time) else { return blocked("Waiting for fresh \(source) AirPod motion. No pose can be saved yet.") }
        guard let q = steadyPose(at: time) else { return blocked("Hold the earbud still for a moment (about half a second).") }
        if stage == .neutral { return Feedback(ready: true, message: "Steady. Save this as your upright starting pose.") }
        guard let reference else { return blocked("Starting pose is missing. Choose Start over.") }
        let vector = GripCalibration.rotationVector(reference: reference, sample: q)
        if stage == .returnNeutral || stage == .verify {
            guard simd_length(vector) <= 10 * .pi / 180 else {
                return blocked(stage == .verify ? "Test left, right and toward-screen movement, then return upright to save." : "Return to your saved starting angle. Aim for 0° (within 10° is fine).")
            }
            return Feedback(ready: true, message: stage == .verify ? "If the live blade follows your tilts, save this grip. Otherwise choose Start over." : "Back at your starting angle. Continue to the toward-screen tilt.")
        }
        let assessment = GripCalibration.assessTilt(vector, comparedTo: stage == .forward ? left : nil)
        switch assessment.issue {
        case .tooSmall: return blocked("The sensor has rotated \(Int(assessment.degrees.rounded()))° since your saved start. Tip the same earbud farther; about 30° is a guide, not an exact target.")
        case .tooLarge: return blocked("This is too far from your starting angle. Return upright, then make a smaller tilt.")
        case .sameAxis: return blocked("This is too similar to your left tilt. Return upright, then tip toward the screen, keeping the same grip.")
        case .invalid: return blocked("These poses cannot be compared. Choose Start over.")
        case nil: return Feedback(ready: true, message: "Steady pose. Ready to save this tilt.")
        }
    }

    @discardableResult public mutating func capture(at time: Double) -> Bool {
        guard feedback(at: time).ready, let q = steadyPose(at: time) else { return false }
        switch stage {
        case .neutral:
            reference = q; stage = .left
        case .left:
            guard let reference else { return false }
            left = GripCalibration.rotationVector(reference: reference, sample: q)
            stage = .returnNeutral
        case .returnNeutral:
            stage = .forward // Preserve the original reference for both measured axes.
        case .forward:
            guard let reference, let left,
                  let basis = GripCalibration.basis(left: left, forward: GripCalibration.rotationVector(reference: reference, sample: q)) else { return false }
            proposedBasis = basis; stage = .verify
        case .verify:
            return proposedBasis != nil
        }
        window.removeAll() // Every next pose needs a new steady sample window.
        return true
    }
}
