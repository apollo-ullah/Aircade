import SwiftUI
import simd
import MotionCore

/// Publishes one cursor position regardless of whether a controller or the
/// mouse is driving it, so no view needs to know which is active.
final class PointerModel: ObservableObject {
    enum Source: Equatable { case motion, mouse }

    /// 0...1 across the window, y running downward like screen coordinates.
    @Published private(set) var unitPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var source: Source = .mouse
    @Published private(set) var isLost = false

    /// Angular speed, in rad/s, that counts as a selecting flick.
    var flickThreshold = 3.0
    /// Flicks are ignored for this long after input returns, so the movement of
    /// reconnecting cannot select a channel.
    let activationBlackout = 0.5

    private var tracker = PointerTracker()
    private var swing = SwingDetector()
    private var reacquiredAt: Double?

    /// Returns true when this sample should count as a click.
    @discardableResult
    func ingestMotion(orientation: simd_quatf, sampleAge: Double, speed: Double, time: Double) -> Bool {
        let wasAbsent = source == .mouse || tracker.isLost
        let point = tracker.update(orientation: orientation, sampleAge: sampleAge)
        isLost = tracker.isLost

        guard !tracker.isLost else {
            source = .mouse
            return false
        }
        if wasAbsent { reacquiredAt = time }
        source = .motion
        unitPoint = CGPoint(x: (point.x + 1) / 2, y: (1 - point.y) / 2)

        let flicked = swing.update(speed: speed, time: time, threshold: flickThreshold)
        if let reacquiredAt, time - reacquiredAt < activationBlackout { return false }
        return flicked
    }

    /// Ignored while a controller is driving, so the two sources never fight.
    func ingestMouse(_ unit: CGPoint) {
        guard source == .mouse else { return }
        unitPoint = CGPoint(x: min(1, max(0, unit.x)), y: min(1, max(0, unit.y)))
    }

    func recenter() {
        tracker.reset()
        unitPoint = CGPoint(x: 0.5, y: 0.5)
    }
}
