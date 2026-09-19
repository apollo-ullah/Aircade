import AppKit
import MotionCore
import simd
import SwiftUI

final class TrainingArena: ObservableObject {
    enum Mode: String, CaseIterable { case block = "Slash lab", parry = "Parry drill" }
    var enabled = true
    @Published var mode: Mode = .block { didSet { reset() } }
    @Published var cutDirection = "Any" { didSet { scene?.showCutDirection(cutDirection) } }
    @Published var hits = 0
    @Published var parries = 0
    @Published var misses = 0
    @Published var score = 0
    @Published var combo = 0
    @Published var message = "Cut through the block"
    @Published var detail = "Move the blade across the target. A swing alone does not count."
    @Published var lastEvent = "Ready"
    @Published var sound = true
    @Published var attackInProgress = false
    @Published var inputReady = false
    @Published var contactSpeed: Float = 0
    @Published var cutQuality: Float = 0
    weak var scene: SaberScene?
    var onEvent: ((String) -> Void)?
    private var previous: SaberPose?
    private var previousTime: Double?
    private var respawnAt: Double?
    private var rejectionUntil = 0.0
    private var impactAt: Double?
    private var horizontalGuard = true
    private var attackNumber = 0
    private let target = SIMD3<Float>(0, 1.0, 0)
    private var guardTarget: SIMD3<Float> { horizontalGuard ? SIMD3<Float>(0.8, -0.5, 0) : SIMD3<Float>(0, 0.7, 0) }
    private var currentPose: SaberPose?
    private var lastPoseTime = 0.0
    private var timer: Timer?

    init(scene: SaberScene) {
        self.scene = scene
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        reset()
    }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func reset() {
        hits = 0; parries = 0; misses = 0; score = 0; combo = 0
        previous = nil; previousTime = nil; respawnAt = nil; impactAt = nil; attackInProgress = false
        attackNumber = 0; rejectionUntil = 0; contactSpeed = 0; cutQuality = 0
        message = mode == .block ? "Cut through the block" : "Ready for a parry?"
        detail = mode == .block ? "Move the blade across the target. A swing alone does not count." : "Press Space to launch an attack. Match the ghost blade at impact."
        lastEvent = "Ready"
        scene?.resetTarget(position: target, visible: mode == .block)
        scene?.showCutDirection(cutDirection)
        scene?.hideAttack()
    }

    func invalidateInput() {
        previous = nil; previousTime = nil; currentPose = nil; inputReady = false
        if impactAt != nil {
            impactAt = nil; attackInProgress = false
            scene?.hideAttack()
            message = "Attack paused — tracking lost"
            detail = "Reacquire your hand or recenter, then press Space. No miss counted."
        }
    }

    func update(pose: SaberPose, time: Double, ready: Bool) {
        guard enabled else { return }
        guard ready else { invalidateInput(); return }
        inputReady = true
        currentPose = pose; lastPoseTime = time
        defer { previous = pose; previousTime = time }
        guard mode == .block, respawnAt == nil, let previous, let previousTime else { return }
        guard let hit = CombatGeometry.sweep(from: previous, to: pose, dt: time - previousTime,
                                             center: target, half: SIMD3<Float>(repeating: 0.33)) else { return }
        guard hit.speed >= 0.8 else { return }
        guard time > rejectionUntil else { return }
        contactSpeed = hit.speed; cutQuality = hit.cuttingAlignment
        let xy = SIMD2<Float>(hit.velocity.x, hit.velocity.y)
        let planarSpeed = simd_length(xy)
        var directionOK = true
        if cutDirection != "Any" {
            let desired: SIMD2<Float> = cutDirection == "Left" ? SIMD2(-1, 0) : cutDirection == "Right" ? SIMD2(1, 0) : SIMD2(0, -1)
            directionOK = planarSpeed > 0.1 && simd_dot(xy / planarSpeed, desired) > 0.65
        }
        if hit.cuttingAlignment < 0.35 || !directionOK {
            rejectionUntil = time + 0.45; combo = 0
            message = !directionOK ? "Wrong slash direction" : "Glancing contact"
            detail = !directionOK ? "Follow the arrow on the block." : "Sweep across the blade instead of pushing along it."
            lastEvent = "Glance"
            scene?.impact(at: hit.point, kind: .glance, velocity: hit.velocity)
            play("Tink")
            onEvent?("GLANCE speed=\(hit.speed) alignment=\(hit.cuttingAlignment)")
            return
        }
        hits += 1; combo += 1
        let points = Int(50 + min(50, hit.speed * 7) * hit.cuttingAlignment)
        score += points
        lastEvent = "Cut +\(points)"
        message = hit.cuttingAlignment > 0.85 ? "Clean cut" : "Target hit"
        detail = "\(Int(hit.cuttingAlignment * 100))% cutting angle · \(String(format: "%.1f", hit.speed)) world units/s"
        respawnAt = time + 0.85
        scene?.splitTarget(velocity: hit.velocity)
        scene?.impact(at: hit.point, kind: .cut, velocity: hit.velocity)
        play("Pop")
        onEvent?("CUT points=\(points) speed=\(hit.speed) alignment=\(hit.cuttingAlignment)")
    }

    func launchAttack() {
        guard mode == .parry, !attackInProgress else { return }
        guard inputReady, now - lastPoseTime < 0.25 else {
            message = "Get tracking ready first"; return
        }
        horizontalGuard = attackNumber % 2 == 0
        attackNumber += 1
        impactAt = now + 1.8
        attackInProgress = true
        message = horizontalGuard ? "Overhead attack → horizontal guard" : "Side attack → vertical guard"
        detail = "Place your blade on the ghost. Hold the correct angle as the attack arrives."
        scene?.showAttack(target: guardTarget, horizontalGuard: horizontalGuard)
        onEvent?("ATTACK horizontalGuard=\(horizontalGuard)")
    }

    private func tick() {
        guard enabled else { return }
        let t = now
        if let respawnAt, t >= respawnAt {
            self.respawnAt = nil; previous = nil; previousTime = nil
            scene?.resetTarget(position: target, visible: mode == .block)
            scene?.showCutDirection(cutDirection)
        }
        guard let impactAt else { return }
        guard inputReady, t - lastPoseTime < 0.25 else { invalidateInput(); return }
        let remaining = impactAt - t
        scene?.advanceAttack(remaining: remaining)
        if abs(remaining) <= 0.18, let pose = currentPose,
           CombatGeometry.validGuard(pose: pose, target: guardTarget, horizontal: horizontalGuard) {
            parries += 1; score += 150; combo += 1
            message = "PARRY"; detail = "Angle + position + timing matched. Press Space for the next attack."
            lastEvent = "Parry +150"
            scene?.impact(at: guardTarget, kind: .parry, velocity: SIMD3<Float>(0, 1, 0))
            scene?.hideAttack(); self.impactAt = nil; attackInProgress = false
            play("Glass"); onEvent?("PARRY horizontalGuard=\(horizontalGuard)")
        } else if remaining < -0.18 {
            misses += 1; combo = 0
            message = "Guard missed"; detail = "Match both the ghost blade's position and angle. Press Space to retry."
            lastEvent = "Damage"
            scene?.impact(at: guardTarget, kind: .damage, velocity: .zero)
            scene?.hideAttack(); self.impactAt = nil; attackInProgress = false
            play("Basso"); onEvent?("DAMAGE horizontalGuard=\(horizontalGuard)")
        }
    }
    private func play(_ name: String) {
        if sound { GameAudio.shared.play(name) }
    }
}
